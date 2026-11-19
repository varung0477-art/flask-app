variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional named AWS CLI profile. Leave null to use env vars / default chain."
  type        = string
  default     = null
}

variable "project_name" {
  description = "Prefix for all resource names. Also the ECR repo name and the EC2 'Name' tag (used by the CI/CD pipeline)."
  type        = string
  default     = "devops-challenge"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.project_name))
    error_message = "project_name must be 2-20 chars: lowercase letters, digits, hyphens; start with a letter."
  }
}

variable "instance_type" {
  description = "EC2 instance type (t3.micro is Free Tier eligible)."
  type        = string
  default     = "t3.micro"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH (port 22) to the instance. CHANGE THIS to your IP, e.g. 203.0.113.7/32."
  type        = string
  default     = "1.2.3.4/32"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR block."
  }
}

variable "ssh_key_name" {
  description = "Optional existing EC2 key pair name for SSH. Not needed for deployments (they use SSM)."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "Optional VPC id. Defaults to the region's default VPC. Must contain >=2 public subnets in different AZs."
  type        = string
  default     = null
}

variable "app_port" {
  description = "Port the container listens on."
  type        = number
  default     = 5000
}
