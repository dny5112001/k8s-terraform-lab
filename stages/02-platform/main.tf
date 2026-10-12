# Stage 02 — shared platform services installed into the cluster with Helm:
#   * Traefik  : ingress controller (on AWS: the AWS Load Balancer Controller / an ALB)
#   * LocalStack: a fake AWS cloud (on AWS: ...the real thing)

terraform {
  required_version = ">= 1.9"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

# Read stage 01's outputs straight from its state file.
data "terraform_remote_state" "cluster" {
  backend = "local"
  config = {
    path = "${path.module}/../01-cluster/terraform.tfstate"
  }
}

locals {
  cluster = data.terraform_remote_state.cluster.outputs
}

provider "helm" {
  kubernetes = {
    config_path = local.cluster.kubeconfig_path
  }
}

resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  wait             = true
  atomic           = true # roll back a failed install instead of leaving an orphan release

  values = [yamlencode({
    # NodePort, not the chart's default LoadBalancer: kind has no cloud LB, so a
    # LoadBalancer service never gets an IP and `wait` times out.
    service = { spec = { type = "NodePort" } }
    ports = {
      web       = { nodePort = local.cluster.ingress_node_port }
      websecure = { expose = { default = false } }
    }
    ingressClass = { enabled = true, isDefaultClass = true, name = "traefik" }
  })]
}

resource "helm_release" "localstack" {
  name             = "localstack"
  namespace        = "localstack"
  create_namespace = true
  repository       = "https://localstack.github.io/helm-charts"
  chart            = "localstack"
  version          = var.localstack_chart_version
  wait             = true
  atomic           = true
  timeout          = 600

  values = [yamlencode({
    # The chart defaults to the Pro image; the free image needs a pinned version
    # because newer releases require a LocalStack account token.
    image = { repository = "localstack/localstack", tag = var.localstack_image_tag }
    service = {
      type        = "NodePort"
      edgeService = { nodePort = local.cluster.localstack_node_port }
    }
    extraEnvVars = [{ name = "SERVICES", value = "s3,iam,sts" }]
  })]
}
