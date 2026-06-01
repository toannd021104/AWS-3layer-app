variable "aws_region" {
  description = "AWS region for the ECS stack."
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tags."
  type        = string
  default     = "fastapi-ecs"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "vpc_cidr_block" {
  description = "CIDR block for the application VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "public_subnet_cidr_blocks" {
  description = "CIDR blocks for public ALB subnets."
  type        = list(string)
  default     = ["10.40.1.0/24", "10.40.2.0/24"]
}

variable "private_subnet_cidr_blocks" {
  description = "CIDR blocks for private ECS and RDS subnets."
  type        = list(string)
  default     = ["10.40.11.0/24", "10.40.12.0/24"]
}

variable "allowed_http_cidr_blocks" {
  description = "CIDR blocks allowed to access the public frontend load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "api_throttle_burst_limit" {
  description = "API Gateway default route burst limit."
  type        = number
  default     = 100
}

variable "api_throttle_rate_limit" {
  description = "API Gateway default route steady-state requests per second."
  type        = number
  default     = 50
}

variable "domain_name" {
  description = "Optional business domain for the application, for example app.example.com."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "Optional ACM certificate ARN. If set, ALB enables HTTPS and redirects HTTP to HTTPS."
  type        = string
  default     = ""
}

variable "backend_image" {
  description = "Fully qualified backend container image URI."
  type        = string
}

variable "frontend_image" {
  description = "Fully qualified frontend container image URI."
  type        = string
}

variable "backend_cpu" {
  description = "Backend Fargate task CPU units."
  type        = number
  default     = 512
}

variable "backend_memory" {
  description = "Backend Fargate task memory in MiB."
  type        = number
  default     = 1024
}

variable "frontend_cpu" {
  description = "Frontend Fargate task CPU units."
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Frontend Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "backend_desired_count" {
  description = "Desired number of backend ECS tasks."
  type        = number
  default     = 2
}

variable "backend_min_count" {
  description = "Minimum number of backend ECS tasks for autoscaling."
  type        = number
  default     = 2
}

variable "backend_max_count" {
  description = "Maximum number of backend ECS tasks for autoscaling."
  type        = number
  default     = 6
}

variable "frontend_desired_count" {
  description = "Desired number of frontend ECS tasks."
  type        = number
  default     = 2
}

variable "frontend_min_count" {
  description = "Minimum number of frontend ECS tasks for autoscaling."
  type        = number
  default     = 2
}

variable "frontend_max_count" {
  description = "Maximum number of frontend ECS tasks for autoscaling."
  type        = number
  default     = 6
}

variable "ecs_cpu_target_value" {
  description = "Target average ECS service CPU utilization percentage."
  type        = number
  default     = 60
}

variable "postgres_db" {
  description = "PostgreSQL database name."
  type        = string
  default     = "app"
}

variable "postgres_user" {
  description = "PostgreSQL admin username."
  type        = string
  default     = "app"
}

variable "postgres_engine_version" {
  description = "RDS PostgreSQL engine version."
  type        = string
  default     = "16.3"
}

variable "postgres_instance_class" {
  description = "RDS PostgreSQL instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "postgres_allocated_storage" {
  description = "Initial RDS allocated storage in GiB."
  type        = number
  default     = 20
}

variable "postgres_max_allocated_storage" {
  description = "Maximum RDS autoscaled storage in GiB."
  type        = number
  default     = 100
}

variable "postgres_multi_az" {
  description = "Whether to create a Multi-AZ RDS deployment."
  type        = bool
  default     = false
}

variable "postgres_deletion_protection" {
  description = "Whether to protect the RDS instance from deletion."
  type        = bool
  default     = false
}

variable "first_superuser" {
  description = "Initial application superuser email."
  type        = string
  default     = "admin@example.com"
}

variable "smtp_host" {
  description = "Optional SMTP host for transactional email."
  type        = string
  default     = ""
}

variable "smtp_user" {
  description = "Optional SMTP user."
  type        = string
  default     = ""
}

variable "smtp_password" {
  description = "Optional SMTP password."
  type        = string
  default     = ""
  sensitive   = true
}

variable "emails_from_email" {
  description = "Optional sender email address."
  type        = string
  default     = "info@example.com"
}

variable "sentry_dsn" {
  description = "Optional Sentry DSN."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_repository" {
  description = "Optional GitHub repository allowed to assume the deploy role, in owner/repo format."
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "GitHub branch allowed to deploy."
  type        = string
  default     = "master"
}

variable "create_github_oidc_role" {
  description = "Whether to create a GitHub Actions OIDC deploy role for this stack."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}
