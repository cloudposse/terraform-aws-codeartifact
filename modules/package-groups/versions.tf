terraform {
  # 1.3.0 is the floor for `optional()` with defaults, which `package_groups` relies on.
  required_version = ">= 1.3.0"

  required_providers {
    # The hashicorp/aws provider has no CodeArtifact package group resource (checked
    # through v6.68.0), so this submodule uses the Cloud Control provider. It lives
    # in a submodule so that the root module requires only hashicorp/aws: Terraform
    # configures every provider a module declares, even one with no resources planned.
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.0.0"
    }
  }
}
