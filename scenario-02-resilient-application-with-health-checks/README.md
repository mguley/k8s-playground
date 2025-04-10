#### Table of Contents

- [Introduction](#introduction)
- [What is Application Resilience?](#what-is-application-resilience)
- [Step 1: Understanding Kubernetes Resilience Features](#step-1-understanding-kubernetes-resilience-features)
- [Step 2: Setting Up Our Environment](#step-2-setting-up-our-environment)
- [Step 3: Creating the Namespace](#step-3-creating-the-namespace)
- [Step 4: Creating ConfigMaps for Application Settings](#step-4-creating-configmaps-for-application-settings)
- [Step 5: Deploying the Main Finance Application](#step-5-deploying-the-main-finance-application)
- [Step 6: Building the Reporting Service](#step-6-building-the-reporting-service)
- [Step 7: Observing Self-Healing in Action](#step-7-observing-self-healing-in-action)
- [Step 8: Implementing Horizontal Pod Autoscaling](#step-8-implementing-horizontal-pod-autoscaling)
- [Step 9: Implementing a Pod Disruption Budget](#step-9-implementing-a-pod-disruption-budget)
- [Step 10: Testing Resilience by Deliberately Causing Failures](#step-10-testing-resilience-by-deliberately-causing-failures)
- [Cleanup](#cleanup)
- [Understanding What Happened Under the Hood](#understanding-what-happened-under-the-hood)

---

#### Introduction

In today's cloud-native landscape, application resilience isn't just a nice-to-have - it's essential.

This tutorial walks through creating a resilient application in Kubernetes that can automatically recover from failures,
representing a real-world scenario where a financial services company needs high-availability systems.

#### What is Application Resilience?

Resilience refers to a system's ability to maintain functionality despite component failures.
In Kubernetes, this translates to:

- Automatic detection of unhealthy applications
- Container restart on failure
- Pod rescheduling when nodes fail
- Dynamic resource scaling
- Continuous availability during maintenance

These capabilities are vital for systems requiring high availability, particularly in financial applications where
downtime can lead to significant losses.

#### Step 1: Understanding Kubernetes Resilience Features

Before building our application, let's understand the key Kubernetes features that enable resilience:

##### Health Checks (Probes)

Kubernetes offers three types of health checks:

1. `Liveness Probe:` Determines if a container is running. If it fails, the container is restarted.
2. `Readiness Probe:` Determines if a container is ready to receive traffic. If it fails, the pod is removed from service endpoints.
3. `Startup Probe:` Determines if an application has started. It disables liveness and readiness checks until it succeeds,
   giving slow-starting applications time to initialize.

##### Self-Healing Mechanisms

Kubernetes provides several self-healing features:

- `ReplicaSets:` Maintain the desired number of pod replicas
- `Node Controller:` Monitors node health and evicts pods from unhealthy nodes
- `Kubelet:` Restarts containers that fail their liveness probes
- `Control Plane Redundancy:` In production environments, the control plane components are typically replicated

##### Horizontal Pod Autoscaler (HPA)

The HPA automatically scales the number of pods based on metrics like CPU utilization or memory usage.

##### Pod Disruption Budget (PDB)

PDBs limit the number of pods that can be down simultaneously during voluntary disruptions, ensuring service availability
during cluster maintenance.

#### Step 2: Setting Up Our Environment

First, let's create a Kubernetes cluster for our resilient application. We have an option to deploy the Metrics Server automatically
along with the cluster.

To create a cluster and deploy Metrics Server, run:

```bash
bash k8s-cluster-manager.sh create resilient-app-cluster 3 kindest/node:v1.31.2 deploy-metrics
```

This Metrics Server is crucial for collecting resource metrics (like CPU usage) used by Horizontal Pod Autoscalers and
other monitoring tools.

If you prefer not to deploy the Metrics Server at cluster creation time:

```bash
bash k8s-cluster-manager.sh create resilient-app-cluster 3
```

This creates a cluster with one control plane node and two worker nodes.

#### Step 3: Creating the Namespace

Let's create a dedicated namespace for our resilient application:

```bash
cat > finance-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: finance
  labels:
    name: finance
EOF

kubectl apply -f finance-namespace.yaml
```

Set this namespace as our default context:

```bash
kubectl config set-context --current --namespace=finance
```

#### Step 4: Creating ConfigMaps for Application Settings

Let's create ConfigMaps with configuration for our applications:

```bash
cat > finance-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: finance-app-config
  namespace: finance
data:
  APP_MODE: "production"
  RESPONSE_DELAY_MS: "100"
  STARTUP_DELAY_SEC: "10"
  FAILURE_RATE: "0.0"  # Probability of simulated failure (0.0 - 1.0)
EOF

kubectl apply -f finance-config.yaml
```

And for our reporting service that will occasionally fail:

```bash
cat > failing-app-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: failing-app-config
  namespace: finance
data:
  STARTUP_DELAY_SEC: "5"
  FAILURE_RATE: "0.3"                   # 30% chance of liveness failures
  LIVENESS_FAILURE_DURATION: "20"       # How long liveness failures last (seconds)
  READINESS_FAILURE_DURATION: "15"      # How long readiness failures last (seconds)
  READINESS_FAILURE_RATE: "0.15"        # 15% chance of readiness failures (separate from liveness)
  SIMULATE_RESOURCE_EXHAUSTION: "false"
EOF

kubectl apply -f failing-app-config.yaml
```

#### Step 5: Deploying the Main Finance Application

Now, let's create a deployment for our main application that includes all three types of health checks:

```bash
cat > resilient-app.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: finance-app
  namespace: finance
spec:
  replicas: 3
  selector:
    matchLabels:
      app: finance-app
  template:
    metadata:
      labels:
        app: finance-app
    spec:
      containers:
        - name: finance-app
          image: nginx:alpine
          command: ["/bin/sh", "-c"]
          args:
            - |
              # Create a simple web server that simulates a financial application
              mkdir -p /usr/share/nginx/html/health /usr/share/nginx/html/ready /usr/share/nginx/html/startup
              
              # Create index.html
              cat > /usr/share/nginx/html/index.html << 'EOL'
              <!DOCTYPE html>
              <html>
              <head>
                <title>Financial Services Dashboard</title>
                <style>
                  body {
                    font-family: Arial, sans-serif;
                    margin: 0;
                    padding: 20px;
                    background-color: #f0f2f5;
                  }
                  .dashboard {
                    max-width: 800px;
                    margin: 0 auto;
                    background-color: #fff;
                    padding: 20px;
                    border-radius: 8px;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                  }
                  header {
                    background-color: #0066b2;
                    color: white;
                    padding: 20px;
                    border-radius: 8px 8px 0 0;
                    margin: -20px -20px 20px;
                  }
                  h1 {
                    margin: 0;
                  }
                  .status {
                    padding: 15px;
                    border-radius: 4px;
                    margin-bottom: 15px;
                    background-color: #d4edda;
                    border: 1px solid #c3e6cb;
                    color: #155724;
                  }
                  .metrics {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 20px;
                    margin-bottom: 20px;
                  }
                  .metric-card {
                    flex: 1;
                    min-width: 200px;
                    padding: 15px;
                    background-color: #e9ecef;
                    border-radius: 4px;
                    text-align: center;
                  }
                  .metric-value {
                    font-size: 24px;
                    font-weight: bold;
                    margin: 10px 0;
                    color: #0066b2;
                  }
                  .container-info {
                    font-family: monospace;
                    background-color: #f8f9fa;
                    padding: 15px;
                    border-radius: 4px;
                    margin-top: 20px;
                  }
                </style>
              </head>
              <body>
                <div class="dashboard">
                  <header>
                    <h1>Financial Services Dashboard</h1>
                  </header>
              
                  <div class="status">
                    System Status: <strong>Operational</strong>
                  </div>
              
                  <div class="metrics">
                    <div class="metric-card">
                      <div>Transactions Processed</div>
                      <div class="metric-value">28,745</div>
                      <div>Today</div>
                    </div>
                    <div class="metric-card">
                      <div>System Uptime</div>
                      <div class="metric-value">99.99%</div>
                      <div>Last 30 days</div>
                    </div>
                    <div class="metric-card">
                      <div>Response Time</div>
                      <div class="metric-value">142 ms</div>
                      <div>Average</div>
                    </div>
                  </div>
              
                  <div class="container-info">
                    <p>Container ID: <span id="hostname">loading...</span></p>
                    <p>Pod IP: <span id="ip">loading...</span></p>
                    <p>Started at: <span id="startTime">loading...</span></p>
                  </div>
                </div>
              
                <script>
                  // Fill in container information
                  document.getElementById('hostname').textContent = location.hostname;
                  document.getElementById('startTime').textContent = new Date().toISOString();
              
                  // Fetch the IP address
                  fetch('/ip')
                    .then(response => response.text())
                    .then(ip => {
                      document.getElementById('ip').textContent = ip;
                    })
                    .catch(error => {
                      document.getElementById('ip').textContent = 'Error fetching IP';
                    });
                </script>
              </body>
              </html>
              EOL
              
              # Create a readiness probe endpoint
              cat > /usr/share/nginx/html/ready/index.html << 'EOL'
              OK
              EOL
              
              # Create a liveness probe endpoint
              cat > /usr/share/nginx/html/health/index.html << 'EOL'
              OK
              EOL
              
              # Start a background process to simulate application startup
              echo "Simulating application startup - will take ${STARTUP_DELAY_SEC} seconds..."
              (
                sleep "${STARTUP_DELAY_SEC}"
                echo "Application started, creating startup probe endpoint"
                mkdir -p /usr/share/nginx/html/startup
                echo "OK" > /usr/share/nginx/html/startup/index.html
              ) &
              
              # Start a monitoring process to simulate occasional failures if FAILURE_RATE > 0
              (
                while true; do
                  if [ $(echo "scale=2; ${FAILURE_RATE} > 0" | bc -l) -eq 1 ]; then
                    # Generate a random number between 0 and 1
                    RANDOM_VALUE=$(awk -v min=0 -v max=1 'BEGIN{srand(); print min+rand()*(max-min)}')
              
                    # If random value is less than FAILURE_RATE, simulate a failure
                    if [ $(echo "scale=2; ${RANDOM_VALUE} < ${FAILURE_RATE}" | bc -l) -eq 1 ]; then
                      echo "Simulating a failure for the liveness probe"
                      echo "ERROR" > /usr/share/nginx/html/health/index.html
                      sleep 5
                      echo "Restoring health endpoint"
                      echo "OK" > /usr/share/nginx/html/health/index.html
                    fi
                  fi
                  sleep 30
                done
              ) &
              
              # Start nginx in the foreground
              nginx -g "daemon off;"
          ports:
            - containerPort: 80
          envFrom:
            - configMapRef:
                name: finance-app-config
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"

          # Check if the application is alive
          livenessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
            successThreshold: 1

          # Check if the application is ready to serve traffic
          readinessProbe:
            httpGet:
              path: /ready
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 2
            successThreshold: 1

          # Check if the application has finished startup
          startupProbe:
            httpGet:
              path: /startup
              port: 80
            failureThreshold: 30  # Allow up to 5 minutes (30 * 10s) for startup
            periodSeconds: 10
EOF

kubectl apply -f resilient-app.yaml
```

Let's also create a service to expose our application:

```bash
cat > finance-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: finance-app
  namespace: finance
spec:
  selector:
    app: finance-app
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
EOF

kubectl apply -f finance-service.yaml
```

#### Step 6: Building the Reporting Service

Now let's create a service that will occasionally fail, to demonstrate Kubernetes' self-healing capabilities.

First, create the simulation script:

```bash
cat > simulate.sh << 'EOF'
#!/usr/bin/env sh
# Resilient application simulation script for Kubernetes health checks
# This script simulates realistic application behavior including:
# - Startup delays
# - Occasional liveness failures (to demonstrate pod restarts)
# - Occasional readiness failures (to demonstrate traffic routing)

# Exit immediately if a command exits with a non-zero status
# Print commands before execution
# Treat unset variables as an error
set -eux

# Configurable parameters (set as environment variables or use defaults)
: "${STARTUP_DELAY_SEC:=5}"
: "${FAILURE_RATE:=0.3}"
: "${LIVENESS_FAILURE_DURATION:=20}"       # How long to fail liveness checks (seconds)
: "${READINESS_FAILURE_DURATION:=15}"      # How long to fail readiness checks (seconds)
: "${READINESS_FAILURE_RATE:=0.15}"        # Probability of readiness failures
: "${SIMULATE_RESOURCE_EXHAUSTION:=false}" # Whether to simulate CPU/memory exhaustion

WEB_ROOT="/usr/share/nginx/html"
HEALTH_PATH="${WEB_ROOT}/health"
READY_PATH="${WEB_ROOT}/ready"
STARTUP_PATH="${WEB_ROOT}/startup"

# Trap to handle cleanup on script termination
cleanup() {
  echo "Cleaning up and exiting..."
  # Kill any background processes we've started
  jobs -p | xargs -r kill
  exit 0
}
trap cleanup SIGTERM SIGINT

# Create web directories
echo "Initializing web directories..."
mkdir -p "${HEALTH_PATH}" "${READY_PATH}" "${STARTUP_PATH}"

# Create a custom 503 error page
cat > "${WEB_ROOT}/503.html" << 'EOL'
<!DOCTYPE html>
<html>
<head>
  <title>Service Temporarily Unavailable</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 50px; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 5px; }
    h1 { color: #d9534f; }
    .timestamp { color: #666; font-size: 0.8em; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Service Temporarily Unavailable</h1>
    <p>The service is currently experiencing a simulated failure for demonstration purposes.</p>
    <p>This page indicates that the service has detected a problem and is properly reporting its unavailability.</p>
    <p class="timestamp">Generated at: <span id="timestamp"></span></p>
  </div>
  <script>
    document.getElementById('timestamp').textContent = new Date().toISOString();
  </script>
</body>
</html>
EOL

# 1) Simulate application startup process
echo "Simulating application startup process (${STARTUP_DELAY_SEC}s)..."
sleep "${STARTUP_DELAY_SEC}"

# Initialize health endpoints
echo "OK" > "${HEALTH_PATH}/index.html"
echo "OK" > "${READY_PATH}/index.html"

# Record startup time
START_TIME=$(date +%s)
echo "Application started at: $(date)"
echo "OK" > "${STARTUP_PATH}/index.html"

# 2) Function to simulate liveness failures
simulate_liveness_failure() {
  echo "$(date) [FAILURE] Simulating liveness probe failure..."
  # Remove the file to cause 404
  rm -f "${HEALTH_PATH}/index.html"

  sleep "${LIVENESS_FAILURE_DURATION}"

  # If container hasn't been restarted by now, restore health
  if [ -d "${HEALTH_PATH}" ]; then
    echo "$(date) [RECOVERY] Restoring liveness endpoint..."
    echo "OK" > "${HEALTH_PATH}/index.html"
  fi
}

# 3) Function to simulate readiness failures (service remains alive but not ready for traffic)
simulate_readiness_failure() {
  echo "$(date) [DEGRADED] Simulating readiness probe failure..."
  # Remove the file to cause 404
  rm -f "${READY_PATH}/index.html"

  sleep "${READINESS_FAILURE_DURATION}"

  echo "$(date) [RESTORED] Restoring readiness endpoint..."
  echo "OK" > "${READY_PATH}/index.html"
}

# 4) Function to simulate high CPU usage
simulate_cpu_load() {
  echo "$(date) [RESOURCE] Simulating high CPU usage for 10 seconds..."
  # Create CPU load with a calculation loop
  for i in $(seq 1 2); do
    # Start a background process that creates CPU load
    (
      end=$((SECONDS+5))
      while [ $SECONDS -lt $end ]; do
        # Heavy math calculation to create CPU load
        for j in $(seq 1 10000); do
          echo "scale=10; s($j) * c($j)" | bc -l >/dev/null 2>&1
        done
      done
    ) &
  done
  sleep 10
  echo "$(date) [RESOURCE] CPU load simulation completed"
}

# 5) Start failure simulation loop in background
(
  # Give the container time to stabilize before starting failure simulations
  sleep 30

  while true; do
    # Calculate uptime
    CURRENT_TIME=$(date +%s)
    UPTIME=$((CURRENT_TIME - START_TIME))

    echo "Current uptime: ${UPTIME}s, FAILURE_RATE=${FAILURE_RATE}"

    # Simulate liveness failure based on probability
    if [ "${FAILURE_RATE}" != "0" ]; then
      RAND_LIVENESS=$(awk "BEGIN{printf \"%.2f\", ${RANDOM}/32767}")
      if [ "$(echo "${RAND_LIVENESS} < ${FAILURE_RATE}" | bc -l)" -eq 1 ]; then
        simulate_liveness_failure
      fi
    fi

    # Sleep between checks to prevent too frequent failures
    sleep 20

    # Simulate readiness failures (separate from liveness)
    if [ "${READINESS_FAILURE_RATE}" != "0" ]; then
      RAND_READINESS=$(awk "BEGIN{printf \"%.2f\", ${RANDOM}/32767}")
      if [ "$(echo "${RAND_READINESS} < ${READINESS_FAILURE_RATE}" | bc -l)" -eq 1 ]; then
        simulate_readiness_failure
      fi
    fi

    # Optionally simulate CPU load (if enabled)
    if [ "${SIMULATE_RESOURCE_EXHAUSTION}" = "true" ]; then
      RAND_RESOURCE=$(awk "BEGIN{printf \"%.2f\", ${RANDOM}/32767}")
      if [ "$(echo "${RAND_RESOURCE} < 0.1" | bc -l)" -eq 1 ]; then
        simulate_cpu_load
      fi
    fi

    # Sleep between simulations to prevent too frequent failures
    sleep 40
  done
) &

# 6) Start nginx in the foreground
echo "Starting nginx..."
exec nginx -g 'daemon off;'
EOF

chmod +x simulate.sh
```

Next, create a Dockerfile for the reporting service:

```bash
cat > Dockerfile.reporting << 'EOF'
FROM nginx:alpine

RUN apk add --no-cache bc gawk

COPY simulate.sh /usr/local/bin/simulate.sh
RUN chmod +x /usr/local/bin/simulate.sh

ENTRYPOINT ["/usr/local/bin/simulate.sh"]
EOF
```

Build and load the image into the cluster:

```bash
docker build -t reporting-service:local -f Dockerfile.reporting .
kind load docker-image reporting-service:local --name resilient-app-cluster
```

Now deploy the reporting service:

```bash
cat > failing-app.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reporting-service
  namespace: finance
  annotations:
    description: "Reporting service with simulated failures for K8s resilience demo"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: reporting-service
  template:
    metadata:
      labels:
        app: reporting-service
    spec:
      containers:
        - name: reporting-service
          image: reporting-service:local
          ports:
            - containerPort: 80
          envFrom:
            - configMapRef:
                name: failing-app-config
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "100m"
          # Check if the application is alive
          livenessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 2
            successThreshold: 1
          # Check if the application is ready to serve traffic
          readinessProbe:
            httpGet:
              path: /ready
              port: 80
            initialDelaySeconds: 3
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 2
            successThreshold: 1
EOF

kubectl apply -f failing-app.yaml
```

Let's expose this service as well:

```bash
cat > reporting-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: reporting-service
  namespace: finance
spec:
  selector:
    app: reporting-service
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
EOF

kubectl apply -f reporting-service.yaml
```

#### Step 7: Observing Self-Healing in Action

Now that we have both applications running, let's observe how Kubernetes handles the occasionally failing reporting service.

Watch the status of our pods:

```bash
watch kubectl get pods -n finance
```

You'll observe:

1. Pods for the `reporting-service` occasionally failing health checks
2. Kubernetes automatically restarting the containers when they fail
3. The restart count incrementing in the `RESTARTS` column

You can also check the detailed events for a specific pod:

```bash
# Press Ctrl+C to exit the watch command first
FAILING_POD=$(kubectl get pods -n finance -l app=reporting-service -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $FAILING_POD -n finance
```

In the output, look for events related to:
- Container killing
- Container creating
- Started container
- Unhealthy

To review logs:

```bash
kubectl logs -n finance -l app=reporting-service --tail=50
```

This demonstrates how Kubernetes automatically detects and recovers from application failures.

#### Step 8: Implementing Horizontal Pod Autoscaling

Now, let's implement horizontal pod autoscaling for our main application based on CPU usage:

```bash
cat > finance-hpa.yaml << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: finance-app-hpa
  namespace: finance
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: finance-app
  minReplicas: 1
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 45
EOF

kubectl apply -f finance-hpa.yaml
```

This HPA will:
- Target our `finance-app` deployment
- Maintain between 1 and 10 replicas
- Scale up when CPU utilization exceeds 45%
- Scale down when CPU utilization falls below 45%

Check the status of the HPA:

```bash
kubectl get hpa -n finance
```

You'll see the current, target, and max number of replicas along with the current CPU utilization.

#### Step 9: Implementing a Pod Disruption Budget

A Pod Disruption Budget (PDB) ensures that a minimum number of pods remain available during voluntary disruptions like
upgrades or node maintenance:

```bash
cat > finance-pdb.yaml << 'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: finance-app-pdb
  namespace: finance
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: finance-app
EOF

kubectl apply -f finance-pdb.yaml
```

This PDB ensures that at least 2 pods of our `finance-app` are always available, even during maintenance operations.

Check the status of the PDB:

```bash
kubectl get pdb -n finance
```

#### Step 10: Testing Resilience by Deliberately Causing Failures

Let's test our application's resilience by deliberately causing some failures.

`Test 1: Delete a pod to simulate a crash`

Let's manually delete a pod to see Kubernetes recreate it:

```bash
POD_TO_DELETE=$(kubectl get pods -n finance -l app=finance-app -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $POD_TO_DELETE -n finance
```

Quickly check the pods:

```bash
kubectl get pods -n finance -l app=finance-app
```

You'll see that Kubernetes immediately starts creating a new pod to replace the one you deleted, maintaining the desired
number of replicas.

`Test 2: Simulate high load`

We can simulate high CPU load to test the Horizontal Pod Autoscaler:

```bash
cat > load-generator.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: load-generator-ab
  namespace: finance
spec:
  template:
    spec:
      containers:
        - name: load-generator-ab
          # Use an image that has ApacheBench installed (for instance, a custom image or one from docker hub)
          image: jordi/ab
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "Starting load test using ApacheBench..."
              # -n: total number of requests (set high if using -t),
              # -c: concurrency level, and
              # -t: test duration in seconds.
              ab -n 1000000 -c 200 -t 300 http://finance-app.finance.svc.cluster.local/
              echo "Load test complete."
      restartPolicy: Never
  backoffLimit: 4
EOF

kubectl apply -f load-generator.yaml
```

Now monitor the HPA to see if it scales up the deployment:

```bash
watch kubectl get hpa -n finance
```

Depending on the actual load generated, you might see the CPU utilization increase and the HPA scale up the number of replicas.

You can also get more details about the HPA:

```bash
kubectl describe hpa finance-app-hpa -n finance
```

This will show current CPU utilization values and scaling decisions.

#### Cleanup

When you're done, you can clean up all resources:

```bash
# Delete the namespace (this will delete everything in it)
kubectl delete namespace finance

# Or delete the entire cluster
bash k8s-cluster-manager.sh delete resilient-app-cluster
```

#### Understanding What Happened Under the Hood

We've successfully built a resilient application architecture in Kubernetes that can:

1. Automatically detect and recover from failures using health checks
2. Maintain the desired number of replicas even when pods fail
3. Scale resources up and down based on load
4. Protect availability during maintenance operations

The key components we implemented:

1. `Health Checks (Probes):` We used all three types of probes:
    - Liveness probe to detect and restart unhealthy containers
    - Readiness probe to control traffic routing
    - Startup probe to allow for application initialization

2. `Self-Healing:` We demonstrated Kubernetes' ability to:
    - Automatically restart containers when they fail health checks
    - Maintain the desired number of replicas

3. `Automatic Scaling:` We implemented Horizontal Pod Autoscaler to:
    - Scale up when demand increases
    - Scale down when demand decreases

4. `Availability Protection:` We used Pod Disruption Budget to:
    - Ensure minimum availability during voluntary disruptions
    - Protect against accidental outages during maintenance
