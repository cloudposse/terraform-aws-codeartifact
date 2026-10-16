data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

module "codeartifact" {
  source = "../../"

  repositories = {
    # Stores hold only the external connection. Nothing installs from them directly.
    pypi-store = {
      description         = "Cache of public PyPI"
      external_connection = "public:pypi"
    }
    npm-store = {
      description         = "Cache of public npm"
      external_connection = "public:npmjs"
    }
    # First-party packages, resolving public dependencies through the stores.
    packages = {
      description = "First-party packages"
      upstreams   = ["pypi-store", "npm-store"]
    }
    # A third tier: a team repository that sees everything in `packages`.
    team = {
      description = "Team packages"
      upstreams   = ["packages"]
    }
  }

  repository_endpoint_formats = var.repository_endpoint_formats

  principals_readonly_access = [
    format("arn:%s:iam::%s:root", data.aws_partition.current.partition, data.aws_caller_identity.current.account_id),
  ]

  context = module.this.context
}

# Package groups live in a submodule because they need the hashicorp/awscc provider.
module "package_groups" {
  source = "../../modules/package-groups"

  domain_name  = module.codeartifact.domain_name
  domain_owner = module.codeartifact.domain_owner

  package_groups = {
    # Names under this prefix can only be published, never pulled from public PyPI.
    first-party = {
      pattern     = "/pypi//example~"
      description = "First-party Python packages"
      publish = {
        restriction_mode = "ALLOW"
      }
      external_upstream = {
        restriction_mode = "BLOCK"
      }
      internal_upstream = {
        restriction_mode = "BLOCK"
      }
    }
    # Only the `packages` repository may publish names under this prefix.
    internal = {
      pattern = "/pypi//internal~"
      publish = {
        restriction_mode = "ALLOW_SPECIFIC_REPOSITORIES"
        repositories     = ["packages"]
      }
    }
  }

  context = module.this.context

  # Repositories in an allow list are plain names, so the ordering has to be explicit:
  # the repositories must exist before a package group that allows them.
  depends_on = [module.codeartifact]
}
