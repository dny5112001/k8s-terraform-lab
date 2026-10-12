output "url" {
  value = "http://${var.hostname}:${trimprefix(local.cluster.ingress_url, "http://localhost:")}"
}

output "namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}

output "image" {
  value = var.image
}
