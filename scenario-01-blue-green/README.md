We'll simulate a real-world situation where a web development team needs to update their application without any
downtime for users.

This technique is called a `"blue-green deployment"` strategy.

#### What is Blue-Green Deployment?
Blue-green deployment is a release management strategy that maintains two identical production environments, called `"blue"`
(current version) and `"green"` (new version).

1. Initially, all user traffic goes to the `blue` environment.
2. The new version is deployed to the `green` environment.
3. The `green` environment is tested to ensure it works properly.
4. Traffic is switched from `blue` to `green`.
5. If issues are found, traffic can be quickly switched back to `blue`.

This approach eliminates downtime and reduces risk when deploying new application versions.

##### Step 1: Setting Up the Cluster

First, let's use the script to create a Kubernetes cluster with three nodes:
```bash
bash k8s-cluster-manager.sh create blue-green-cluster 3
```

This will:
- Create a Kubernetes cluster named `"blue-green-cluster"`
- Set up one control plane node and two worker nodes
- Configure kubectl to interact with this cluster

##### Step 2: Create the Version 1 (Blue) Deployment

Let's create a file called `blue-deployment.yaml` for our first version:

```bash
cat > blue-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app-v1
  labels:
    app: web-app
    version: v1
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
      version: v1
  template:
    metadata:
      labels:
        app: web-app
        version: v1
    spec:
      containers:
      - name: web-app
        image: nginx:1.19
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        volumeMounts:
        - name: content-volume
          mountPath: /usr/share/nginx/html
      volumes:
      - name: content-volume
        configMap:
          name: web-content-v1
EOF
```

This YAML file defines:
- A Deployment named `"web-app-v1"`
- 3 replica pods running nginx version 1.19
- Resource limits to ensure stable operation
- Labels for `"app: web-app"` and `"version: v1"`
- A volume mount to inject custom content

Now, let's create a ConfigMap with the content for our v1 application:

```bash
cat > v1-content-configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-content-v1
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
      <title>Web App - Version 1</title>
      <style>
        body {
          background-color: #3498db; /* Blue background */
          color: white;
          font-family: Arial, sans-serif;
          text-align: center;
          padding-top: 100px;
        }
      </style>
    </head>
    <body>
      <h1>Version 1 (Blue)</h1>
      <p>This is version 1 of our web application.</p>
    </body>
    </html>
EOF
```

This ConfigMap contains an HTML file that clearly identifies itself as version 1 with a blue background.

Let's apply these files to create the resources:

```bash
kubectl apply -f v1-content-configmap.yaml
kubectl apply -f blue-deployment.yaml
```

Let's check if the pods are running:

```bash
kubectl get pods --selector=app=web-app,version=v1
```

You should see 3 pods in the `"Running"` state. It might take a few moments for all pods to be ready.

##### Step 3: Create a Service to Expose the Application

Now let's create a Service to expose our application:

```bash
cat > web-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web-app-service
spec:
  selector:
    app: web-app
    version: v1  # Initially points to version 1 (blue)
  ports:
  - port: 80
    targetPort: 80
  type: NodePort
EOF
```

This Service:
- Is named `"web-app-service"`
- Selects pods with labels `"app: web-app"` and `"version: v1"`
- Maps port 80 on the service to port 80 on the pods
- Uses NodePort to make it accessible outside the cluster

Let's apply this file:
```bash
kubectl apply -f web-service.yaml
```

Now, let's check what port has been assigned to our service:
```bash
kubectl get services web-app-service
```

Look for the `"PORT(S)"` column, which should show something like `"80:31XXX/TCP"`. The number after the colon `(31XXX)`
is your NodePort.

##### Step 4: Testing the V1 (Blue) Application

Since we're using kind, we need to forward a port to access our service:

```bash
# Forward that port to localhost
kubectl port-forward --address 0.0.0.0 service/web-app-service 8080:80
```

Now you can access the application by opening a web browser and navigating to:

```
http://localhost:8080/
```

You should see a blue page that says `"Version 1 (Blue)"`

##### Step 5: Create the Version 2 (Green) Deployment

Now, let's create a new deployment for version 2 of our application:

```bash
cat > green-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app-v2
  labels:
    app: web-app
    version: v2
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
      version: v2
  template:
    metadata:
      labels:
        app: web-app
        version: v2
    spec:
      containers:
      - name: web-app
        image: nginx:1.20
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        volumeMounts:
        - name: content-volume
          mountPath: /usr/share/nginx/html
      volumes:
      - name: content-volume
        configMap:
          name: web-content-v2
EOF
```

This is similar to our v1 deployment, but with:
- Different deployment name: `"web-app-v2"`
- Different version label: `"version: v2"`
- Newer nginx image: 1.20 instead of 1.19
- Reference to a new ConfigMap: `"web-content-v2"`

