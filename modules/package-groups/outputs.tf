output "package_group_arns" {
  description = "Map of package group key to ARN"
  value       = { for key, group in awscc_codeartifact_package_group.default : key => group.arn }
}

output "package_group_patterns" {
  description = "Map of package group key to pattern"
  value       = { for key, group in awscc_codeartifact_package_group.default : key => group.pattern }
}
