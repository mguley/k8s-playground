## Kubernetes Playground

A hands-on learning environment for Kubernetes deployment strategies and resilience patterns.
This repository contains practical scenarios that demonstrate real-world Kubernetes concepts through guided exercises.

## Overview

This playground is designed to help you learn Kubernetes concepts by doing.
Each scenario focuses on a specific pattern or technique used in production Kubernetes environments.
The scenarios are self-contained and include step-by-step instructions, manifest files, and explanations.

## Prerequisites

Before starting, ensure you have the following installed:
- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) (Kubernetes in Docker)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

## Getting Started

This playground includes a handy cluster management script that makes it easy to create and manage local Kubernetes clusters:

```bash
# Clone this repository
git clone https://github.com/mguley/k8s-playground.git
cd k8s-playground

# Make the cluster manager script executable
chmod +x k8s-cluster-manager.sh

# View available commands
./k8s-cluster-manager.sh help
```

## Available Scenarios

### [Scenario 1: Blue-Green Deployment](./scenario-01-blue-green/)

Learn how to implement zero-downtime deployments using the blue-green deployment strategy.
This scenario simulates a real-world situation where a web application needs to be updated without any service interruption.

To begin this scenario:
```bash
cd scenario-01-blue-green
```

### [Scenario 2: Resilient Applications with Health Checks](./scenario-02-resilient-application-with-health-checks/)

Explore how to build self-healing applications in Kubernetes using various health check mechanisms.
This scenario demonstrates a financial services application that can automatically recover from failures.

To begin this scenario:
```bash
cd scenario-02-resilient-application-with-health-checks
```

### [Scenario 3: Multi-tier Application with Database](./scenario-03-multi-tier-application-with-database/)

Build a complete multi-tier application with database, backend API, and frontend components.
This scenario demonstrates how to structure and connect different application layers in Kubernetes using a practical e-commerce platform example.

To begin this scenario:
```bash
cd scenario-03-multi-tier-application-with-database
```

### [Scenario 4: Secure Application Deployment](./scenario-04-secure-application-deployment/)
Implement a healthcare application with multiple layers of security using Kubernetes security features.
This scenario demonstrates how to apply security best practices including namespace isolation, secrets management, network policies, RBAC, and TLS encryption.

To begin this scenario:
```bash
cd scenario-04-secure-application-deployment
```

### [Scenario 5: Batch Processing in Kubernetes](./scenario-05-batch-processing/)
Implement scheduled jobs and batch processing workflows in Kubernetes using Jobs and CronJobs.
This scenario demonstrates how a data analytics company can perform regular data processing tasks on schedule and handle ad-hoc batch workloads efficiently.

To begin this scenario:
```bash
cd scenario-05-batch-processing
```

## Using the Cluster Manager

The included `k8s-cluster-manager.sh` script simplifies cluster management operations:

```bash
# Create a 3-node cluster
./k8s-cluster-manager.sh create my-cluster 3

# Create a cluster with metrics server
./k8s-cluster-manager.sh create my-cluster 3 kindest/node:v1.31.2 deploy-metrics

# Check cluster status
./k8s-cluster-manager.sh status my-cluster

# Delete a cluster
./k8s-cluster-manager.sh delete my-cluster
```

## Contributing

Contributions to add new scenarios or improve existing ones are welcome! To contribute:

1. Fork the repository
2. Create a new scenario directory following the existing pattern
3. Add comprehensive README.md with step-by-step instructions
4. Include all necessary manifest files
5. Submit a pull request

---

Happy learning! Kubernetes is a powerful system with many concepts to master.
