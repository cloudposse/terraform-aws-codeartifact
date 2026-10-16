# ------------------------------------------------------------------------------
# Domain
# ------------------------------------------------------------------------------

variable "create_domain" {
  type        = bool
  description = <<-EOT
    Whether to create the CodeArtifact domain.

    Set to `false` to manage repositories and package groups inside a domain that
    already exists, for example one owned by another instance of this module. When
    `false`, `domain_name` is required, and no domain permissions policy is managed
    EOT
  default     = true
  nullable    = false
}

variable "domain_name" {
  type        = string
  description = <<-EOT
    Name of the CodeArtifact domain. Defaults to the null-label `id` when `null`.

    Every consumer types this name into its package manager configuration
    (`aws codeartifact login --domain ...`), so prefer something short and stable.
    Changing it replaces the domain, and deleting a domain deletes every package
    stored in it
    EOT
  default     = null

  validation {
    # 2 to 50 characters, lowercase letters, digits and hyphens, starting with a
    # letter and not ending with a hyphen.
    condition     = var.domain_name == null || can(regex("^[a-z][a-z0-9-]{0,48}[a-z0-9]$", var.domain_name))
    error_message = "The `domain_name` must be 2 to 50 lowercase letters, digits or hyphens, start with a letter and not end with a hyphen."
  }
}

variable "domain_owner" {
  type        = string
  description = <<-EOT
    AWS account ID that owns the domain. Only consulted when `create_domain` is
    `false`; defaults to the account of the current provider credentials
    EOT
  default     = null

  validation {
    condition     = var.domain_owner == null || can(regex("^[0-9]{12}$", var.domain_owner))
    error_message = "The `domain_owner` must be a 12-digit AWS account ID."
  }
}

variable "encryption_key_arn" {
  type        = string
  description = <<-EOT
    ARN of a customer managed KMS key used to encrypt the domain's assets. When
    `null`, CodeArtifact uses the AWS managed key `aws/codeartifact`.

    A customer managed key must grant every principal that reads or publishes
    packages, including principals in other accounts, permission to use it.
    Changing this value replaces the domain
    EOT
  default     = null
}

# ------------------------------------------------------------------------------
# Repositories
# ------------------------------------------------------------------------------

variable "repositories" {
  type = map(object({
    description         = optional(string)
    external_connection = optional(string)
    upstreams           = optional(list(string), [])
    policy_document     = optional(string)
  }))
  description = <<-EOT
    Repositories to create in the domain, keyed by repository name.

    - `description`: Description of the repository.
    - `external_connection`: Name of a public package registry to connect to, for
      example `public:pypi`, `public:npmjs` or `public:maven-central`. A repository
      can have at most one external connection.
    - `upstreams`: Keys of other entries in this map, in the order CodeArtifact
      searches them when a package is not found in the repository itself. At most 10.
    - `policy_document`: JSON IAM policy document whose statements are merged into
      this repository's permissions policy, alongside the statements generated from
      the `principals_*` and `organizations_*` inputs.

    Upstreams must be repositories created by this module, and chains are capped at
    a depth of 3: a repository with no upstreams, a repository whose upstreams have
    none, and a repository whose upstreams are at most one level deep. That is a
    Terraform limit, not an AWS one. A repository cannot depend on another instance
    of its own resource, so the module creates one resource per tier.

    The usual shape is a "store" repository holding only the external connection,
    and one or more internal repositories that list it as an upstream:

    ```hcl
    repositories = {
      pypi-store = { external_connection = "public:pypi" }
      python     = { upstreams = ["pypi-store"] }
    }
    ```
    EOT
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for name in keys(var.repositories) : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{1,99}$", name))
    ])
    error_message = "Repository names must be 2 to 100 letters, digits, dots, underscores or hyphens, and start with a letter or digit."
  }

  validation {
    condition = alltrue([
      for repository in values(var.repositories) :
      repository.external_connection == null || startswith(coalesce(repository.external_connection, "-"), "public:")
    ])
    error_message = "An `external_connection` must name a public registry, for example `public:pypi`."
  }

  validation {
    condition     = alltrue([for repository in values(var.repositories) : length(repository.upstreams) <= 10])
    error_message = "A repository can have at most 10 upstreams."
  }
}

variable "repository_destroy_delay" {
  type        = string
  description = <<-EOT
    How long to wait, on destroy, between deleting a tier of repositories and deleting
    the upstream repositories it used. CodeArtifact releases upstream links
    asynchronously, so an immediate delete of the upstream fails with a
    `ConflictException`. Only applies when `repositories` has upstream chains, and
    never delays create or update
    EOT
  default     = "30s"
  nullable    = false
}

variable "repository_endpoint_formats" {
  type        = list(string)
  description = <<-EOT
    Package formats to look up repository endpoint URLs for, for example `pypi`,
    `npm` or `maven`. Each format is looked up for every repository and returned in
    the `repository_endpoints` output. Leave empty to skip the lookups
    EOT
  default     = []
  nullable    = false
}

# ------------------------------------------------------------------------------
# Permissions
# ------------------------------------------------------------------------------

variable "principals_readonly_access" {
  type        = list(string)
  description = <<-EOT
    IAM principal ARNs allowed to read every repository: obtain an authorization
    token, look up repository endpoints, and list and download packages.

    Cross-account access needs both this resource policy grant and an identity
    policy on the caller. Principals in the domain owner's account need only the
    identity policy
    EOT
  default     = []
  nullable    = false
}

variable "principals_publish_access" {
  type        = list(string)
  description = <<-EOT
    IAM principal ARNs allowed to read every repository and publish package
    versions to it. Includes everything granted by `principals_readonly_access`
    EOT
  default     = []
  nullable    = false
}

variable "organizations_readonly_access" {
  type        = list(string)
  description = <<-EOT
    AWS Organizations IDs (`o-xxxxxxxxxx`) whose principals are allowed to read
    every repository. Grants the same actions as `principals_readonly_access`,
    conditioned on `aws:PrincipalOrgID`
    EOT
  default     = []
  nullable    = false
}

variable "organizations_publish_access" {
  type        = list(string)
  description = <<-EOT
    AWS Organizations IDs (`o-xxxxxxxxxx`) whose principals are allowed to read and
    publish to every repository. Grants the same actions as
    `principals_publish_access`, conditioned on `aws:PrincipalOrgID`
    EOT
  default     = []
  nullable    = false
}

variable "domain_policy_document" {
  type        = string
  description = <<-EOT
    JSON IAM policy document whose statements are merged into the domain
    permissions policy, alongside the statements generated from the `principals_*`
    and `organizations_*` inputs. Only used when `create_domain` is `true`
    EOT
  default     = null
}
