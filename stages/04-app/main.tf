# Stage 04 — the application, as plain Kubernetes objects managed by Terraform.
# Each resource below maps 1:1 to a YAML manifest you'd otherwise `kubectl apply`.

terraform {
  required_version = ">= 1.9"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
  }
}

data "terraform_remote_state" "cluster" {
  backend = "local"
  config  = { path = "${path.module}/../01-cluster/terraform.tfstate" }
}

data "terraform_remote_state" "platform" {
  backend = "local"
  config  = { path = "${path.module}/../02-platform/terraform.tfstate" }
}

data "terraform_remote_state" "aws" {
  backend = "local"
  config  = { path = "${path.module}/../03-aws/terraform.tfstate" }
}

locals {
  cluster  = data.terraform_remote_state.cluster.outputs
  platform = data.terraform_remote_state.platform.outputs
  aws      = data.terraform_remote_state.aws.outputs

  labels = {
    "app.kubernetes.io/name"       = var.app_name
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

provider "kubernetes" {
  config_path = local.cluster.kubeconfig_path
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace
  }
}

# Non-secret settings. Shows up as env vars in the pod.
resource "kubernetes_config_map_v1" "app" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = {
    NOTES_BUCKET     = local.aws.bucket_name
    AWS_REGION       = local.aws.region
    AWS_ENDPOINT_URL = local.platform.localstack_url_in_cluster
    APP_VERSION      = var.image
  }
}

# Credentials. Secrets are only base64-encoded in etcd by default — not encrypted.
resource "kubernetes_secret_v1" "aws" {
  metadata {
    name      = "${var.app_name}-aws"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = {
    AWS_ACCESS_KEY_ID     = local.aws.app_access_key_id
    AWS_SECRET_ACCESS_KEY = local.aws.app_secret_access_key
  }
}

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.labels
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = "0" # never drop below desired capacity during a rollout
        max_surge       = "1"
      }
    }

    template {
      metadata {
        labels = local.labels
        annotations = {
          # Env vars are only read at pod start. Changing this hash when the
          # config changes makes Kubernetes roll the pods automatically.
          "checksum/config" = sha256(jsonencode(kubernetes_config_map_v1.app.data))
          "checksum/secret" = sha256(jsonencode(kubernetes_secret_v1.aws.data))
        }
      }

      spec {
        container {
          name              = var.app_name
          image             = var.image
          image_pull_policy = "IfNotPresent" # image is side-loaded with `kind load`, not pulled

          port {
            name           = "http"
            container_port = 8000
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.app.metadata[0].name
            }
          }
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.aws.metadata[0].name
            }
          }

          resources {
            requests = { cpu = "50m", memory = "96Mi" }
            limits   = { memory = "256Mi" }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds = 10
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = "http"
            }
            period_seconds = 5
          }

          security_context {
            run_as_non_root            = true
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
          }

          # gunicorn needs a writable temp dir when the root fs is read-only.
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}

# Stable in-cluster address + load balancing across the pods.
resource "kubernetes_service_v1" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = local.labels
  }

  spec {
    selector = local.labels
    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}

# HTTP routing from outside the cluster: Host header -> Service.
resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    ingress_class_name = local.platform.ingress_class

    rule {
      host = var.hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.app.metadata[0].name
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
  }
}
