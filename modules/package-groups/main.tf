locals {
  enabled = module.this.enabled

  package_groups = local.enabled ? var.package_groups : {}

  # awscc takes tags as a list of key/value objects. An empty list is sent as null
  # so that a domain without tags does not plan a perpetual diff against the
  # computed attribute.
  tags = length(module.this.tags) > 0 ? [for key, value in module.this.tags : { key = key, value = value }] : null
}

resource "awscc_codeartifact_package_group" "default" {
  for_each = local.package_groups

  domain_name  = var.domain_name
  domain_owner = var.domain_owner
  pattern      = each.value.pattern
  description  = each.value.description
  contact_info = each.value.contact_info

  origin_configuration = {
    restrictions = {
      for kind, restriction in {
        publish           = each.value.publish
        external_upstream = each.value.external_upstream
        internal_upstream = each.value.internal_upstream
      } :
      kind => {
        # An omitted restriction is sent as INHERIT rather than left unset, so that
        # removing one from the configuration resets it instead of leaving the last
        # applied value in place.
        restriction_mode = restriction == null ? "INHERIT" : restriction.restriction_mode
        repositories     = restriction == null ? null : (length(restriction.repositories) > 0 ? restriction.repositories : null)
      }
    }
  }

  tags = local.tags
}
