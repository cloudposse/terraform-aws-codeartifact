terraform {
  # 1.3.0 is the floor for `optional()` with defaults, which `repositories` relies
  # on. 1.4.0 is the floor for `terraform_data`, which hosts the preconditions that
  # validate the repository upstream graph (see `main.tf`).
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
    # time_sleep delays destroy between repository tiers (see `main.tf`).
    time = {
      source  = "hashicorp/time"
      version = ">= 0.7.0"
    }
  }
}
