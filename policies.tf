locals {
  principals_any_access    = distinct(concat(var.principals_readonly_access, var.principals_publish_access))
  organizations_any_access = distinct(concat(var.organizations_readonly_access, var.organizations_publish_access))

  generated_policy_enabled = length(local.principals_any_access) + length(local.organizations_any_access) > 0

  domain_policy_enabled = local.create_domain && (local.generated_policy_enabled || var.domain_policy_document != null)

  repository_policy_names = [
    for name, repository in local.repositories : name
    if local.generated_policy_enabled || repository.policy_document != null
  ]

  # Domain-level actions every reader and publisher needs. A cross-account caller
  # authenticates against the domain before it can reach any repository.
  domain_actions = [
    "codeartifact:GetAuthorizationToken",
    "sts:GetServiceBearerToken",
  ]

  repository_readonly_actions = [
    "codeartifact:DescribePackage",
    "codeartifact:DescribePackageVersion",
    "codeartifact:DescribeRepository",
    "codeartifact:GetPackageVersionReadme",
    "codeartifact:GetRepositoryEndpoint",
    "codeartifact:ListPackageVersionAssets",
    "codeartifact:ListPackageVersionDependencies",
    "codeartifact:ListPackageVersions",
    "codeartifact:ListPackages",
    "codeartifact:ReadFromRepository",
  ]

  repository_publish_actions = concat(local.repository_readonly_actions, [
    "codeartifact:PublishPackageVersion",
    "codeartifact:PutPackageMetadata",
  ])
}

data "aws_iam_policy_document" "domain" {
  count = local.domain_policy_enabled ? 1 : 0

  source_policy_documents = compact([var.domain_policy_document])

  dynamic "statement" {
    for_each = length(local.principals_any_access) > 0 ? [1] : []
    content {
      sid       = "PrincipalsAuthorizationToken"
      effect    = "Allow"
      actions   = local.domain_actions
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = local.principals_any_access
      }
    }
  }

  dynamic "statement" {
    for_each = length(local.organizations_any_access) > 0 ? [1] : []
    content {
      sid       = "OrganizationsAuthorizationToken"
      effect    = "Allow"
      actions   = local.domain_actions
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = ["*"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = local.organizations_any_access
      }
    }
  }
}

resource "aws_codeartifact_domain_permissions_policy" "default" {
  count = local.domain_policy_enabled ? 1 : 0

  domain          = local.domain_name
  domain_owner    = local.domain_owner
  policy_document = one(data.aws_iam_policy_document.domain[*].json)
}

data "aws_iam_policy_document" "repository" {
  for_each = toset(local.repository_policy_names)

  source_policy_documents = compact([local.repositories[each.key].policy_document])

  dynamic "statement" {
    for_each = length(var.principals_readonly_access) > 0 ? [1] : []
    content {
      sid       = "PrincipalsReadOnly"
      effect    = "Allow"
      actions   = local.repository_readonly_actions
      resources = [local.repository_resources[each.key].arn]

      principals {
        type        = "AWS"
        identifiers = var.principals_readonly_access
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.principals_publish_access) > 0 ? [1] : []
    content {
      sid       = "PrincipalsPublish"
      effect    = "Allow"
      actions   = local.repository_publish_actions
      resources = [local.repository_resources[each.key].arn]

      principals {
        type        = "AWS"
        identifiers = var.principals_publish_access
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.organizations_readonly_access) > 0 ? [1] : []
    content {
      sid       = "OrganizationsReadOnly"
      effect    = "Allow"
      actions   = local.repository_readonly_actions
      resources = [local.repository_resources[each.key].arn]

      principals {
        type        = "AWS"
        identifiers = ["*"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = var.organizations_readonly_access
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.organizations_publish_access) > 0 ? [1] : []
    content {
      sid       = "OrganizationsPublish"
      effect    = "Allow"
      actions   = local.repository_publish_actions
      resources = [local.repository_resources[each.key].arn]

      principals {
        type        = "AWS"
        identifiers = ["*"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = var.organizations_publish_access
      }
    }
  }
}

resource "aws_codeartifact_repository_permissions_policy" "default" {
  for_each = toset(local.repository_policy_names)

  domain          = local.domain_name
  domain_owner    = local.domain_owner
  repository      = local.repository_resources[each.key].repository
  policy_document = data.aws_iam_policy_document.repository[each.key].json
}
