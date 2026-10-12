# Stage 03 — AWS resources. This is ordinary AWS Terraform code; the only
# LocalStack-specific part is the provider block (endpoints + fake creds).
# Point those at real AWS and the rest works unchanged.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }
}

data "terraform_remote_state" "cluster" {
  backend = "local"
  config = {
    path = "${path.module}/../01-cluster/terraform.tfstate"
  }
}

locals {
  localstack = data.terraform_remote_state.cluster.outputs.localstack_url

  tags = {
    project     = "k8s-terraform-lab"
    environment = var.environment
    managed_by  = "terraform"
  }
}

provider "aws" {
  region     = var.region
  access_key = "test"
  secret_key = "test"

  # Skip calls that only make sense against real AWS.
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = local.localstack
    iam = local.localstack
    sts = local.localstack
  }

  default_tags {
    tags = local.tags
  }
}

module "notes_bucket" {
  source = "../../modules/notes-bucket"

  name          = "notes-${var.environment}"
  force_destroy = true # fine for a lab; never for real data
}
