#### Table of Contents

- [Introduction](#introduction)
- [What is Kubernetes Security?](#what-is-kubernetes-security)
- [Step 1: Understanding Key Kubernetes Security Concepts](#step-1-understanding-key-kubernetes-security-concepts)
- [Step 2: Setting Up the Cluster](#step-2-setting-up-the-cluster)
- [Step 3: Create a Namespace with Resource Quotas](#step-3-create-a-namespace-with-resource-quotas)
- [Step 4: Generate Kubernetes Secrets for Sensitive Configuration](#step-4-generate-kubernetes-secrets-for-sensitive-configuration)
- [Step 5: Create a Simple Database Service](#step-5-create-a-simple-database-service)
- [Step 6: Deploy a Healthcare Application with Secrets](#step-6-deploy-a-healthcare-application-with-secrets)
- [Step 7: Implement Network Policies](#step-7-implement-network-policies)
- [Step 8: Set up RBAC for Limited Access](#step-8-set-up-rbac-for-limited-access)
- [Step 9: Setting Up a NodePort Service for External Access](#step-9-setting-up-a-nodeport-service-for-external-access)
- [Step 10: Testing the Secure Application](#step-10-testing-the-secure-application)
- [Cleanup](#cleanup)
- [Understanding What Happened Under the Hood](#understanding-what-happened-under-the-hood)

---

#### Introduction

In this scenario, we'll implement a healthcare application with strict security requirements. Healthcare applications
handle sensitive patient data and must comply with regulations like HIPAA (Health Insurance Portability and Accountability Act)
in the US or GDPR in Europe, making security a critical concern.

#### What is Kubernetes Security?

Kubernetes provides powerful tools for deploying and scaling applications, but without proper security measures, these
same capabilities can expose your applications to risks.

In a healthcare context, security breaches can lead to:
- Exposure of protected health information (PHI)
- Regulatory violations with significant penalties
- Loss of patient trust
- Legal liability

We will demonstrate how Kubernetes provides multiple layers of security that work together to protect your applications and data.

#### Step 1: Understanding Key Kubernetes Security Concepts

Before we start building, let's review the key security concepts in Kubernetes:

`Namespaces with Resource Quotas`
- Logical partitions that provide scope for names and policies
- Resource quotas limit the total resources that can be consumed
- Prevent a single application from consuming all cluster resources

`Kubernetes Secrets`
- Store sensitive information like passwords, tokens, and keys
- Base64 encoded (but not encrypted by default)
- Can be mounted as files or exposed as environment variables
- Should be combined with RBAC to limit who can access them

`Network Policies`
- Act like a firewall for pod-to-pod communication
- Define rules for ingress (incoming) and egress (outgoing) traffic
- Allow you to isolate workloads and limit exposure

`Role-Based Access Control (RBAC)`
- Control who can perform actions on Kubernetes resources
- Based on roles (collections of permissions) and bindings (assignments of roles to users)
- Follow the principle of the least privilege

`Security Contexts`
- Control security settings for pods and containers
- Define user/group IDs, capabilities, and privilege settings
- Limit what containers can do to enhance security

`Sidecar Containers`
- Additional containers in the same pod that enhance the main application
- Can handle security concerns like TLS termination
- Allow separation of concerns between application and security logic

#### Step 2: Setting Up the Cluster

Let's create a new Kubernetes cluster for our secure healthcare application:

```bash
bash k8s-cluster-manager.sh create secure-app-cluster 3
```

This creates a cluster with one control plane node and two worker nodes.

#### Step 3: Create a Namespace with Resource Quotas

Let's create a dedicated namespace for our healthcare application with resource quotas to limit resource usage:

```bash
cat > healthcare-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: healthcare
  labels:
    name: healthcare
    environment: production
    compliance: hipaa
EOF
```

Apply this manifest to create the namespace:

```bash
kubectl apply -f healthcare-namespace.yaml
```

Now, let's create resource quotas for this namespace to limit resource consumption:

```bash
cat > healthcare-quota.yaml << 'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: healthcare-quota
  namespace: healthcare
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    pods: "20"
    services: "10"
    secrets: "20"
    configmaps: "20"
EOF
```

Apply the resource quota:

```bash
kubectl apply -f healthcare-quota.yaml
```

Set this namespace as our default context:

```bash
kubectl config set-context --current --namespace=healthcare
```

Verify that the namespace and quota were created:

```bash
kubectl get namespace healthcare
kubectl describe resourcequota healthcare-quota
```

#### Step 4: Generate Kubernetes Secrets for Sensitive Configuration

Now, let's create Kubernetes Secrets to store sensitive information our application will need:

```bash
cat > healthcare-secrets.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: healthcare-db-credentials
  namespace: healthcare
type: Opaque
data:
  # These values are base64 encoded
  # In a real scenario, you would never store these in version control
  # You can generate them with: echo -n "value" | base64
  username: YWRtaW4=  # admin
  password: cGFzc3dvcmQxMjM=  # password123
  database: cGF0aWVudGRi  # patientdb
  connection-string: cG9zdGdyZXNxbDovL2FkbWluOnBhc3N3b3JkMTIzQGhlYWx0aGNhcmUtZGI6NTQzMi9wYXRpZW50ZGI=  # postgresql://admin:password123@healthcare-db:5432/patientdb
---
apiVersion: v1
kind: Secret
metadata:
  name: healthcare-api-keys
  namespace: healthcare
type: Opaque
data:
  external-api-key: VGhpc0lzQVNlY3JldEFQSUtleQ==  # ThisIsASecretAPIKey
  encryption-key: U2VjdXJlRW5jcnlwdGlvbktleUZvckFwcGxpY2F0aW9uRGF0YQ==  # SecureEncryptionKeyForApplicationData
EOF
```

Apply these secrets:

```bash
kubectl apply -f healthcare-secrets.yaml
```

Verify that the secrets were created:

```bash
kubectl get secrets -n healthcare
```

#### Step 5: Create a Simple Database Service

Let's create a simple database service that our healthcare application will connect to:

```bash
cat > healthcare-db.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: healthcare-db
  namespace: healthcare
  labels:
    app: healthcare-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: healthcare-db
  template:
    metadata:
      labels:
        app: healthcare-db
    spec:
      securityContext:
        fsGroup: 999  # PostgreSQL group
      containers:
      - name: postgres
        image: postgres:13
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: healthcare-db-credentials
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: healthcare-db-credentials
              key: password
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: healthcare-db-credentials
              key: database
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: db-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: db-data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: healthcare-db
  namespace: healthcare
spec:
  selector:
    app: healthcare-db
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF
```

Apply the database deployment and service:

```bash
kubectl apply -f healthcare-db.yaml
```

#### Step 6: Deploy a Healthcare Application with Secrets

Now, let's deploy our healthcare application that uses the secrets we created:

```bash
cat > healthcare-app.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: healthcare-app
  namespace: healthcare
spec:
  replicas: 2
  selector:
    matchLabels:
      app: healthcare-app
  template:
    metadata:
      labels:
        app: healthcare-app
    spec:
      initContainers:
        - name: init-nginx
          image: busybox
          command: ["/bin/sh", "-c"]
          args:
            - |
              mkdir -p /nginx-cache/client_temp /nginx-cache/proxy_temp /nginx-cache/fastcgi_temp /nginx-cache/uwsgi_temp /nginx-cache/scgi_temp
              chmod -R 777 /nginx-cache
              # Add this line to set ownership to nginx user (101)
              chown -R 101:101 /nginx-cache
          securityContext:
            runAsUser: 0  # Run as root to have permission to chown
          resources:
            requests:
              memory: "32Mi"
              cpu: "50m"
            limits:
              memory: "64Mi"
              cpu: "100m"
          volumeMounts:
            - name: nginx-cache
              mountPath: /nginx-cache
      containers:
        - name: healthcare-app
          image: nginx:alpine
          command: ["/bin/sh", "-c"]
          args:
            - |
              # Create a simple web server that simulates a healthcare application
              mkdir -p /usr/share/nginx/html
              
              # Create index.html
              cat > /usr/share/nginx/html/index.html << 'EOL'
              <!DOCTYPE html>
              <html>
              <head>
                <title>Healthcare Application Dashboard</title>
                <style>
                  body {
                    font-family: Arial, sans-serif;
                    margin: 0;
                    padding: 20px;
                    background-color: #f5f7fa;
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
                    background-color: #3498db;
                    color: white;
                    padding: 20px;
                    border-radius: 8px 8px 0 0;
                    margin: -20px -20px 20px;
                  }
                  h1 {
                    margin: 0;
                  }
                  .secure-badge {
                    background-color: #2ecc71;
                    color: white;
                    padding: 5px 10px;
                    border-radius: 4px;
                    display: inline-block;
                    margin-bottom: 20px;
                  }
                  .section {
                    border: 1px solid #e0e0e0;
                    border-radius: 4px;
                    padding: 15px;
                    margin-bottom: 20px;
                  }
                  .section h2 {
                    margin-top: 0;
                    color: #2c3e50;
                  }
                  .section table {
                    width: 100%;
                    border-collapse: collapse;
                  }
                  .section th, .section td {
                    padding: 8px;
                    text-align: left;
                    border-bottom: 1px solid #e0e0e0;
                  }
                  .section th {
                    background-color: #f8f9fa;
                  }
                  .env-var {
                    font-family: monospace;
                    background-color: #f8f9fa;
                    padding: 10px;
                    border-radius: 4px;
                    margin-top: 5px;
                    white-space: pre-wrap;
                    word-break: break-all;
                  }
                  .masked {
                    color: #e74c3c;
                    font-style: italic;
                  }
                </style>
              </head>
              <body>
                <div class="dashboard">
                  <header>
                    <h1>Healthcare Application Dashboard</h1>
                  </header>
              
                  <div class="secure-badge">Secure Connection</div>
              
                  <div class="section">
                    <h2>Patient Records</h2>
                    <table>
                      <tr>
                        <th>Patient ID</th>
                        <th>Name</th>
                        <th>Last Visit</th>
                      </tr>
                      <tr>
                        <td>P12345</td>
                        <td>John Smith</td>
                        <td>2025-04-15</td>
                      </tr>
                      <tr>
                        <td>P23456</td>
                        <td>Jane Doe</td>
                        <td>2025-04-02</td>
                      </tr>
                      <tr>
                        <td>P34567</td>
                        <td>Robert Johnson</td>
                        <td>2025-04-10</td>
                      </tr>
                    </table>
                  </div>
              
                  <div class="section">
                    <h2>System Information</h2>
                    <p>Pod Name: <span id="pod-name">Loading...</span></p>
                    <p>Namespace: <span id="namespace">Loading...</span></p>
                    <p>Database Connection: <span class="masked">**** (Secured) ****</span></p>
                    <p>API Key Status: <span class="masked">**** (Secured) ****</span></p>
                  </div>
              
                  <div class="section">
                    <h2>Security Settings</h2>
                    <p>TLS Enabled: Yes</p>
                    <p>Data Encryption: Enabled</p>
                    <p>Access Control: Role-Based</p>
                    <p>Network Policy: Restricted</p>
                  </div>
                </div>
              
                <script>
                  // Fill in some dynamic information
                  const hostName = window.location.hostname;
                  document.getElementById('pod-name').textContent = hostName;
                  document.getElementById('namespace').textContent = 'healthcare';
                </script>
              </body>
              </html>
              EOL
              
              # Create a health check endpoint
              mkdir -p /usr/share/nginx/html/health
              echo "OK" > /usr/share/nginx/html/health/index.html
              
              # Start nginx in the foreground
              nginx -g "daemon off;"
          ports:
            - containerPort: 80
          env:
            - name: DB_CONNECTION_STRING
              valueFrom:
                secretKeyRef:
                  name: healthcare-db-credentials
                  key: connection-string
            - name: EXTERNAL_API_KEY
              valueFrom:
                secretKeyRef:
                  name: healthcare-api-keys
                  key: external-api-key
            - name: ENCRYPTION_KEY
              valueFrom:
                secretKeyRef:
                  name: healthcare-api-keys
                  key: encryption-key
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"
          readinessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 20
          volumeMounts:
            - name: nginx-cache
              mountPath: /var/cache/nginx
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
              add:
                - NET_BIND_SERVICE  # Required for binding to ports 80/443
                - SETGID  # Required for changing group ID
                - SETUID  # Required for changing user ID
            readOnlyRootFilesystem: false  # Nginx needs write access to temp directories
        - name: tls-proxy
          image: nginx:alpine
          command: ["/bin/sh", "-c"]
          args:
            - |
              # Create a self-signed certificate for TLS
              apk add --no-cache openssl
              mkdir -p /etc/nginx/ssl
              
              openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/nginx/ssl/tls.key -out /etc/nginx/ssl/tls.crt \
                -subj "/CN=healthcare-app.example.com" \
                -addext "subjectAltName = DNS:healthcare-app.example.com"
              
              # Create NGINX configuration for TLS termination
              cat > /etc/nginx/conf.d/default.conf << 'EOL'
              server {
                  listen 443 ssl;
                  server_name healthcare-app.example.com;
              
                  ssl_certificate /etc/nginx/ssl/tls.crt;
                  ssl_certificate_key /etc/nginx/ssl/tls.key;
              
                  ssl_protocols TLSv1.2 TLSv1.3;
                  ssl_ciphers HIGH:!aNULL:!MD5;
                  ssl_prefer_server_ciphers on;
              
                  location / {
                      proxy_pass http://localhost:80;
                      proxy_set_header Host $host;
                      proxy_set_header X-Real-IP $remote_addr;
                  }
              }
              EOL
              
              # Start nginx
              nginx -g "daemon off;"
          ports:
            - containerPort: 443
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "100m"
          volumeMounts:
            - name: nginx-cache
              mountPath: /var/cache/nginx
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
              add:
                - NET_BIND_SERVICE  # Required for binding to ports 80/443
                - SETGID  # Required for changing group ID
                - SETUID  # Required for changing user ID
      volumes:
        - name: nginx-cache
          emptyDir: {}
EOF
```

This deployment:
- Creates a healthcare application with a user interface
- Uses environment variables from our secrets
- Includes a TLS sidecar container for HTTP encryption
- Sets security contexts to run as a non-root user
- Implements health checks

Let's create a service to expose our healthcare application:

```bash
cat > healthcare-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: healthcare-app
  namespace: healthcare
spec:
  selector:
    app: healthcare-app
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: https
    port: 443
    targetPort: 443
  type: ClusterIP
EOF
```

Apply the healthcare application and service:

```bash
kubectl apply -f healthcare-app.yaml
kubectl apply -f healthcare-service.yaml
```

#### Step 7: Implement Network Policies

Now, let's create network policies to restrict pod communication:

```bash
cat > network-policies.yaml << 'EOF'
# Allow the healthcare app to access only the healthcare database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: healthcare-app-to-db
  namespace: healthcare
spec:
  podSelector:
    matchLabels:
      app: healthcare-app
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: healthcare-db
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
---
# Restrict database to only accept connections from the healthcare app
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-from-healthcare-app
  namespace: healthcare
spec:
  podSelector:
    matchLabels:
      app: healthcare-db
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: healthcare-app
    ports:
    - protocol: TCP
      port: 5432
---
# Allow healthcare app to be accessible only on HTTPS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: healthcare-app-https-only
  namespace: healthcare
spec:
  podSelector:
    matchLabels:
      app: healthcare-app
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - protocol: TCP
      port: 443
EOF
```

Apply these network policies:

```bash
kubectl apply -f network-policies.yaml
```

#### Step 8: Set up RBAC for Limited Access

Let's create RBAC roles and role bindings to limit who can access our resources:

```bash
cat > healthcare-rbac.yaml << 'EOF'
# Role for read-only access to healthcare resources
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: healthcare-viewer
  namespace: healthcare
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]
---
# Role for managing healthcare pods (but not secrets)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: healthcare-operator
  namespace: healthcare
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update", "patch"]
---
# Role for full access to healthcare namespace (including secrets)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: healthcare-admin
  namespace: healthcare
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
# Role binding for a hypothetical viewer user
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: healthcare-viewer-binding
  namespace: healthcare
subjects:
- kind: User
  name: viewer@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: healthcare-viewer
  apiGroup: rbac.authorization.k8s.io
---
# Role binding for a hypothetical operator user
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: healthcare-operator-binding
  namespace: healthcare
subjects:
- kind: User
  name: operator@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: healthcare-operator
  apiGroup: rbac.authorization.k8s.io
---
# Role binding for a hypothetical admin user
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: healthcare-admin-binding
  namespace: healthcare
subjects:
- kind: User
  name: admin@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: healthcare-admin
  apiGroup: rbac.authorization.k8s.io
EOF
```

Apply these RBAC roles and bindings:

```bash
kubectl apply -f healthcare-rbac.yaml
```

#### Step 9: Setting Up a NodePort Service for External Access

Let's create a NodePort service to access our healthcare application from outside the cluster:

```bash
cat > healthcare-external.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: healthcare-app-external
  namespace: healthcare
spec:
  selector:
    app: healthcare-app
  ports:
  - name: https
    port: 443
    targetPort: 443
    nodePort: 30443
  type: NodePort
EOF
```

Apply this service:

```bash
kubectl apply -f healthcare-external.yaml
```

#### Step 10: Testing the Secure Application

Let's test our secure healthcare application:

`Port forwarding to access the application`

```bash
kubectl port-forward -n healthcare service/healthcare-app-external 8443:443
```

Now you can access the application securely via HTTPS at:

```
https://localhost:8443
```

Note: Since we're using a self-signed certificate, your browser will show a security warning.

`Testing Network Policies`

Let's verify that our network policies are working by trying to create a pod that violates them:

```bash
cat > test-pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: network-test
  namespace: healthcare
  labels:
    app: network-test
spec:
  containers:
    - name: busybox
      image: busybox
      command: ["/bin/sh", "-c", "sleep 3600"]
      resources:
        requests:
          memory: "64Mi"
          cpu: "50m"
        limits:
          memory: "128Mi"
          cpu: "100m"    
EOF
```

Apply this test pod:

```bash
kubectl apply -f test-pod.yaml
```

Once the pod is running, let's try to access the database from it:

```bash
kubectl exec -it -n healthcare network-test -- sh
# Inside the pod, try to connect to the database
nc -zv healthcare-db 5432
# This should fail because our network policy only allows connections from pods with the 'app: healthcare-app' label

# Try to connect to the healthcare app on HTTP (port 80)
nc -zv healthcare-app 80
# This should also fail because our network policy only allows connections to the healthcare app on HTTPS (port 443)

# Try to connect to the healthcare app on HTTPS (port 443)
nc -zv healthcare-app 443
# This should work because our network policy allows connections to the healthcare app on HTTPS

exit
```

#### Cleanup

When you're done, you can clean up all resources:

```bash
# Delete the namespace (this will delete everything in it)
kubectl delete namespace healthcare

# Or delete the entire cluster
bash k8s-cluster-manager.sh delete secure-app-cluster
```

#### Understanding What Happened Under the Hood

We've created a secure healthcare application with multiple layers of protection:

1. `Namespace Isolation:` A dedicated namespace with resource quotas
2. `Secret Management:` Secure storage of sensitive information
3. `Network Policies:` Restricting pod-to-pod communication
4. `RBAC:` Limited access to resources based on roles
5. `TLS Encryption:` Protecting data in transit with a sidecar container

These security measures work together to protect our application from various threats and comply with healthcare regulations.

They follow security best practices like:

- `Principle of Least Privilege:` Every component has only the permissions it needs
- `Defence in Depth:` Multiple layers of security working together
- `Secure by Default:` Starting with restrictive settings and only opening what's needed
- `Zero Trust:` Verifying and validating all access attempts

Through this scenario, you've learned about:
- `Resource Quotas:` Limiting resource consumption in namespaces
- `Secrets Management:` Securely storing and using sensitive information
- `Network Policies:` Creating firewall rules for pod communication
- `RBAC:` Controlling access to Kubernetes resources
- `Sidecar Pattern:` Using additional containers for specialized functions
- `TLS Termination:` Encrypting communications with HTTPS
