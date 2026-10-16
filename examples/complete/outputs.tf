output "domain_name" {
  description = "Name of the CodeArtifact domain"
  value       = module.codeartifact.domain_name
}

output "domain_owner" {
  description = "AWS account ID that owns the domain"
  value       = module.codeartifact.domain_owner
}

output "domain_arn" {
  description = "ARN of the domain"
  value       = module.codeartifact.domain_arn
}

output "repositories" {
  description = "Map of repository name to repository attributes"
  value       = module.codeartifact.repositories
}

output "repository_arns" {
  description = "Map of repository name to ARN"
  value       = module.codeartifact.repository_arns
}

output "repository_endpoints" {
  description = "Map of repository name to a map of package format to endpoint URL"
  value       = module.codeartifact.repository_endpoints
}

output "package_group_arns" {
  description = "Map of package group key to ARN"
  value       = module.package_groups.package_group_arns
}
