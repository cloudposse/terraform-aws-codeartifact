locals {
  enabled = module.this.enabled

  create_domain = local.enabled && var.create_domain

  domain_name = local.create_domain ? one(aws_codeartifact_domain.default[*].domain) : var.domain_name
  domain_owner = local.create_domain ? one(aws_codeartifact_domain.default[*].owner) : (
    local.enabled ? coalesce(var.domain_owner, one(data.aws_caller_identity.current[*].account_id)) : null
  )

  repositories = local.enabled ? var.repositories : {}

  # A repository cannot list another instance of its own resource as an upstream,
  # and AWS rejects an upstream that does not exist yet. Repositories are therefore
  # partitioned into tiers by the depth of their upstream chain, with one resource
  # per tier, so that every upstream is created before the repositories that use it
  # and destroyed after them.
  repository_names_level_0 = [for name, repository in local.repositories : name if length(repository.upstreams) == 0]
  repository_names_level_1 = [
    for name, repository in local.repositories : name
    if length(repository.upstreams) > 0 && alltrue([for upstream in repository.upstreams : contains(local.repository_names_level_0, upstream)])
  ]
  repository_names_level_2 = [
    for name, repository in local.repositories : name
    if length(repository.upstreams) > 0
    && !contains(local.repository_names_level_1, name)
    && alltrue([for upstream in repository.upstreams : contains(concat(local.repository_names_level_0, local.repository_names_level_1), upstream)])
  ]

  # Graph errors, reported by the guard below.
  repository_unknown_upstreams = flatten([
    for name, repository in local.repositories : [
      for upstream in repository.upstreams : "${name} -> ${upstream}" if !contains(keys(local.repositories), upstream)
    ]
  ])
  repository_names_unplaced = [
    for name in keys(local.repositories) : name
    if !contains(concat(local.repository_names_level_0, local.repository_names_level_1, local.repository_names_level_2), name)
  ]

  repository_resources = merge(
    aws_codeartifact_repository.level_0,
    aws_codeartifact_repository.level_1,
    aws_codeartifact_repository.level_2,
  )
}

data "aws_caller_identity" "current" {
  count = local.enabled && !var.create_domain && var.domain_owner == null ? 1 : 0
}

# The graph checks live on a `terraform_data` rather than on a repository resource,
# because a precondition only runs when its resource has instances, and the inputs
# these checks reject (a cycle, an over-deep chain) are exactly the ones that leave
# a tier empty.
resource "terraform_data" "repository_graph" {
  count = local.enabled ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.create_domain || var.domain_name != null
      error_message = "The `domain_name` is required when `create_domain` is `false`."
    }

    precondition {
      condition     = length(local.repository_unknown_upstreams) == 0
      error_message = "Every upstream must name another key of `repositories`. These do not: ${join(", ", local.repository_unknown_upstreams)}."
    }

    precondition {
      condition     = length(local.repository_unknown_upstreams) > 0 || length(local.repository_names_unplaced) == 0
      error_message = "Upstream chains must be acyclic and at most 3 repositories deep. These repositories are part of a cycle or nested deeper: ${join(", ", local.repository_names_unplaced)}."
    }
  }
}

resource "aws_codeartifact_domain" "default" {
  count = local.create_domain ? 1 : 0

  domain         = coalesce(var.domain_name, module.this.id)
  encryption_key = var.encryption_key_arn

  tags = module.this.tags

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{0,48}[a-z0-9]$", coalesce(var.domain_name, module.this.id)))
      error_message = "The domain name `${coalesce(var.domain_name, module.this.id)}` derived from the null-label `id` is not a valid CodeArtifact domain name. Set `domain_name`, or adjust the label inputs."
    }
  }
}

resource "aws_codeartifact_repository" "level_0" {
  for_each = { for name in local.repository_names_level_0 : name => local.repositories[name] }

  repository   = each.key
  domain       = local.domain_name
  domain_owner = local.domain_owner
  description  = each.value.description

  dynamic "external_connections" {
    for_each = each.value.external_connection == null ? [] : [each.value.external_connection]
    content {
      external_connection_name = external_connections.value
    }
  }

  tags = module.this.tags
}

resource "aws_codeartifact_repository" "level_1" {
  for_each = { for name in local.repository_names_level_1 : name => local.repositories[name] }

  repository   = each.key
  domain       = local.domain_name
  domain_owner = local.domain_owner
  description  = each.value.description

  dynamic "external_connections" {
    for_each = each.value.external_connection == null ? [] : [each.value.external_connection]
    content {
      external_connection_name = external_connections.value
    }
  }

  dynamic "upstream" {
    for_each = each.value.upstreams
    content {
      repository_name = aws_codeartifact_repository.level_0[upstream.value].repository
    }
  }

  tags = module.this.tags
}

resource "aws_codeartifact_repository" "level_2" {
  for_each = { for name in local.repository_names_level_2 : name => local.repositories[name] }

  repository   = each.key
  domain       = local.domain_name
  domain_owner = local.domain_owner
  description  = each.value.description

  dynamic "external_connections" {
    for_each = each.value.external_connection == null ? [] : [each.value.external_connection]
    content {
      external_connection_name = external_connections.value
    }
  }

  dynamic "upstream" {
    for_each = each.value.upstreams
    content {
      repository_name = try(
        aws_codeartifact_repository.level_1[upstream.value].repository,
        aws_codeartifact_repository.level_0[upstream.value].repository,
      )
    }
  }

  tags = module.this.tags
}

data "aws_codeartifact_repository_endpoint" "default" {
  for_each = {
    for pair in setproduct(keys(local.repository_resources), var.repository_endpoint_formats) :
    "${pair[0]}/${pair[1]}" => { repository = pair[0], format = pair[1] }
  }

  domain       = local.domain_name
  domain_owner = local.domain_owner
  repository   = local.repository_resources[each.value.repository].repository
  format       = each.value.format
}
