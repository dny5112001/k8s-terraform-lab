variable "app_name" {
  type    = string
  default = "notes-api"
}

variable "namespace" {
  type    = string
  default = "notes"
}

variable "image" {
  description = "Container image. `make app` passes a tag derived from the app's source hash."
  type        = string
  default     = "notes-api:dev"
}

variable "replicas" {
  type    = number
  default = 2
}

variable "hostname" {
  description = "Host the Ingress answers on. *.localhost resolves to 127.0.0.1."
  type        = string
  default     = "notes.localhost"
}
