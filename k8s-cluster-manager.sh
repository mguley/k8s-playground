#!/bin/bash
#
# k8s-cluster-manager.sh - v1.1.0
# A helper script to manage Kubernetes clusters via kind.
#
# Prerequisites:
#   • Docker (https://docs.docker.com/get-docker/)
#   • kind   (https://kind.sigs.k8s.io/docs/user/quick-start/)
#   • kubectl (https://kubernetes.io/docs/tasks/tools/install-kubectl/)
#
# Default values:
#   • Cluster name:   k8s-cluster
#   • Node count:     1
#   • Node image:     (latest kindest/node)
#
# Usage:
#   ./k8s-cluster-manager.sh [command] [args]
#
# Commands:
#   create [name] [nodes] [node_image] [deploy-metrics]   Create a new kind cluster
#                                                         Use "deploy-metrics" as 4th param to install metrics-server
#   delete [name]                                         Delete an existing kind cluster
#   list                                                  List all kind clusters
#   status [name]                                         Show nodes, pods & services of a cluster
#   use [name]                                            Switch kubectl context to a cluster
#   kubeconfig [name]                                     Print the kubeconfig for a cluster
#   contexts                                              List all kubectl contexts
#   install-metrics [name]                                Install metrics-server on an existing cluster
#   version                                               Show script, kind & kubectl versions
#   help                                                  Display this help text
#
# Examples:
#   # Create a 3‑node cluster named "dev-cluster"
#   ./k8s-cluster-manager.sh create dev-cluster 3
#
#   # Create a single‑node cluster using a specific node image
#   ./k8s-cluster-manager.sh create test 1 kindest/node:v1.24.0
#
#   # Create a cluster with metrics-server installed
#   ./k8s-cluster-manager.sh create prod 3 kindest/node:v1.31.2 deploy-metrics
#
#   # Install metrics-server on an existing cluster
#   ./k8s-cluster-manager.sh install-metrics dev-cluster
#
#   # List clusters
#   ./k8s-cluster-manager.sh list
#
#   # Show status of "dev-cluster"
#   ./k8s-cluster-manager.sh status dev-cluster
#
#   # Switch kubectl to "dev-cluster"
#   ./k8s-cluster-manager.sh use dev-cluster
#
#   # Dump the kubeconfig for "dev-cluster"
#   ./k8s-cluster-manager.sh kubeconfig dev-cluster
#
#   # Show all kubectl contexts
#   ./k8s-cluster-manager.sh contexts
#
#   # Delete "dev-cluster"
#   ./k8s-cluster-manager.sh delete dev-cluster
#
#   # Show versions
#   ./k8s-cluster-manager.sh version
#

set -euo pipefail

SCRIPT_VERSION="1.1.0"
DEFAULT_CLUSTER_NAME="k8s-cluster"

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Ensure Docker is installed (kind requires Docker)
#------------------------------------------------------------------------------
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error:${NC} Docker is not installed or not in your PATH."
        echo "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Ensure kind is installed
#------------------------------------------------------------------------------
check_kind() {
    if ! command -v kind &> /dev/null; then
        echo -e "${RED}Error:${NC} kind is not installed or not in your PATH."
        echo "Please install kind: https://kind.sigs.k8s.io/docs/user/quick-start/"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Ensure kubectl is installed
#------------------------------------------------------------------------------
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error:${NC} kubectl is not installed or not in your PATH."
        echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Install the Metrics Server on a cluster
#   args: [cluster_name]
#------------------------------------------------------------------------------
install_metrics_server() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"

    echo -e "${BLUE}→ Installing Metrics Server on cluster '${name}'...${NC}"

    # Check if the cluster exists
    if ! kind get clusters | grep -q "^${name}$"; then
        echo -e "${RED}✖ Cluster '${name}' not found.${NC}"
        echo "Use 'kind get clusters' to list existing clusters."
        exit 1
    fi

    # Switch kubectl context to the cluster
    kubectl config use-context "kind-${name}" &> /dev/null

    # Check if metrics-server is already installed
    if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        echo -e "${YELLOW}⚠ Metrics Server is already installed on cluster '${name}'.${NC}"
        return 0
    fi

    echo -e "${BLUE}→ Deploying Metrics Server...${NC}"
    if kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml; then
        echo -e "${GREEN}✔ Metrics Server deployment initiated.${NC}"

        echo -e "${BLUE}→ Patching Metrics Server to work with self-signed certificates...${NC}"
        kubectl patch -n kube-system deployment metrics-server --type='json' \
            -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

        echo -e "${BLUE}→ Waiting for Metrics Server to start...${NC}"
        sleep 10

        # Check if metrics-server pod is running
        if kubectl get pods -n kube-system -l k8s-app=metrics-server | grep -q "Running"; then
            echo -e "${GREEN}✔ Metrics Server successfully installed and running.${NC}"
            kubectl get pods -n kube-system -l k8s-app=metrics-server
        else
            echo -e "${YELLOW}⚠ Metrics Server pods are not yet running. Check status with:${NC}"
            echo "kubectl get pods -n kube-system -l k8s-app=metrics-server"
        fi
    else
        echo -e "${RED}✖ Failed to deploy Metrics Server.${NC}"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Create a kind cluster
#   args: [cluster_name] [node_count] [node_image (optional)] [deploy-metrics (optional)]
#------------------------------------------------------------------------------
create_cluster() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    local nodes="${2:-1}"
    local image="${3:-}"
    local deploy_metrics="${4:-}"

    echo -e "${BLUE}→ Creating kind cluster '${name}' with ${nodes} node(s)...${NC}"

    # Temp config file, guaranteed removal on exit
    local cfg
    cfg=$(mktemp)
    trap 'rm -f "$cfg"' EXIT

    # Build minimal kind config
    cat > "$cfg" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${name}
nodes:
  - role: control-plane${image:+
    image: ${image}}
EOF

    # Add worker nodes if requested
    for ((i=1; i<nodes; i++)); do
        cat >> "$cfg" <<EOF
  - role: worker${image:+
    image: ${image}}
EOF
    done

    # Launch cluster
    if kind create cluster --config="$cfg"; then
        echo -e "${GREEN}✔ Cluster '${name}' created.${NC}"
        echo -e "${BLUE}→ Setting kubectl context to kind-${name}${NC}"
        kubectl config use-context "kind-${name}" &> /dev/null

        echo -e "${BLUE}→ Cluster Info:${NC}"
        kubectl cluster-info

        echo -e "${BLUE}→ Nodes:${NC}"
        kubectl get nodes

        # Deploy metrics-server if requested
        if [ "$deploy_metrics" = "deploy-metrics" ]; then
            install_metrics_server "$name"
        fi
    else
        echo -e "${RED}✖ Failed to create cluster '${name}'.${NC}"
        exit 1
    fi

    # Clear the EXIT trap so we don't delete other temp files later
    trap - EXIT
}

