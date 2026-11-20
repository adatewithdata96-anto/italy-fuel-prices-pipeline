variable "region" {
  description = "AWS region. eu-south-1 (Milan) is closer to the data, eu-west-1 (Ireland) has every service."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefix for every resource name."
  type        = string
  default     = "fuel-prices"
}

variable "environment" {
  description = "Deployment environment (dev, prod)."
  type        = string
  default     = "dev"
}

variable "github_repository" {
  description = "GitHub repository allowed to push images, as owner/name."
  type        = string
  default     = "<your-username>/italy-fuel-prices-pipeline"
}

variable "create_github_oidc_provider" {
  description = "Set to false if the GitHub OIDC provider already exists in the account."
  type        = bool
  default     = true
}

variable "image_tag" {
  description = "Tag of the ingestion and dbt images in ECR."
  type        = string
  default     = "v1.0.0"
}

variable "mimit_prices_url" {
  description = "URL of the MIMIT daily prices file."
  type        = string
}

variable "mimit_stations_url" {
  description = "URL of the MIMIT station registry file."
  type        = string
}

variable "schedule_expression" {
  description = "When the pipeline runs. MIMIT publishes the files in the morning."
  type        = string
  default     = "cron(0 10 * * ? *)"
}

variable "schedule_timezone" {
  description = "Time zone of the schedule."
  type        = string
  default     = "Europe/Rome"
}

variable "alert_email" {
  description = "Email that receives pipeline failure alerts and budget alerts."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly budget: an email is sent at 80% and 100% of it."
  type        = number
  default     = 10
}

variable "athena_bytes_scanned_cutoff" {
  description = "Maximum bytes a single Athena query can scan (cost guardrail)."
  type        = number
  default     = 1073741824 # 1 GB
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps the logs."
  type        = number
  default     = 30
}