Let's create a ConfigMap for the v2 content:
```bash
cat > v2-content-configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-content-v2
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
      <title>Web App - Version 2</title>
      <style>
        body {
          background-color: #2ecc71; /* Green background */
          color: white;
          font-family: Arial, sans-serif;
          text-align: center;
          padding-top: 100px;
        }
      </style>
    </head>
    <body>
      <h1>Version 2 (Green)</h1>
      <p>This is version 2 of our web application.</p>
      <p>We've added this new paragraph as a feature!</p>
    </body>
    </html>
EOF
```

This new version has a green background and additional content.
Let's apply these files:

```bash
kubectl apply -f v2-content-configmap.yaml
kubectl apply -f green-deployment.yaml
```

Check if the v2 pods are running:
```bash
kubectl get pods --selector=app=web-app,version=v2
```

##### Step 6. Verify Both Versions are Running

Let's check all running pods across both versions:

```bash
kubectl get pods --selector=app=web-app
```

You should see 6 pods in total - 3 for v1 and 3 for v2.

But if you check your browser, the service is still showing version 1. This is because our service is still selecting
pods with `version: v1`.

##### Step 7. Test the Green Deployment Before Switching

Before we switch traffic to v2, let's make sure it's working correctly. We can create a temporary service just for testing:

```bash
cat > green-test-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web-app-v2-test
spec:
  selector:
    app: web-app
    version: v2
  ports:
  - port: 80
    targetPort: 80
  type: NodePort
EOF
```

Apply this test service:

```bash
kubectl apply -f green-test-service.yaml
```

In a new terminal window, set up port-forwarding for the test service:

```bash
kubectl port-forward --address 0.0.0.0 service/web-app-v2-test 8081:80
```

Now visit:

```
http://localhost:8081
```

You should see a green page that says `"Version 2 (Green)"` with the additional paragraph we added.

##### Step 8. Switch Traffic to the Green Deployment

Now that we've verified the green deployment is working correctly, we can switch our main service to direct traffic to it.

We'll edit the original service to change the selector:

```bash
cat > web-service-v2.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web-app-service
spec:
  selector:
    app: web-app
    version: v2  # Now points to version 2 (green)
  ports:
  - port: 80
    targetPort: 80
  type: NodePort
EOF
```

Apply the updated service:

```bash
kubectl apply -f web-service-v2.yaml
```

We also need to restart port forwarding

```bash
kubectl port-forward --address 0.0.0.0 service/web-app-service 8080:80
```

Now if you refresh your browser at `http://localhost:8080/`, after a moment, you should see the green version 2 page.

##### Step 9. Verify the Switch Was Successful

Let's check which pods our service is now selecting:

```bash
kubectl describe service web-app-service
```

In the output, look for the `"Endpoints"` field. It should show the IP addresses of the version 2 pods.

##### Step 10. Clean Up After Successful Deployment

After confirming that the switch to version 2 was successful and everything is working properly, we can clean up the
version 1 resources:

```bash
# Delete the v1 deployment
kubectl delete deployment web-app-v1

# Delete the v1 ConfigMap
kubectl delete configmap web-content-v1

# Delete the test service
kubectl delete service web-app-v2-test
```

##### Step 11. Rollback Scenario (Optional)

Let's say we discovered a critical issue with version 2 after switching.
Here's how we would quickly roll back to version 1:

```bash
# Update the service to point back to version 1
cat > web-service-rollback.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web-app-service
spec:
  selector:
    app: web-app
    version: v1  # Back to version 1 (blue)
  ports:
  - port: 80
    targetPort: 80
  type: NodePort
EOF

# Apply the rollback
kubectl apply -f web-service-rollback.yaml
```

However, since we deleted our version 1 deployment in the previous step, we would need to recreate it first:

```bash
kubectl apply -f v1-content-configmap.yaml
kubectl apply -f blue-deployment.yaml
```

After a moment, services would be redirected back to version 1, and users would see the blue page again.

##### Cleanup

When you're done, you can clean up all resources:

```bash
# Delete all resources
kubectl delete service web-app-service
kubectl delete deployment web-app-v2
kubectl delete configmap web-content-v2

# Or delete everything by deleting the cluster
bash k8s-cluster-manager.sh delete blue-green-cluster
```

##### Understanding What Happened Under the Hood

We successfully implemented a blue-green deployment strategy:

1. We started with version 1 (`blue`) running and serving all traffic
2. We deployed version 2 (`green`) alongside version 1
3. We tested version 2 to make sure it worked properly
4. We switched traffic from version 1 to version 2 by updating the service selector
5. We demonstrated how to roll back if needed

The key to this strategy is that we never had any downtime.

Version 2 was fully deployed and ready before we switched any traffic to it, and the switch itself was instantaneous 
from a user perspective.