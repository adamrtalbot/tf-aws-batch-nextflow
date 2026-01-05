# =============================================================================
# AWS Batch Resources for Seqera Platform (Manual Setup)
#
# This file creates AWS Batch compute environments and job queues without
# using Batch Forge. Resources are created via AWS provider, then registered
# with Seqera Platform.
#
# Architecture:
#   1. Launch Template - Custom EC2 configuration (CloudWatch, NVMe, AWS CLI)
#   2. Head Compute Environment - On-demand instances for workflow orchestration
#   3. Compute Environment - On-demand or Spot instances for workflow tasks
#   4. Job Queues - Head queue and compute queue linked to respective CEs
#   5. Seqera Integration - Credentials and compute environment registration
# =============================================================================

# =============================================================================
# Launch Template
# Provides custom user data for EC2 instances:
# - CloudWatch agent for monitoring
# - NVMe storage mounting for instance store
# - AWS CLI v2 installation
# =============================================================================

resource "aws_launch_template" "batch" {
  name        = "${var.name}-batch-lt"
  description = "Launch template for ${var.name} AWS Batch compute environment"
  tags        = local.common_tags

  # Custom AMI (optional)
  image_id = var.ami_id

  # SSH key pair (optional)
  key_name = var.ec2_key_pair

  # User data script for instance initialization
  # Source: https://docs.seqera.io/platform-enterprise/24.2/enterprise/advanced-topics/manual-aws-batch-setup
  # Uses Fusion script (with NVMe formatting) when enable_fusion=true, otherwise CLI-only script
  user_data = base64encode(var.enable_fusion ? local.user_data_fusion : local.user_data_cli)

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      "Name" = "${var.name}-batch-instance"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      "Name" = "${var.name}-batch-volume"
    })
  }
}

# =============================================================================
# AWS Batch Compute Environments
# =============================================================================

