# Stage 01 — a Kubernetes cluster running inside Docker (kind = "Kubernetes IN Docker").
# On AWS this stage would be an EKS cluster + VPC. Everything after this stage
# only needs a kubeconfig, so it doesn't care which kind of cluster it got.

terraform {
  required_version = ">= 1.9"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"
    }
  }
}

provider "kind" {}

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = abspath("${path.module}/kubeconfig")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # The "node" is a Docker container. These mappings punch holes from your Mac
      # into it, so NodePort services become reachable on localhost.
      extra_port_mappings {
        container_port = var.ingress_node_port # Traefik (stage 02) listens here
        host_port      = var.ingress_host_port
      }
      extra_port_mappings {
        container_port = var.localstack_node_port # LocalStack (stage 02) listens here
        host_port      = var.localstack_host_port
      }
    }

    node {
      role = "worker"
    }
  }
}
