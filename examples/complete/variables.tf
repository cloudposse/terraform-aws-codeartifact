variable "region" {
  type        = string
  description = "AWS Region"
}

variable "repository_endpoint_formats" {
  type        = list(string)
  description = "Package formats to look up repository endpoint URLs for"
  default     = []
}