# -----------------------------------------------------------------------------
# Head Compute Environment
# Always uses On-Demand instances for reliability (head job orchestrates workflow)
# -----------------------------------------------------------------------------
resource "aws_batch_compute_environment" "head" {
  compute_environment_name = local.head_ce_name
  type                     = "MANAGED"
  state                    = "ENABLED"
  service_role             = aws_iam_role.batch_service.arn
  tags                     = local.common_tags

  compute_resources {
    type                = "EC2" # Always On-Demand for head
    allocation_strategy = "BEST_FIT_PROGRESSIVE"
    min_vcpus           = var.head_min_vcpus
    max_vcpus           = var.head_max_vcpus
    instance_role       = aws_iam_instance_profile.ecs_instance.arn
    instance_type       = var.instance_types
    subnets             = var.subnet_ids
    security_group_ids  = var.security_group_ids

    launch_template {
      launch_template_id = aws_launch_template.batch.id
      version            = "$Latest"
    }

    tags = local.common_tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Compute Environment
# Can use On-Demand or Spot instances based on configuration
# -----------------------------------------------------------------------------
resource "aws_batch_compute_environment" "compute" {
  compute_environment_name = local.compute_ce_name
  type                     = "MANAGED"
  state                    = "ENABLED"
  service_role             = aws_iam_role.batch_service.arn
  tags                     = local.common_tags

  compute_resources {
    type                = var.use_spot_instances ? "SPOT" : "EC2"
    allocation_strategy = local.compute_allocation_strategy
    min_vcpus           = var.compute_min_vcpus
    max_vcpus           = var.compute_max_vcpus
    instance_role       = aws_iam_instance_profile.ecs_instance.arn
    instance_type       = var.instance_types
    subnets             = var.subnet_ids
    security_group_ids  = var.security_group_ids

    # Spot-specific configuration
    spot_iam_fleet_role = var.use_spot_instances ? aws_iam_role.spot_fleet[0].arn : null
    bid_percentage      = var.use_spot_instances ? var.spot_bid_percentage : null

    launch_template {
      launch_template_id = aws_launch_template.batch.id
      version            = "$Latest"
    }

    tags = local.common_tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# AWS Batch Job Queues
# =============================================================================

# -----------------------------------------------------------------------------
# Head Job Queue
# Used for Nextflow head job (workflow orchestration)
# -----------------------------------------------------------------------------
resource "aws_batch_job_queue" "head" {
  name     = local.head_queue_name
  state    = "ENABLED"
  priority = 1
  tags     = local.common_tags

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.head.arn
  }
}

# -----------------------------------------------------------------------------
# Compute Job Queue
# Used for Nextflow workflow tasks
# -----------------------------------------------------------------------------
resource "aws_batch_job_queue" "compute" {
  name     = local.compute_queue_name
  state    = "ENABLED"
  priority = 1
  tags     = local.common_tags

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.compute.arn
  }
}

# =============================================================================
# Seqera Platform Integration
# =============================================================================

# -----------------------------------------------------------------------------
# AWS Credentials in Seqera Platform
# Creates programmatic credentials for AWS access
# -----------------------------------------------------------------------------
resource "seqera_aws_credential" "aws_keys" {
  name         = local.seqera_credentials_name
  workspace_id = var.seqera_workspace_id
  access_key   = aws_iam_access_key.seqera.id
  secret_key   = aws_iam_access_key.seqera.secret
}

# IAM User for Seqera Platform credentials
# Note: Seqera Platform requires AWS access keys for credentials.
# The secret key will be stored in Terraform state - ensure state is encrypted.
# For enhanced security, consider using Seqera's IAM role assumption feature:
# https://docs.seqera.io/platform-enterprise/23.3/enterprise/advanced-topics/use-iam-role
resource "aws_iam_user" "seqera" {
  name = "${var.name}-seqera-user"
  tags = local.common_tags
}

resource "aws_iam_access_key" "seqera" {
  user = aws_iam_user.seqera.name
}

# Attach necessary policies to Seqera user
resource "aws_iam_user_policy_attachment" "seqera_batch_job" {
  user       = aws_iam_user.seqera.name
  policy_arn = aws_iam_policy.batch_job.arn
}

resource "aws_iam_user_policy_attachment" "seqera_head_job" {
  user       = aws_iam_user.seqera.name
  policy_arn = aws_iam_policy.head_job.arn
}

resource "aws_iam_user_policy_attachment" "seqera_pass_role" {
  user       = aws_iam_user.seqera.name
  policy_arn = aws_iam_policy.seqera_pass_role.arn
}

# -----------------------------------------------------------------------------
# Compute Environment in Seqera Platform
# Registers the manually-created AWS Batch resources with Seqera
# Note: No forge block = manual mode
# -----------------------------------------------------------------------------
resource "seqera_aws_batch_ce" "batch" {
  name           = local.seqera_compute_env_name
  platform       = "aws-batch"
  workspace_id   = var.seqera_workspace_id
  credentials_id = seqera_aws_credential.aws_keys.credentials_id
  description    = var.seqera_compute_env_description

  config = {
    # Required configuration
    region   = data.aws_region.current.name
    work_dir = local.work_dir

    # Manual mode: specify pre-created queues (no forge block)
    head_queue    = aws_batch_job_queue.head.name
    compute_queue = aws_batch_job_queue.compute.name

    # IAM roles
    execution_role   = aws_iam_role.batch_execution.arn
    head_job_role    = aws_iam_role.head_job.arn
    compute_job_role = aws_iam_role.compute_job.arn

    # Head job resources (optional - use Platform defaults if null)
    head_job_cpus      = var.head_job_cpus
    head_job_memory_mb = var.head_job_memory_mb

    # Optional features
    enable_wave          = var.enable_wave
    enable_fusion        = var.enable_fusion
    nvme_storage_enabled = var.enable_fusion
    fusion_snapshots     = var.enable_fusion

    # Scripts and configuration
    pre_run_script  = var.pre_run_script
    post_run_script = var.post_run_script
    nextflow_config = var.nextflow_config
  }

  depends_on = [
    aws_batch_job_queue.head,
    aws_batch_job_queue.compute,
  ]
}
