output "ingress_class" {
  value = "traefik"
}

output "localstack_url_from_host" {
  description = "Use this from your Mac (Terraform, aws CLI)."
  value       = local.cluster.localstack_url
}

output "localstack_url_in_cluster" {
  description = "Use this from pods. <service>.<namespace>.svc.cluster.local is Kubernetes DNS."
  value       = "http://localstack.${helm_release.localstack.namespace}.svc.cluster.local:4566"
}
