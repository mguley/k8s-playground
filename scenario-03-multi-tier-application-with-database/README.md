#### Table of Contents

- [Introduction](#introduction)
- [What is a Multi-tier Architecture?](#what-is-a-multi-tier-architecture)
- [Step 1: Understanding the New Kubernetes Concepts](#step-1-understanding-the-new-kubernetes-concepts)
- [Step 2: Create a Namespace for Our Application](#step-2-create-a-namespace-for-our-application)
- [Step 3: Deploy the Database Tier using StatefulSet](#step-3-deploy-the-database-tier-using-statefulset)
- [Step 4: Deploy the Backend API Service](#step-4-deploy-the-backend-api-service)
- [Step 5: Deploy the Frontend Application](#step-5-deploy-the-frontend-application)
- [Step 6: Expose via Ingress](#step-6-expose-via-ingress)
- [Step 7: Testing the Ingress](#step-7-testing-the-ingress)
- [Step 8: Testing the Multi-tier Application](#step-8-testing-the-multi-tier-application)
- [Step 9: Testing Communication Between Services](#step-9-testing-communication-between-services)
- [Step 10: Scaling the Application](#step-10-scaling-the-application)
- [Cleanup](#cleanup)
- [Understanding What Happened Under the Hood](#understanding-what-happened-under-the-hood)

---

#### Introduction

We'll build a multi-tier application that represents a simplified e-commerce platform.
This is a common architecture used in real-world applications where different components need to be isolated but still
communicate with each other.

#### What is a Multi-tier Architecture?

In a multi-tier (or n-tier) architecture, an application is divided into logical layers, each responsible for specific
functionality:

1. `Database tier`: Stores and manages data
2. `Backend/API tier`: Processes business logic and handles data operations
3. `Frontend tier`: Presents the user interface and interacts with users

This separation allows teams to develop, scale, and maintain each component independently.

##### Setting Up the Cluster

Let's create a new Kubernetes cluster for our e-commerce application:

```bash
bash k8s-cluster-manager.sh create ecommerce-cluster 3
```

This creates a cluster with one control plane node and two worker nodes.

##### Step 1: Understanding the New Kubernetes Concepts

`Namespaces`
- Logical partitions within a Kubernetes cluster
- Provide a scope for names (each object name must be unique within a namespace)
- Allow for resource isolation and organization
- Enable teams to work in their own spaces without interfering with each other

`StatefulSets`
- Similar to Deployments but designed for stateful applications
- Provide stable, unique network identifiers
- Offer stable, persistent storage
- Ordered, graceful deployment and scaling
- Perfect for databases and other stateful applications

`ConfigMaps and Secrets`
- ConfigMaps store configuration data as key-value pairs
- Secrets are similar but designed for sensitive data
- Both can be mounted as files or exposed as environment variables

`Service Discovery`
- The process of finding which services are available and how to connect to them
- In Kubernetes, services automatically get DNS entries
- Applications can discover and connect to services using these DNS names

##### Step 2: Create a Namespace for Our Application

Let's start by creating a dedicated namespace for our e-commerce application:

```bash
cat > ecommerce-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: ecommerce
  labels:
    name: ecommerce
EOF
```

Apply this manifest to create the namespace:

```bash
kubectl apply -f ecommerce-namespace.yaml
```

Verify the namespace was created:

```bash
kubectl get namespaces
```

You should see the `"ecommerce"` namespace in the list.

Now, let's set this namespace as our default context to avoid having to specify it in every command:

```bash
kubectl config set-context --current --namespace=ecommerce
```

##### Step 3: Deploy the Database Tier using StatefulSet

For our database tier, we'll use PostgreSQL. Since databases are stateful applications (they need to persistently store data),
we'll use a StatefulSet rather than a Deployment.

First, let's create a ConfigMap for our PostgreSQL configuration:

```bash
cat > postgres-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-config
  namespace: ecommerce
data:
  POSTGRES_DB: "ecommercedb"
  POSTGRES_USER: "ecommerceuser"
  POSTGRES_PASSWORD: "ecommercepass"  # In a real scenario, use Secrets for passwords
  POSTGRES_HOST: "postgres-0.postgres-headless"
EOF
```

This ConfigMap defines the database name, username, password, and hostname that will be used both by PostgreSQL and
our application.

Next, let's create our PostgreSQL StatefulSet:

```bash
cat > postgres-statefulset.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: ecommerce
spec:
  serviceName: "postgres-headless"
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:13
        ports:
        - containerPort: 5432
          name: postgres
        envFrom:
        - configMapRef:
            name: postgres-config
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
EOF
```

This StatefulSet:
- Creates a single PostgreSQL instance (replica: 1)
- Uses the configuration from our ConfigMap
- Sets resource limits to ensure stability
- Defines a persistent volume claim to store data

Now, let's create a headless service for the database. A headless service is used for StatefulSets to provide stable DNS
names for each pod:

```bash
cat > postgres-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
  namespace: ecommerce
  labels:
    app: postgres
spec:
  clusterIP: None  # This makes it a headless service
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
    name: postgres
EOF
```

Apply these files to create the database tier:

```bash
kubectl apply -f postgres-config.yaml
kubectl apply -f postgres-statefulset.yaml
kubectl apply -f postgres-service.yaml
```

Check if the PostgreSQL pod is running:

```bash
kubectl get pods -l app=postgres
```

It might take a minute for the pod to be ready. You can watch its progress with:

```bash
kubectl get pods -l app=postgres -w
```
(Press Ctrl+C to exit the watch mode when the pod is running)

Once the pod is running, let's initialize our database with some sample data. We'll create a simple products table:

```bash
# Connect to the PostgreSQL pod
kubectl exec -it postgres-0 -- bash

# Inside the pod, connect to PostgreSQL
psql -U ecommerceuser -d ecommercedb

# Create a products table and insert some data
CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  description TEXT,
  price NUMERIC(10, 2) NOT NULL,
  stock INTEGER NOT NULL
);

INSERT INTO products (name, description, price, stock) VALUES
  ('Smartphone', 'Latest model smartphone with high-res camera', 699.99, 50),
  ('Laptop', 'Powerful laptop for work and gaming', 1299.99, 25),
  ('Headphones', 'Noise-cancelling wireless headphones', 199.99, 100),
  ('Smartwatch', 'Fitness tracking smartwatch with heart rate monitor', 249.99, 75),
  ('Tablet', '10-inch tablet with retina display', 499.99, 30);

# Verify the data was inserted
SELECT * FROM products;

# Exit PostgreSQL
\q

# Exit the pod
exit
```

##### Step 4: Deploy the Backend API Service

Now that our database is running, let's create a simple backend API service that will connect to the database and serve
product data.

First, let's create a deployment for our backend API:

```bash
cat > backend-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
  namespace: ecommerce
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-backend
  template:
    metadata:
      labels:
        app: api-backend
    spec:
      containers:
      - name: api-backend
        image: node:16-alpine
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo 'Creating API server...'
            mkdir -p /app
            cd /app
            
            # Create package.json
            cat > package.json << 'EOL'
            {
              "name": "ecommerce-api",
              "version": "1.0.0",
              "description": "Simple API for e-commerce",
              "main": "server.js",
              "dependencies": {
                "express": "^4.17.1",
                "pg": "^8.7.1",
                "cors": "^2.8.5"
              }
            }
            EOL
            
            # Create server.js
            cat > server.js << 'EOL'
            const express = require('express');
            const { Pool } = require('pg');
            const cors = require('cors');
            
            const app = express();
            const port = 3000;
            
            app.use(cors());
            app.use(express.json());
            
            // Create PostgreSQL connection pool
            const pool = new Pool({
              user: process.env.POSTGRES_USER,
              host: process.env.POSTGRES_HOST,
              database: process.env.POSTGRES_DB,
              password: process.env.POSTGRES_PASSWORD,
              port: 5432,
            });
            
            // Health check endpoint
            app.get('/health', (req, res) => {
              res.json({ status: 'healthy' });
            });
            
            // Get all products
            app.get('/api/products', async (req, res) => {
              try {
                const result = await pool.query('SELECT * FROM products');
                res.json(result.rows);
              } catch (err) {
                console.error('Database error:', err);
                res.status(500).json({ error: 'Database error' });
              }
            });
            
            // Get a single product by ID
            app.get('/api/products/:id', async (req, res) => {
              try {
                const { id } = req.params;
                const result = await pool.query('SELECT * FROM products WHERE id = $1', [id]);
                
                if (result.rows.length === 0) {
                  return res.status(404).json({ error: 'Product not found' });
                }
                
                res.json(result.rows[0]);
              } catch (err) {
                console.error('Database error:', err);
                res.status(500).json({ error: 'Database error' });
              }
            });
            
            app.listen(port, () => {
              console.log(`API server running on port ${port}`);
            });
            EOL
            
            # Install dependencies and start server
            npm install
            node server.js
        ports:
        - containerPort: 3000
        envFrom:
        - configMapRef:
            name: postgres-config
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 15
          periodSeconds: 5
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
EOF
```

This backend deployment:
- Uses a Node.js Alpine image
- Creates a simple Express.js API server
- Connects to PostgreSQL using the connection details from our ConfigMap
- Implements basic API endpoints for product data
- Includes a readiness probe to check if the service is healthy

Now, let's create a service to expose the backend API:

```bash
cat > backend-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: api-backend
  namespace: ecommerce
spec:
  selector:
    app: api-backend
  ports:
  - port: 80
    targetPort: 3000
  type: ClusterIP
EOF
```

Apply these files to create the backend tier:

```bash
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
```

Check if the backend pods are running:

```bash
kubectl get pods -l app=api-backend
```

It might take a minute for the pods to be ready, especially since they need to download dependencies.
You can watch their progress with:

```bash
kubectl get pods -l app=api-backend -w
```

##### Step 5: Deploy the Frontend Application

Finally, let's create a simple frontend application that will interact with our API:

```bash
cat > frontend-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ecommerce
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:alpine
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo 'Creating frontend app...'
            mkdir -p /usr/share/nginx/html
            
            # Create index.html
            cat > /usr/share/nginx/html/index.html << 'EOL'
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>E-Commerce Store</title>
              <style>
                body {
                  font-family: Arial, sans-serif;
                  line-height: 1.6;
                  max-width: 800px;
                  margin: 0 auto;
                  padding: 20px;
                }
                header {
                  background-color: #4CAF50;
                  color: white;
                  text-align: center;
                  padding: 1em;
                  margin-bottom: 20px;
                  border-radius: 5px;
                }
                .product {
                  border: 1px solid #ddd;
                  padding: 15px;
                  margin-bottom: 15px;
                  border-radius: 5px;
                }
                .product h3 {
                  margin-top: 0;
                  color: #333;
                }
                .price {
                  font-weight: bold;
                  color: #4CAF50;
                  font-size: 1.2em;
                }
                .stock {
                  color: #666;
                  font-size: 0.9em;
                }
                .loading {
                  text-align: center;
                  color: #666;
                  font-style: italic;
                }
                .error {
                  color: red;
                  border: 1px solid red;
                  padding: 10px;
                  border-radius: 5px;
                  margin-bottom: 15px;
                }
              </style>
            </head>
            <body>
              <header>
                <h1>E-Commerce Product Catalog</h1>
                <p>Kubernetes Multi-tier Application Demo</p>
              </header>
              
              <div id="products-container">
                <p class="loading">Loading products...</p>
              </div>
            
              <script>
                // The API_URL will be updated by the startup script
                const API_URL = '';
                
                async function fetchProducts() {
                  try {
                    const response = await fetch(`${API_URL}/api/products`);
                    
                    if (!response.ok) {
                      throw new Error(`HTTP error! Status: ${response.status}`);
                    }
                    
                    const products = await response.json();
                    displayProducts(products);
                  } catch (error) {
                    console.error('Error fetching products:', error);
                    document.getElementById('products-container').innerHTML = `
                      <div class="error">
                        <p>Error loading products. Please try again later.</p>
                        <p>Error details: ${error.message}</p>
                      </div>
                    `;
                  }
                }
                
                function displayProducts(products) {
                  const container = document.getElementById('products-container');
                  
                  if (products.length === 0) {
                    container.innerHTML = '<p>No products available.</p>';
                    return;
                  }
                  
                  const productsHTML = products.map(product => `
                    <div class="product">
                      <h3>${product.name}</h3>
                      <p>${product.description}</p>
                      <p class="price">$${parseFloat(product.price).toFixed(2)}</p>
                      <p class="stock">In stock: ${product.stock}</p>
                    </div>
                  `).join('');
                  
                  container.innerHTML = productsHTML;
                }
                
                // Fetch products when the page loads
                window.addEventListener('DOMContentLoaded', fetchProducts);
              </script>
            </body>
            </html>
            EOL
            
            # Replace API_BACKEND_SERVICE with the actual service URL
            sed -i "s|http://API_BACKEND_SERVICE|http://ecommerce.local|g" /usr/share/nginx/html/index.html
            
            # Start nginx
            nginx -g "daemon off;"
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF
```

This frontend deployment:
- Uses an Nginx Alpine image
- Creates a simple HTML/CSS/JavaScript frontend
- Connects to our backend API service using the Kubernetes DNS name
- Shows a product catalog with information from the database

Now, let's create a service to expose the frontend:

```bash
cat > frontend-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: ecommerce
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
  type: NodePort
EOF
```

Apply these files to create the frontend tier:

```bash
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml
```

Check if the frontend pods are running:

```bash
kubectl get pods -l app=frontend
```

##### Step 6: Expose via Ingress

To make our application accessible from outside the cluster, we'll set up an Ingress controller and create rules to route traffic to our services.

1. First, install the NGINX Ingress Controller (Kind-flavored manifest):

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.4/deploy/static/provider/kind/deploy.yaml
```

2. Label your Kind nodes so the controller can schedule itself:

```bash
# List your nodes, then label each one:
kubectl get nodes -o name | xargs -I{} kubectl label {} ingress-ready=true

```

3. Wait for the controller pods to become `Running`:
```bash
kubectl -n ingress-nginx get pods --watch
```

You should see:

```
ingress-nginx-admission-create-xxxxx   Completed   0/1
ingress-nginx-admission-patch-xxxxx    Completed   0/1
ingress-nginx-controller-xxxxx         Running     1/1
```

4. Create your Ingress resource:
```bash
cat > ecommerce-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ecommerce-ingress
  namespace: ecommerce
spec:
  ingressClassName: nginx
  rules:
  - host: ecommerce.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-backend
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
EOF
```

Apply the Ingress configuration:

```bash
kubectl apply -f ecommerce-ingress.yaml
```

5. Map the host locally by adding to `/etc/hosts`:
```
127.0.0.1 ecommerce.local
```

##### Step 7: Testing the Ingress

Because we're running Kubernetes in Kind, we need to set up port forwarding to access our application:

```bash
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80
```

Now point your browser at:

```
http://ecommerce.local:8080
```

You should see a nicely formatted product catalog with items from our database. This confirms that:
1. The frontend is working
2. It's successfully communicating with the backend API
3. The backend API is successfully querying the database

The routing works as follows:
- `/` - served by your `frontend`
- `/api/products` - routed to your `api-backend`

##### Step 8: Testing the Multi-tier Application

Let's verify that each component of our application is running correctly:

```bash
kubectl get pods -n ecommerce
```

You should see all pods in the Running state.

##### Step 9: Testing Communication Between Services

To demonstrate how Kubernetes service discovery works, let's look at how our services communicate:

```bash
# Access a frontend pod
FRONTEND_POD=$(kubectl get pods -n ecommerce -l app=frontend -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it -n ecommerce $FRONTEND_POD -- sh

# Inside the pod, use curl to connect to the backend API
curl http://api-backend/health
# Should return: {"status":"healthy"}

# Try getting the products
curl http://api-backend/api/products
# Should return JSON data with our products

# Exit the pod
exit
```

These tests confirm that our services can discover and communicate with each other using Kubernetes service names.

##### Step 10: Scaling the Application

One of the benefits of this architecture is that we can scale each tier independently. Let's try scaling the frontend:

```bash
kubectl scale deployment frontend -n ecommerce --replicas=4
```

Check the pods to see the additional replicas:

```bash
kubectl get pods -n ecommerce -l app=frontend
```

You should now see 4 frontend pods. The frontend service automatically load-balances traffic across all these pods.

We can also scale the backend:

```bash
kubectl scale deployment api-backend -n ecommerce --replicas=3
```

Check the backend pods:

```bash
kubectl get pods -n ecommerce -l app=api-backend
```

You should now see 3 backend pods. Again, the backend service automatically load-balances traffic.

Note that we're not scaling the database because scaling stateful applications like databases requires additional configuration for data replication.

#### Cleanup

When you're done, you can clean up all resources:

```bash
# Delete the namespace (this will delete everything in it)
kubectl delete namespace ecommerce

# Or delete the entire cluster
bash k8s-cluster-manager.sh delete ecommerce-cluster
```

#### Understanding What Happened Under the Hood

We've successfully created a multi-tier application in Kubernetes with:

1. `Database Tier`: A PostgreSQL database running in a StatefulSet with persistent storage
2. `Backend API Tier`: An Express.js API server that connects to the database
3. `Frontend Tier`: An Nginx web server serving a static website that communicates with the API

Each tier is isolated in its own set of pods, but they can communicate through services. This architecture allows us to:
- Scale each tier independently
- Update each tier independently
- Replace components without affecting the entire application
- Isolate failures to specific tiers

The key Kubernetes concepts we've demonstrated include:

1. `Namespaces`: For logical partitioning of cluster resources
2. `StatefulSets`: For managing stateful applications like databases
3. `Deployments`: For managing stateless applications
4. `Services`: For service discovery and load balancing
5. `ConfigMaps`: For managing configuration data
6. `Ingress`: For external access and traffic routing
7. `Resource Scaling`: For dynamically adjusting the number of replicas

This multi-tier architecture pattern is commonly used in real-world production environments because it provides flexibility,
scalability, and resilience. Each component can be developed, deployed, and scaled independently, making it easier to
manage complex applications.