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

# --- New Variables for Part 3 ---
variable "db_username" {
  description = "Database administrator username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  # Default value removed for security.
  # Set this value in terraform.tfvars or via env var TF_VAR_db_password
  sensitive = true
}