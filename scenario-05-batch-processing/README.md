#### Table of Contents

- [Introduction](#introduction)
- [What are Jobs and CronJobs in Kubernetes?](#what-are-jobs-and-cronjobs-in-kubernetes)
- [Step 1: Understanding Key Batch Processing Concepts](#step-1-understanding-key-batch-processing-concepts)
- [Step 2: Setting Up the Cluster](#step-2-setting-up-the-cluster)
- [Step 3: Create a Simple CronJob for Regular Data Collection](#step-3-create-a-simple-cronjob-for-regular-data-collection)
- [Step 4: Create a Job Template for Ad-hoc Data Processing](#step-4-create-a-job-template-for-ad-hoc-data-processing)
- [Step 5: Implement Job Parallelism for Faster Processing](#step-5-implement-job-parallelism-for-faster-processing)
- [Step 6: Set Up a Message Queue for Job Coordination](#step-6-set-up-a-message-queue-for-job-coordination)
- [Step 7: Set Resource Requests and Limits for Batch Workloads](#step-7-set-resource-requests-and-limits-for-batch-workloads)
- [Step 8: Testing Job Completion and Failure Scenarios](#step-8-testing-job-completion-and-failure-scenarios)
- [Cleanup](#cleanup)
- [Understanding What Happened Under the Hood](#understanding-what-happened-under-the-hood)

---

#### Introduction

In this scenario, we'll implement scheduled jobs and batch processing workflows in Kubernetes.
This represents a situation where a data analytics company needs to perform regular data processing tasks
on schedule and handle ad-hoc batch workloads efficiently.

#### What are Jobs and CronJobs in Kubernetes?

Kubernetes provides two resources specifically designed for batch processing:

1. `Jobs:` One-time tasks that run to completion
    - Run a container until it completes successfully
    - Automatically retry on failure (configurable)
    - Track successful completions
    - Ideal for data processing, backups, and migrations
2. `CronJobs:` Jobs that run on a schedule
    - Use cron syntax (same as Linux cron) to define schedules
    - Automatically create Jobs at scheduled times
    - Manage history and concurrent executions
    - Perfect for periodic tasks like data collection, reporting, and maintenance

#### Why Use Kubernetes for Batch Processing?

Kubernetes offers several advantages for batch workloads:
- `Resource efficiency:` Only consume resources when jobs are running
- `Automated scheduling:` Run jobs on a defined schedule without external tools
- `Failure handling:` Automatic retries and notifications
- `Scalability:` Scale out batch processing with parallelism
- `Resource management:` Set appropriate limits for batch vs. interactive workloads
- `Integration:` Jobs can interact with other Kubernetes resources

#### Step 1: Understanding Key Batch Processing Concepts

Before we dive into implementation, let's understand some key concepts related to batch processing in Kubernetes:

`Job Lifecycles`

A Job creates Pods that run until successful completion. Key features include:

- `Completions:` Number of Pods that should successfully execute and terminate
- `Parallelism:` Maximum number of Pods that can run in parallel
- `BackoffLimit:` Number of retries before considering a Job failed
- `Active Deadline Seconds:` Maximum time a Job can be active before being terminated
- `TTL After Finished:` Automatic cleanup after Job completion

`CronJob Scheduling`

CronJobs use the standard cron syntax to define schedules:

```
┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of the month (1 - 31)
│ │ │ ┌───────────── month (1 - 12)
│ │ │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday)
│ │ │ │ │                                   
* * * * * command to execute
```

For example:
- `0 * * * *` - Run once every hour at the start of the hour
- `0 0 * * *` - Run once a day at midnight
- `0 0 * * 0` - Run once a week on Sunday

`Queue-Based Job Processing`

For more complex workloads, you can implement a queue-based pattern:

1. A message queue holds tasks to be processed
2. A producer adds tasks to the queue
3. Consumer deployments process tasks from the queue
4. This pattern enables dynamic scaling and workload distribution

#### Step 2: Setting Up the Cluster

Let's create a new Kubernetes cluster for our batch processing demonstration:

```bash
bash k8s-cluster-manager.sh create batch-jobs-cluster 3
```

This creates a cluster with one control plane node and two worker nodes.

#### Step 3: Create a Simple CronJob for Regular Data Collection

Let's start by creating a CronJob that runs every minute to simulate collecting metrics:

```bash
cat > metrics-collector-cronjob.yaml << 'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: metrics-collector
spec:
  schedule: "*/1 * * * *"  # Run every minute
  concurrencyPolicy: Forbid  # Don't start a new job if previous still running
  failedJobsHistoryLimit: 3  # Keep history of 3 failed jobs
  successfulJobsHistoryLimit: 3  # Keep history of 3 successful jobs
  startingDeadlineSeconds: 30  # Must start within 30 seconds of scheduled time
  jobTemplate:
    spec:
      backoffLimit: 2  # Retry 2 times before marking as failed
      template:
        spec:
          containers:
          - name: metrics-collector
            image: busybox
            command:
            - /bin/sh
            - -c
            - |
              echo "Starting metrics collection job at $(date)"
              echo "Simulating data collection process..."
              sleep 10  # Simulate work being done
              echo "Collection completed successfully at $(date)"
              echo "Data points collected: $((RANDOM % 100 + 50))"
            resources:
              requests:
                memory: "64Mi"
                cpu: "100m"
              limits:
                memory: "128Mi"
                cpu: "200m"
          restartPolicy: OnFailure
EOF
```

Let's apply this CronJob:

```bash
kubectl apply -f metrics-collector-cronjob.yaml
```

Now, let's check if our CronJob was created:

```bash
kubectl get cronjobs
```

You should see the `metrics-collector` CronJob in the list. After a minute, a Job should be created. Let's check:

```bash
kubectl get jobs
```

And we can see the pods created by the job:

```bash
kubectl get pods
```

Let's check the logs from one of the completed pods to see the output of our job:

```bash
# Get the name of a completed pod
POD_NAME=$(kubectl get pods --selector=job-name --sort-by=.status.startTime | tail -1 | awk '{print $1}')

# View the logs
kubectl logs $POD_NAME
```

You should see the output from our metrics collection job.

#### Step 4: Create a Job Template for Ad-hoc Data Processing

Now, let's create a template for ad-hoc data processing jobs:

```bash
cat > data-processing-job-template.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: data-processor-TIMESTAMP
  labels:
    app: data-processor
    type: ad-hoc
spec:
  backoffLimit: 3
  completions: 1
  template:
    spec:
      containers:
      - name: data-processor
        image: python:3.9-alpine
        command:
        - /bin/sh
        - -c
        - |
          echo "Starting data processing job at $(date)"
          echo "Input parameters: PARAMETERS"
          echo "Installing required packages..."
          pip install pandas numpy --quiet
          
          echo "Processing data..."
          python -c '
          import pandas as pd
          import numpy as np
          import time
          import random
          
          # Simulate data processing
          print("Generating sample data...")
          data_size = 100000
          data = pd.DataFrame({
              "id": range(data_size),
              "value": np.random.normal(100, 15, data_size),
              "category": np.random.choice(["A", "B", "C", "D"], data_size)
          })
          
          print(f"Generated dataset with {len(data)} records")
          print("Sample of data:")
          print(data.head())
          
          print("\nPerforming data analysis...")
          time.sleep(5)  # Simulate processing time
          
          # Calculate statistics
          stats = data.groupby("category").agg({
              "value": ["mean", "std", "min", "max", "count"]
          })
          
          print("\nAnalysis results:")
          print(stats)
          
          # Simulate successful completion most of the time
          if random.random() < 0.9:
              print("\nData processing completed successfully!")
          else:
              print("\nSimulating a processing error!")
              exit(1)
          '
          
          echo "Job completed at $(date)"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      restartPolicy: OnFailure
EOF
```

This job template:
- Uses Python with pandas and numpy for data analysis
- Simulates processing a large dataset
- Calculates statistics grouped by category
- Occasionally fails randomly (10% of the time) to demonstrate retry behavior

To run an ad-hoc job, we need to replace TIMESTAMP and PARAMETERS with actual values:

```bash
# Generate a timestamp
TIMESTAMP=$(date +%s)

# Create a job instance with parameters
sed "s/TIMESTAMP/$TIMESTAMP/g; s/PARAMETERS/size=large,type=analysis/g" data-processing-job-template.yaml > data-processing-job-$TIMESTAMP.yaml

# Apply the job
kubectl apply -f data-processing-job-$TIMESTAMP.yaml
```

Let's check the status of our job:

```bash
kubectl get jobs -l app=data-processor
```

And let's check the logs to see the output:

```bash
# Get the name of the pod
POD_NAME=$(kubectl get pods --selector=job-name=data-processor-$TIMESTAMP | grep -v Completed | tail -1 | awk '{print $1}')

# View the logs
kubectl logs $POD_NAME
```

You should see the output from our data processing job, including the generated sample data and analysis results.

#### Step 5: Implement Job Parallelism for Faster Processing

For larger datasets, we might want to process data in parallel. Let's create a job that demonstrates parallelism:

```bash
cat > parallel-processing-job.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: parallel-processor
  labels:
    app: parallel-processor
spec:
  completions: 5  # Need 5 successful completions
  parallelism: 3  # Run up to 3 pods in parallel
  backoffLimit: 2
  template:
    spec:
      containers:
      - name: processor
        image: python:3.9-alpine
        command:
        - /bin/sh
        - -c
        - |
          # Get pod info for the record
          POD_NAME=$HOSTNAME
          echo "Starting processing on pod $POD_NAME"
          
          # Generate a random processing time to simulate different workloads
          PROCESS_TIME=$((RANDOM % 20 + 5))
          echo "This task will take approximately $PROCESS_TIME seconds"
          
          # Simulate processing
          for i in $(seq 1 $PROCESS_TIME); do
            echo "Processing: $i/$PROCESS_TIME"
            sleep 1
          done
          
          # Return success most of the time
          if [ $((RANDOM % 10)) -lt 9 ]; then
            echo "Processing completed successfully on $POD_NAME"
            exit 0
          else
            echo "Simulating a failure on $POD_NAME"
            exit 1
          fi
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      restartPolicy: OnFailure
EOF
```

This job:
- Requires 5 successful completions
- Runs up to 3 pods in parallel
- Simulates work with random processing times
- Occasionally fails to demonstrate retry behavior

Let's apply this job:

```bash
kubectl apply -f parallel-processing-job.yaml
```

Now, let's watch the job in action:

```bash
kubectl get pods -l job-name=parallel-processor -w
```

You should see up to 3 pods running simultaneously, with new pods starting as others complete, until 5 successful completions
are achieved.

Press Ctrl+C to exit the watch mode when the job is complete.

Let's check the status of our job:

```bash
kubectl get job parallel-processor
```

You should see the number of successful completions in the "COMPLETIONS" column.

#### Step 6: Set Up a Message Queue for Job Coordination

For more complex scenarios, we can set up a message queue to coordinate job processing.
This approach provides a robust way to decouple task producers from processors, enabling reliable and scalable workload distribution.

Let's first deploy RabbitMQ as our message broker:

```bash
cat > rabbitmq-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq
  labels:
    app: rabbitmq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3.9-alpine
        ports:
        - containerPort: 5672
          name: amqp
        - containerPort: 15672
          name: management
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        env:
        - name: RABBITMQ_DEFAULT_USER
          value: "user"
        - name: RABBITMQ_DEFAULT_PASS
          value: "password"
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  labels:
    app: rabbitmq
spec:
  ports:
  - port: 5672
    name: amqp
    targetPort: 5672
  - port: 15672
    name: management
    targetPort: 15672
  selector:
    app: rabbitmq
EOF
```

Let's apply this manifest to deploy RabbitMQ:

```bash
kubectl apply -f rabbitmq-deployment.yaml
```

Next, let's create and deploy worker pods that will be ready to consume tasks from the queue as soon as they're available:

```bash
cat > worker-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: task-worker
  labels:
    app: task-worker
spec:
  replicas: 3
  selector:
    matchLabels:
      app: task-worker
  template:
    metadata:
      labels:
        app: task-worker
    spec:
      containers:
        - name: worker
          image: python:3.9-alpine
          command:
            - /bin/sh
            - -c
            - |
              echo "Starting task worker..."
              pip install pika --quiet
              
              python -c '
              import pika
              import json
              import time
              import random
              import os
              import sys
              
              # Force output to be unbuffered for real-time logs
              sys.stdout.reconfigure(line_buffering=True) if hasattr(sys.stdout, "reconfigure") else None
              print = lambda *args, **kwargs: __builtins__.print(*args, **kwargs, flush=True)
              
              # Get worker ID from hostname
              worker_id = os.environ.get("HOSTNAME", "unknown")
              print(f"Worker {worker_id} starting up...")
              
              # Function to check if RabbitMQ is reachable
              def is_rabbitmq_ready():
                  try:
                      import socket
                      sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                      sock.settimeout(2)
                      sock.connect(("rabbitmq", 5672))
                      sock.close()
                      return True
                  except Exception as e:
                      print(f"RabbitMQ not yet reachable: {str(e)}")
                      return False
              
              # Wait for RabbitMQ to be ready with progressive backoff
              print("Checking if RabbitMQ is available...")
              max_attempts = 15
              attempt = 0
              
              while attempt < max_attempts:
                  if is_rabbitmq_ready():
                      print("RabbitMQ is now reachable!")
                      break
              
                  wait_time = min(5 + attempt, 20)  # Progressive backoff, max 20 seconds
                  print(f"Waiting {wait_time} seconds before retry {attempt+1}/{max_attempts}...")
                  time.sleep(wait_time)
                  attempt += 1
              
              if attempt == max_attempts:
                  print("Max attempts reached. Could not connect to RabbitMQ.")
                  sys.exit(1)
              
              print("Giving RabbitMQ a moment to initialize fully...")
              time.sleep(5)
              
              # Message processing function
              def process_message(ch, method, properties, body):
                  try:
                      print(f"Received message: {body[:100]}...")  # Truncate long messages in log
                      task = json.loads(body)
                      task_id = task.get("task_id")
                      task_type = task.get("type")
                      priority = task.get("priority")
                      data_size = task.get("data_size")
              
                      print(f"Worker {worker_id} processing task {task_id}: {task_type}, priority: {priority}")
              
                      # Simulate processing time based on data size and task type
                      if task_type == "analysis":
                          process_time = data_size / 1000
                      elif task_type == "aggregation":
                          process_time = data_size / 2000
                      else:  # transformation
                          process_time = data_size / 3000
              
                      # Add some randomness to processing time
                      process_time = max(1, process_time * random.uniform(0.8, 1.2))
              
                      print(f"Task {task_id} will take approximately {process_time:.2f} seconds")
              
                      # Simulate the processing work
                      time.sleep(process_time)
              
                      # Simulate occasional failures
                      if random.random() < 0.1:
                          print(f"Task {task_id} failed!")
                          raise Exception("Simulated processing error")
              
                      print(f"Task {task_id} completed successfully!")
              
                      # Acknowledge the message
                      ch.basic_ack(delivery_tag=method.delivery_tag)
                  except Exception as e:
                      print(f"Error processing task: {str(e)}")
                      # Negative acknowledgment - return to queue
                      ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
                      # Small delay before retrying
                      time.sleep(5)
              
              # Set up credentials
              print("Setting up RabbitMQ credentials...")
              credentials = pika.PlainCredentials("user", "password")
              
              # Connect to RabbitMQ with robust retry logic
              connected = False
              connect_attempts = 0
              max_connect_attempts = 10
              connection = None
              channel = None
              
              print("Attempting to connect to RabbitMQ...")
              while not connected and connect_attempts < max_connect_attempts:
                  try:
                      print(f"Connection attempt {connect_attempts+1}/{max_connect_attempts}...")
                      connection_params = pika.ConnectionParameters(
                          host="rabbitmq", 
                          credentials=credentials,
                          socket_timeout=10,
                          connection_attempts=3,
                          retry_delay=2
                      )
                      connection = pika.BlockingConnection(connection_params)
                      channel = connection.channel()
                      connected = True
                      print("Successfully connected to RabbitMQ!")
                  except Exception as e:
                      connect_attempts += 1
                      print(f"Failed to connect to RabbitMQ: {str(e)}")
              
                      if connect_attempts < max_connect_attempts:
                          wait_time = min(5 * (connect_attempts + 1), 30)  # Progressive backoff
                          print(f"Retrying in {wait_time} seconds...")
                          time.sleep(wait_time)
                      else:
                          print("Max connection attempts reached. Exiting...")
                          sys.exit(1)
              
              # Declare the queue
              queue_name = "data_processing_tasks"
              print(f"Declaring queue: {queue_name}")
              channel.queue_declare(queue=queue_name, durable=True)
              
              # Check queue status
              result = channel.queue_declare(queue=queue_name, durable=True, passive=True)
              message_count = result.method.message_count
              print(f"Queue {queue_name} has {message_count} messages waiting")
              
              # Set QoS prefetch
              print("Setting QoS prefetch to 1...")
              channel.basic_qos(prefetch_count=1)
              
              # Set up the consumer
              print(f"Worker {worker_id} waiting for tasks...")
              channel.basic_consume(queue=queue_name, on_message_callback=process_message)
              
              # Start consuming messages
              print("Starting message consumption loop...")
              try:
                  channel.start_consuming()
              except KeyboardInterrupt:
                  print("Received keyboard interrupt. Shutting down...")
              except Exception as e:
                  print(f"Error in message consumption: {str(e)}")
              finally:
                  if channel is not None and channel.is_open:
                      channel.stop_consuming()
                  if connection is not None and connection.is_open:
                      print("Closing connection...")
                      connection.close()
                      print("Connection closed.")
              
              print("Worker shutting down...")
              '
          resources:
            requests:
              memory: "192Mi"
              cpu: "200m"
            limits:
              memory: "384Mi"
              cpu: "400m"
      restartPolicy: Always
EOF
```

Apply the worker deployment to start workers that will listen for tasks:

```bash
kubectl apply -f worker-deployment.yaml
```

Verify that the worker pods are running:

```bash
kubectl get pods -l app=task-worker
```

You should see three worker pods running. Let's check one of them to verify they're properly connected and waiting for tasks:

```bash
# Get one of the worker pod names
WORKER_POD=$(kubectl get pods -l app=task-worker -o jsonpath='{.items[0].metadata.name}')

# View the logs
kubectl logs $WORKER_POD
```

You should see logs showing that the worker has connected to RabbitMQ and is waiting for tasks.

Now that we have our workers ready, let's create a job producer that will push tasks to the queue:

```bash
cat > job-producer.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: job-producer
spec:
  backoffLimit: 4
  template:
    spec:
      containers:
        - name: producer
          image: python:3.9-alpine
          command:
            - /bin/sh
            - -c
            - |
              echo "Starting job producer..."
              pip install pika --quiet
              
              python -c '
              import pika
              import json
              import time
              import random
              import socket
              
              def is_rabbitmq_ready():
                  """Check if RabbitMQ service is reachable"""
                  try:
                      # Try to resolve and connect to the RabbitMQ hostname
                      sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                      sock.settimeout(2)  # 2 second timeout
                      sock.connect(("rabbitmq", 5672))
                      sock.close()
                      return True
                  except Exception as e:
                      print(f"RabbitMQ not yet reachable: {str(e)}")
                      return False
              
              # Wait for RabbitMQ to be ready with progressive backoff
              print("Waiting for RabbitMQ to be available...")
              max_attempts = 15
              attempt = 0
              
              while attempt < max_attempts:
                  if is_rabbitmq_ready():
                      print("RabbitMQ is now reachable!")
                      break
              
                  wait_time = min(5 + attempt, 30)  # Progressive backoff, max 30 seconds
                  print(f"Waiting {wait_time} seconds before retry {attempt+1}/{max_attempts}...")
                  time.sleep(wait_time)
                  attempt += 1
              
              if attempt == max_attempts:
                  print("Max attempts reached. Could not connect to RabbitMQ.")
                  exit(1)
              
              # Wait a bit more for RabbitMQ to initialize fully
              print("Giving RabbitMQ a moment to initialize fully...")
              time.sleep(5)
              
              # Connect to RabbitMQ with retry logic
              connected = False
              connection = None
              channel = None
              connect_attempts = 0
              max_connect_attempts = 5
              
              while not connected and connect_attempts < max_connect_attempts:
                  try:
                      print(f"Attempting to connect to RabbitMQ (attempt {connect_attempts+1}/{max_connect_attempts})...")
                      credentials = pika.PlainCredentials("user", "password")
                      connection = pika.BlockingConnection(
                          pika.ConnectionParameters(
                              host="rabbitmq", 
                              credentials=credentials,
                              socket_timeout=10,
                              connection_attempts=3,
                              retry_delay=2
                          )
                      )
                      channel = connection.channel()
                      connected = True
                      print("Successfully connected to RabbitMQ!")
                  except Exception as e:
                      print(f"Failed to connect: {str(e)}")
                      if connect_attempts < max_connect_attempts - 1:
                          wait_time = 5 * (connect_attempts + 1)  # Progressive backoff
                          print(f"Waiting {wait_time} seconds before retry...")
                          time.sleep(wait_time)
                      connect_attempts += 1
              
              if not connected:
                  print("Could not connect to RabbitMQ after multiple attempts.")
                  exit(1)
              
              # Declare a queue
              queue_name = "data_processing_tasks"
              print(f"Declaring queue: {queue_name}")
              channel.queue_declare(queue=queue_name, durable=True)
              
              # Generate and send 20 tasks
              print("Generating tasks...")
              for i in range(20):
                  task_id = i + 1
                  task = {
                      "task_id": task_id,
                      "type": random.choice(["analysis", "aggregation", "transformation"]),
                      "priority": random.choice(["high", "medium", "low"]),
                      "data_size": random.randint(100, 10000),
                      "created_at": time.time()
                  }
              
                  message = json.dumps(task)
                  channel.basic_publish(
                      exchange="",
                      routing_key=queue_name,
                      body=message,
                      properties=pika.BasicProperties(
                          delivery_mode=2,  # make message persistent
                      )
                  )
                  print(f"Message sent to the queue: {i}")
                  time.sleep(0.5)  # Small delay between tasks
              
              # Close the connection
              connection.close()
              print("All tasks have been sent to the queue!")
              '
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"
      restartPolicy: OnFailure
EOF
```

Now let's run the job producer to send tasks to our waiting workers:

```bash
kubectl apply -f job-producer.yaml
```

Check the status of our producer job:

```bash
kubectl get job job-producer
```

You should see the job running and then completing once it has sent all messages to the queue.
Once the producer has completed, let's watch the workers processing the tasks:

```bash
# Get one of the worker pod names
WORKER_POD=$(kubectl get pods -l app=task-worker -o jsonpath='{.items[0].metadata.name}')

# View the logs
kubectl logs $WORKER_POD
```

You should see logs showing the worker processing tasks from the queue. Each worker will handle a portion of the tasks,
so it's interesting to check the logs from multiple workers to see how the workload is distributed:

```bash
# Check logs from all worker pods
for pod in $(kubectl get pods -l app=task-worker -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== Logs from $pod ==="
  kubectl logs $pod | grep "processing task"
done
```

This shows how our queue-based architecture efficiently distributes work across multiple worker pods, handling occasional
failures with automatic retries, and maintaining a reliable processing pipeline.

#### Step 7: Set Resource Requests and Limits for Batch Workloads

When working with batch jobs, proper resource allocation is crucial. Let's understand the best practices:

1. `Memory Requests and Limits`:
    - Set realistic memory requests based on expected usage
    - Set memory limits to prevent a single job from consuming too much memory
    - For memory-intensive jobs, ensure request and limit are close to avoid OOM kills
2. `CPU Requests and Limits`:
    - Set lower CPU requests to improve scheduling (batch jobs can often wait)
    - Set higher CPU limits to allow bursting when resources are available
    - This allows better cluster utilization for mixed workloads
3. `Priority Classes`:
    - Use priority classes to ensure interactive workloads are prioritized over batch jobs
    - Lower priority batch jobs can fill in unused cluster capacity

Let's create a priority class for batch jobs:

```bash
cat > batch-priority.yaml << 'EOF'
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: batch-priority
value: 100  # Lower than default (1000)
globalDefault: false
description: "Priority class for batch jobs that can tolerate delays"
EOF
```

Apply the priority class:

```bash
kubectl apply -f batch-priority.yaml
```

Now, let's create a job that uses this priority class and demonstrates best practices for resource allocation:

```bash
cat > optimized-batch-job.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: optimized-batch-job
spec:
  backoffLimit: 2
  template:
    spec:
      priorityClassName: batch-priority
      containers:
        - name: batch-processor
          image: python:3.9-alpine
          command:
            - /bin/sh
            - -c
            - |
              echo "Starting optimized batch job..."
              echo "Installing required system dependencies..."
              apk add --no-cache build-base
              
              echo "Installing Python packages with detailed output..."
              pip install numpy --verbose
              
              echo "NumPy installation completed. Starting Python script..."
              
              # Simulate a memory-intensive operation that varies in usage
              python -c '
              import sys
              import numpy as np
              import time
              import os
              
              # Force unbuffered output
              sys.stdout.reconfigure(line_buffering=True) if hasattr(sys.stdout, "reconfigure") else None
              # Alternative flush approach for older Python versions
              print = lambda *args, **kwargs: __builtins__.print(*args, **kwargs, flush=True)
              
              try:
                  print("Running memory-adaptive batch process")
              
                  # Simulate a job that scales its memory usage based on available resources
                  # In a real scenario, you might check cgroup limits or use resource estimation
              
                  # Start with a small array
                  print("Starting with minimal memory usage")
                  data = np.ones((1000, 1000), dtype=np.float32)
                  print(f"Initial memory usage: {data.nbytes / (1024 * 1024):.2f} MB")
              
                  # Gradually increase if we have enough memory
                  max_iterations = 20
                  for i in range(max_iterations):
                      print(f"Processing batch {i+1}/{max_iterations}")
              
                      # Simulate CPU-intensive work
                      t_start = time.time()
                      for _ in range(3):
                          # Matrix operations are CPU-intensive
                          result = np.matmul(data, data)
                      t_end = time.time()
              
                      print(f"Batch {i+1} completed in {t_end - t_start:.2f} seconds")
              
                      # For this demo, limit our growth to stay within container limits
                      if i < 5:
                          current_size = data.shape[0]
                          new_size = min(current_size + 1000, 8000)
                          print(f"Increasing working set size: {current_size} -> {new_size}")
                          data = np.ones((new_size, new_size), dtype=np.float32)
                          print(f"New memory usage: {data.nbytes / (1024 * 1024):.2f} MB")
              
                      # Sleep between batches to simulate I/O or other waiting
                      time.sleep(1)
              
                  print("Optimized batch job completed successfully!")
              except Exception as e:
                  print(f"ERROR: Script failed with exception: {str(e)}")
                  import traceback
                  traceback.print_exc()
                  sys.exit(1)
              '
              
              echo "Python script execution completed."
          resources:
            # Request modest CPU but allow bursting
            requests:
              memory: "512Mi"  # Request what we know we'll need
              cpu: "200m"      # Low CPU request for better scheduling
            limits:
              memory: "1Gi"    # Hard limit to protect the cluster
              cpu: "2"         # Allow high CPU usage when available
      restartPolicy: OnFailure
EOF
```

Apply the optimized batch job:

```bash
kubectl apply -f optimized-batch-job.yaml
```

Let's check the status of our job:

```bash
kubectl get job optimized-batch-job
```

And let's check the logs to see resource usage patterns:

```bash
# Get the pod name
POD_NAME=$(kubectl get pods -l job-name=optimized-batch-job | grep -v Completed | tail -1 | awk '{print $1}')

# View the logs
kubectl logs $POD_NAME
```

#### Step 8: Testing Job Completion and Failure Scenarios

Let's create a job that demonstrates various completion and failure scenarios:

```bash
cat > job-scenarios.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: job-test-scenarios
spec:
  parallelism: 4
  completions: 4
  backoffLimit: 6
  template:
    spec:
      containers:
        - name: test-scenarios
          image: busybox
          command:
            - /bin/sh
            - -c
            - |
              # Get a predictable scenario number based on a hash of the pod name
              POD_NAME=$HOSTNAME
              HASH_VALUE=$(echo $POD_NAME | md5sum | tr -cd '0-9' | cut -c 1-2)
              SCENARIO=$((HASH_VALUE % 4 + 1))
              
              echo "Starting pod $POD_NAME (assigned scenario: $SCENARIO)"
              
              # Different scenarios based on calculated scenario number
              case $SCENARIO in
                1)
                  echo "Scenario 1: Fast success"
                  sleep 5
                  echo "Completed successfully"
                  exit 0
                  ;;
                2)
                  echo "Scenario 2: Success after delay"
                  sleep 30
                  echo "Completed successfully after delay"
                  exit 0
                  ;;
                3)
                  # For retry scenario, use the restart count from the downward API
                  # This is approximated here by checking if the job has been running awhile
                  STARTUP_TIME=$(date +%s)
                  if [ "$STARTUP_TIME" -gt 1744563600 ]; then
                    echo "This is a retry attempt, succeeding this time"
                    sleep 10
                    echo "Completed successfully after previous failure"
                    exit 0
                  else
                    echo "Simulating a failure on first attempt"
                    sleep 15
                    exit 1
                  fi
                  ;;
                4)
                  echo "Scenario 4: Resource exhaustion simulation"
                  echo "Allocating memory until limit is reached..."
              
                  # For simulation, just exit with an error
                  sleep 20
                  echo "Simulating resource exhaustion failure"
                  exit 2
                  ;;
              esac
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "200m"
      restartPolicy: OnFailure
EOF
```

Apply the job scenarios:

```bash
kubectl apply -f job-scenarios.yaml
```

Let's watch the job progress:

```bash
kubectl get pods -l job-name=job-test-scenarios -w --output-watch-events
```

You should see different pods going through their respective scenarios, including success, failure, and retry.

Press Ctrl+C to exit the watch mode.

Check logs for any running pod:
```bash
kubectl logs -f $(kubectl get pods -l job-name=job-test-scenarios -o name | head -1)
```

Let's check the final status of our job:

```bash
kubectl get job job-test-scenarios
```

To see detailed information about the job and its completion status:

```bash
kubectl describe job job-test-scenarios
```

#### Cleanup

When you're done, you can clean up all resources:

```bash
# Delete all the jobs and deployments
kubectl delete jobs --all
kubectl delete cronjobs --all
kubectl delete deployments --all
kubectl delete services rabbitmq
kubectl delete priorityclass batch-priority

# Or delete the entire cluster
bash k8s-cluster-manager.sh delete batch-jobs-cluster
```

#### Understanding What Happened Under the Hood

We've explored batch processing patterns in Kubernetes:

1. `CronJobs:` Regular scheduled tasks for data collection
2. `Jobs with Parallelism:` Accelerating processing by running multiple pods
3. `Queue-Based Processing:` Using a message queue for job coordination
4. `Resource Optimization:` Setting appropriate requests and limits for batch workloads
5. `Priority Classes:` Ensuring proper scheduling priority for different workload types
6. `Failure Handling:` Implementing retry logic and error management