#------------------------------------------------------------------------------
# Delete a kind cluster
#   args: [cluster_name]
#------------------------------------------------------------------------------
delete_cluster() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    echo -e "${YELLOW}→ Deleting kind cluster '${name}'...${NC}"

    if kind delete cluster --name "$name"; then
        echo -e "${GREEN}✔ Cluster '${name}' deleted.${NC}"
    else
        echo -e "${RED}✖ Could not delete cluster '${name}'.${NC}"
        echo "Use 'kind get clusters' to list existing clusters."
        exit 1
    fi
}

#------------------------------------------------------------------------------
# List all kind clusters
#------------------------------------------------------------------------------
list_clusters() {
    echo -e "${BLUE}→ Existing kind clusters:${NC}"
    kind get clusters || echo "(none)"
}

#------------------------------------------------------------------------------
# Show status of a cluster: nodes, pods & services
#   args: [cluster_name]
#------------------------------------------------------------------------------
cluster_status() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    echo -e "${BLUE}→ Status for cluster '${name}':${NC}"

    if kind get clusters | grep -q "^${name}$"; then
        echo -e "${GREEN}✔ Cluster '${name}' exists.${NC}"

        kubectl config use-context "kind-${name}" &> /dev/null

        echo -e "${BLUE}→ Nodes:${NC}"
        kubectl get nodes

        echo -e "${BLUE}→ Pods (all ns):${NC}"
        kubectl get pods --all-namespaces

        echo -e "${BLUE}→ Services (all ns):${NC}"
        kubectl get svc --all-namespaces

        # Check if metrics-server is installed
        if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
            echo -e "${BLUE}→ Metrics Server:${NC} ${GREEN}Installed${NC}"

            # Check if metrics API is available
            if kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" &> /dev/null; then
                echo -e "${BLUE}→ Metrics API:${NC} ${GREEN}Available${NC}"
            else
                echo -e "${BLUE}→ Metrics API:${NC} ${YELLOW}Not yet available${NC}"
            fi
        else
            echo -e "${BLUE}→ Metrics Server:${NC} ${YELLOW}Not installed${NC}"
            echo "  Run './$(basename "$0") install-metrics $name' to install"
        fi
    else
        echo -e "${YELLOW}⚠ Cluster '${name}' not found.${NC}"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Switch kubectl context to a kind cluster
#   args: [cluster_name]
#------------------------------------------------------------------------------
use_context() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    echo -e "${BLUE}→ Switching kubectl context to kind-${name}...${NC}"
    kubectl config use-context "kind-${name}"
}

#------------------------------------------------------------------------------
# Print the kubeconfig for a kind cluster
#   args: [cluster_name]
#------------------------------------------------------------------------------
get_kubeconfig() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    echo -e "${BLUE}→ Kubeconfig for '${name}':${NC}"
    kind get kubeconfig --name "$name"
}

#------------------------------------------------------------------------------
# List all kubectl contexts
#------------------------------------------------------------------------------
list_contexts() {
    echo -e "${BLUE}→ All kubectl contexts:${NC}"
    kubectl config get-contexts
}

#------------------------------------------------------------------------------
# Show versions of script, kind & kubectl
#------------------------------------------------------------------------------
version() {
    echo -e "${BLUE}Script version: ${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}kind version:   $(kind version)${NC}"
    echo -e "${BLUE}kubectl version:$(kubectl version --client)${NC}"
}

#------------------------------------------------------------------------------
# Display help / usage information
#------------------------------------------------------------------------------
show_help() {
    sed -n '1,65p' "$0"
}

#––– Main ---------------------------------------------------------------------

# Pre-flight checks
check_docker
check_kind
check_kubectl

# Dispatch
cmd="${1:-help}"; shift || true
case "$cmd" in
  create)          create_cluster       "$@" ;;
  delete)          delete_cluster       "$@" ;;
  list)            list_clusters        ;;
  status)          cluster_status       "$@" ;;
  use)             use_context          "$@" ;;
  kubeconfig)      get_kubeconfig       "$@" ;;
  contexts)        list_contexts        ;;
  install-metrics) install_metrics_server "$@" ;;
  version)         version              ;;
  help|--help)     show_help            ;;
  *) echo -e "${RED}Unknown command: $cmd${NC}" >&2; show_help; exit 1 ;;
esac

exit 0