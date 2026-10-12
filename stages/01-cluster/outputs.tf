# Outputs are this stage's public API. Later stages read them via terraform_remote_state.

output "cluster_name" {
  value = kind_cluster.this.name
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}

output "ingress_node_port" {
  value = var.ingress_node_port
}

output "ingress_url" {
  value = "http://localhost:${var.ingress_host_port}"
}

output "localstack_node_port" {
  value = var.localstack_node_port
}

output "localstack_url" {
  value = "http://localhost:${var.localstack_host_port}"
}
