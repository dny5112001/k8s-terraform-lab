variable "name" {
  description = "Bucket name (globally unique on real AWS)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "Bucket names: 3-63 chars, lowercase letters, digits, dots, hyphens."
  }
}

variable "versioning" {
  type    = bool
  default = true
}

variable "force_destroy" {
  description = "Allow destroying the bucket even if it still contains objects."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
