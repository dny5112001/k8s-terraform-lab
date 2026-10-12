variable "cluster_name" {
  description = "Name of the kind cluster (the kubectl context becomes kind-<name>)."
  type        = string
  default     = "lab"
}

variable "node_image" {
  description = "kindest/node image; pins the Kubernetes version."
  type        = string
  default     = "kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0"
}

variable "ingress_node_port" {
  description = "NodePort the ingress controller is exposed on inside the cluster."
  type        = number
  default     = 30080
}

variable "ingress_host_port" {
  description = "Port on your Mac that forwards to the ingress controller."
  type        = number
  default     = 8088
}

variable "localstack_node_port" {
  description = "NodePort LocalStack is exposed on inside the cluster."
  type        = number
  default     = 31566
}

variable "localstack_host_port" {
  description = "Port on your Mac that forwards to LocalStack."
  type        = number
  default     = 4566

  validation {
    condition     = var.localstack_host_port > 1024
    error_message = "Pick an unprivileged port (> 1024)."
  }
}
