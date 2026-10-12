variable "traefik_chart_version" {
  type    = string
  default = "41.7.1"
}

variable "localstack_chart_version" {
  type    = string
  default = "0.7.1"
}

variable "localstack_image_tag" {
  description = "Last LocalStack community release that runs without an auth token."
  type        = string
  default     = "4.14"
}
