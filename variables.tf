# =============================================================================
# Required Variables
# =============================================================================

variable "region" {
  description = "AWS region where resources will be created. Should match the region of your VPC and S3 bucket."
  type        = string
}

variable "profile" {
  description = "AWS CLI profile to use for authentication. Leave null to use default credentials."
  type        = string
  default     = null
}

variable "name" {
  description = "Name prefix for all resources. Used in naming convention: {name}-{resource-type}"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name)) && length(var.name) <= 32
    error_message = "Name must contain only lowercase letters, numbers, and hyphens, and be 32 characters or less."
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs for compute instances. Use private subnets for security. Multiple subnets recommended for high availability."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID is required."
  }
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to compute instances. Must allow outbound HTTPS (443) for AWS API calls."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "At least one security group ID is required."
  }
}

variable "work_bucket_name" {
  description = "S3 bucket name for Nextflow work directory (without s3:// prefix). This bucket stores intermediate workflow files."
  type        = string

  validation {
    condition     = !startswith(var.work_bucket_name, "s3://")
    error_message = "Provide bucket name only, without 's3://' prefix."
  }
}

# =============================================================================
# Compute Environment Configuration
# =============================================================================

variable "head_max_vcpus" {
  description = "Maximum vCPUs for head job compute environment. Head jobs orchestrate the workflow."
  type        = number
  default     = 128
}

variable "head_min_vcpus" {
  description = "Minimum vCPUs to maintain for head job compute environment. Set to 0 to scale to zero when idle."
  type        = number
  default     = 0
}

variable "compute_max_vcpus" {
  description = "Maximum vCPUs for compute job environment. This controls the parallelism of your workflow tasks."
  type        = number
  default     = 256
}

variable "compute_min_vcpus" {
  description = "Minimum vCPUs to maintain for compute job environment. Set to 0 to scale to zero when idle."
  type        = number
  default     = 0
}

variable "instance_types" {
  description = "EC2 instance types for compute environment. Defaults to instance families with NVMe storage for optimal Nextflow performance. ARM64/Graviton instances are not supported in manual setups."
  type        = list(string)
  default     = ["c6id", "m6id", "r6id"]
}

variable "use_spot_instances" {
  description = "Whether to use Spot instances for compute jobs. Spot instances can reduce costs by up to 90% but may be interrupted. Head jobs always use On-Demand."
  type        = bool
  default     = false
}

variable "spot_bid_percentage" {
  description = "Maximum Spot price as percentage of On-Demand price (1-100). Only used when use_spot_instances=true. Leave at 100 to pay market price."
  type        = number
  default     = 100

  validation {
    condition     = var.spot_bid_percentage >= 1 && var.spot_bid_percentage <= 100
    error_message = "Spot bid percentage must be between 1 and 100."
  }
}

variable "allocation_strategy" {
  description = "Allocation strategy for compute environment. BEST_FIT_PROGRESSIVE recommended for On-Demand, SPOT_CAPACITY_OPTIMIZED for Spot."
  type        = string
  default     = "BEST_FIT_PROGRESSIVE"

  validation {
    condition = contains([
      "BEST_FIT",
      "BEST_FIT_PROGRESSIVE",
      "SPOT_CAPACITY_OPTIMIZED",
      "SPOT_PRICE_CAPACITY_OPTIMIZED"
    ], var.allocation_strategy)
    error_message = "Must be one of: BEST_FIT, BEST_FIT_PROGRESSIVE, SPOT_CAPACITY_OPTIMIZED, SPOT_PRICE_CAPACITY_OPTIMIZED."
  }
}

variable "ami_id" {
  description = "Custom AMI ID for compute instances. Leave null to use AWS Batch default ECS-optimized AMI (recommended)."
  type        = string
  default     = null
}

variable "ec2_key_pair" {
  description = "EC2 key pair name for SSH access to compute instances. Leave null to disable SSH access."
  type        = string
  default     = null
}

# =============================================================================
# S3 Configuration
# =============================================================================

variable "work_dir_path" {
  description = "Path within work bucket for Nextflow work directory. Full path will be s3://{work_bucket_name}/{work_dir_path}"
  type        = string
  default     = "work"
}

variable "additional_bucket_arns" {
  description = "Additional S3 bucket ARNs that jobs need read/write access to (e.g., for input/output data)."
  type        = list(string)
  default     = []
}

# =============================================================================
# Seqera Platform Integration
# =============================================================================

variable "seqera_server_url" {
  description = "Seqera Platform API server URL."
  type        = string
  default     = "https://api.cloud.seqera.io"
}

variable "seqera_access_token" {
  description = "Seqera Platform access token for authentication."
  type        = string
  sensitive   = true
}

variable "seqera_workspace_id" {
  description = "Seqera Platform workspace ID where the compute environment will be created."
  type        = number
}

variable "seqera_credentials_name" {
  description = "Name for AWS credentials in Seqera Platform. Defaults to '{name}-aws-credentials'."
  type        = string
  default     = null
}

variable "seqera_compute_env_name" {
  description = "Name for compute environment in Seqera Platform. Defaults to var.name."
  type        = string
  default     = null
}

variable "seqera_compute_env_description" {
  description = "Description for the compute environment in Seqera Platform."
  type        = string
  default     = null
}

# =============================================================================
# Nextflow Configuration
# =============================================================================

variable "head_job_cpus" {
  description = "Number of CPUs allocated for the head job. Leave null to use Seqera Platform defaults."
  type        = number
  default     = null
}

variable "head_job_memory_mb" {
  description = "Memory allocation for the head job in MB. Leave null to use Seqera Platform defaults."
  type        = number
  default     = null
}

variable "enable_wave" {
  description = "Enable Wave containers for automatic container provisioning."
  type        = bool
  default     = false
}

variable "enable_fusion" {
  description = "Enable Fusion file system for improved S3 performance. Requires enable_wave to be true."
  type        = bool
  default     = false
}

variable "pre_run_script" {
  description = "Bash script to run before workflow execution. Use for environment setup, loading modules, etc."
  type        = string
  default     = null
}

variable "post_run_script" {
  description = "Bash script to run after workflow execution. Use for cleanup, archiving results, notifications, etc."
  type        = string
  default     = null
}

variable "nextflow_config" {
  description = "Additional Nextflow configuration to append to the compute environment. Use heredoc syntax for multi-line config."
  type        = string
  default     = null
}


# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Tags to apply to all AWS resources created by this module."
  type        = map(string)
  default     = {}
}
