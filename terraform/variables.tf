variable "region" {
  description = "AWS Region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "The environment to deploy (e.g., default, development)"
  type        = string
  default     = "default"
}

variable "iam_instance_profile" {
  description = "Name of the existing IAM Instance Profile to use (required for AWS Academy)"
  type        = string
  default     = "LabInstanceProfile"
}