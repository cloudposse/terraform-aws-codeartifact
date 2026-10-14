variable "domain_name" {
  type        = string
  description = "Name of the CodeArtifact domain the package groups belong to. Usually the `domain_name` output of the root module"
}

variable "domain_owner" {
  type        = string
  description = "AWS account ID that owns the domain. Usually the `domain_owner` output of the root module. Defaults to the account of the current provider credentials"
  default     = null
}

variable "package_groups" {
  type = map(object({
    pattern      = string
    description  = optional(string)
    contact_info = optional(string)
    publish = optional(object({
      restriction_mode = string
      repositories     = optional(list(string), [])
    }))
    external_upstream = optional(object({
      restriction_mode = string
      repositories     = optional(list(string), [])
    }))
    internal_upstream = optional(object({
      restriction_mode = string
      repositories     = optional(list(string), [])
    }))
  }))
  description = <<-EOT
    Package groups with origin controls, keyed by a name of your choosing.

    - `pattern`: Package group definition, `/<format>/<namespace>/<package>`. Formats
      without namespaces, such as `pypi`, leave the namespace empty (`/pypi//name`).
      Append `~` for a prefix match (`/pypi//mycompany~`) and use `*` for a whole
      segment (`/npm/@mycompany/*`). The API validates the pattern at apply time,
      not at plan time.
    - `description`, `contact_info`: Free text shown in the console.
    - `publish`, `external_upstream`, `internal_upstream`: Origin restrictions.
      `restriction_mode` is one of `ALLOW`, `BLOCK`, `ALLOW_SPECIFIC_REPOSITORIES` or
      `INHERIT`. `repositories` lists repository names and is only valid with
      `ALLOW_SPECIFIC_REPOSITORIES`. Reference them through the root module's
      `repositories` output (`module.codeartifact.repositories["name"].name`) so
      that Terraform creates the repositories before the package group. An
      omitted restriction is set to `INHERIT`, which takes the setting of the
      closest parent group.

    Origin controls are the defense against dependency confusion: with `publish`
    set to `ALLOW` and both upstreams set to `BLOCK`, a version of a matching package
    can only come from a direct publish into the domain, never from a public
    registry, even if someone registers the same name there.

    Package groups are managed with the `hashicorp/awscc` provider, because the
    `hashicorp/aws` provider has no resource for them. A package group is not a
    repository setting: it applies to every repository in the domain
    EOT
  default     = {}
  nullable    = false

  validation {
    condition = alltrue(flatten([
      for group in values(var.package_groups) : [
        for restriction in [group.publish, group.external_upstream, group.internal_upstream] :
        restriction == null ? true : contains(["ALLOW", "BLOCK", "ALLOW_SPECIFIC_REPOSITORIES", "INHERIT"], restriction.restriction_mode)
      ]
    ]))
    error_message = "A `restriction_mode` must be one of `ALLOW`, `BLOCK`, `ALLOW_SPECIFIC_REPOSITORIES` or `INHERIT`."
  }

  validation {
    condition = alltrue(flatten([
      for group in values(var.package_groups) : [
        for restriction in [group.publish, group.external_upstream, group.internal_upstream] :
        restriction == null ? true : (restriction.restriction_mode == "ALLOW_SPECIFIC_REPOSITORIES") == (length(restriction.repositories) > 0)
      ]
    ]))
    error_message = "A restriction lists `repositories` if and only if its `restriction_mode` is `ALLOW_SPECIFIC_REPOSITORIES`."
  }
}
