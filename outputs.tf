output "domain_name" {
  description = "Name of the CodeArtifact domain, the `--domain` argument of `aws codeartifact login`"
  value       = local.enabled ? local.domain_name : null
}

output "domain_owner" {
  description = "AWS account ID that owns the domain, the `--domain-owner` argument required for every cross-account call"
  value       = local.domain_owner
}

output "domain_arn" {
  description = "ARN of the domain. Only set when this module creates the domain"
  value       = one(aws_codeartifact_domain.default[*].arn)
}

output "domain_encryption_key_arn" {
  description = "ARN of the KMS key that encrypts the domain's assets. Only set when this module creates the domain"
  value       = one(aws_codeartifact_domain.default[*].encryption_key)
}

output "domain_s3_bucket_arn" {
  description = "ARN of the S3 bucket CodeArtifact uses to store the domain's package assets. Only set when this module creates the domain"
  value       = one(aws_codeartifact_domain.default[*].s3_bucket_arn)
}

output "repositories" {
  description = "Map of repository name to its `arn`, `name`, `administrator_account`, `external_connection` and `upstreams`"
  value = {
    for name, repository in local.repository_resources : name => {
      arn                   = repository.arn
      name                  = repository.repository
      administrator_account = repository.administrator_account
      external_connection   = local.repositories[name].external_connection
      upstreams             = local.repositories[name].upstreams
    }
  }
}

output "repository_arns" {
  description = "Map of repository name to ARN"
  value       = { for name, repository in local.repository_resources : name => repository.arn }
}

output "repository_endpoints" {
  description = "Map of repository name to a map of package format to endpoint URL, for each format in `repository_endpoint_formats`"
  value = {
    for name in keys(local.repository_resources) : name => {
      for format in var.repository_endpoint_formats :
      format => data.aws_codeartifact_repository_endpoint.default["${name}/${format}"].repository_endpoint
    }
  }
}
