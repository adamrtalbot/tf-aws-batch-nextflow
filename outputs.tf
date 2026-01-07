# =============================================================================
# Outputs
# These values can be used by other modules or for reference
# =============================================================================

# -----------------------------------------------------------------------------
# AWS Batch Outputs
# -----------------------------------------------------------------------------

output "head_compute_environment_arn" {
  description = "ARN of the head job compute environment"
  value       = aws_batch_compute_environment.head.arn
}

output "head_compute_environment_name" {
  description = "Name of the head job compute environment"
  value       = aws_batch_compute_environment.head.compute_environment_name
}

output "compute_environment_arn" {
  description = "ARN of the compute job compute environment"
  value       = aws_batch_compute_environment.compute.arn
}

output "compute_environment_name" {
  description = "Name of the compute job compute environment"
  value       = aws_batch_compute_environment.compute.compute_environment_name
}

output "head_queue_arn" {
  description = "ARN of the head job queue"
  value       = aws_batch_job_queue.head.arn
}

output "head_queue_name" {
  description = "Name of the head job queue"
  value       = aws_batch_job_queue.head.name
}

output "compute_queue_arn" {
  description = "ARN of the compute job queue"
  value       = aws_batch_job_queue.compute.arn
}

output "compute_queue_name" {
  description = "Name of the compute job queue"
  value       = aws_batch_job_queue.compute.name
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------

output "batch_service_role_arn" {
  description = "ARN of the AWS Batch service role"
  value       = aws_iam_role.batch_service.arn
}

output "ecs_instance_role_arn" {
  description = "ARN of the ECS instance role"
  value       = aws_iam_role.ecs_instance.arn
}

output "ecs_instance_profile_arn" {
  description = "ARN of the ECS instance profile"
  value       = aws_iam_instance_profile.ecs_instance.arn
}

output "batch_execution_role_arn" {
  description = "ARN of the Batch execution role"
  value       = aws_iam_role.batch_execution.arn
}

output "head_job_role_arn" {
  description = "ARN of the head job role"
  value       = aws_iam_role.head_job.arn
}

output "compute_job_role_arn" {
  description = "ARN of the compute job role"
  value       = aws_iam_role.compute_job.arn
}

output "spot_fleet_role_arn" {
  description = "ARN of the Spot Fleet role (null if Spot not enabled)"
  value       = var.use_spot_instances ? aws_iam_role.spot_fleet[0].arn : null
}

# -----------------------------------------------------------------------------
# Seqera Platform Outputs
# -----------------------------------------------------------------------------

output "seqera_credentials_id" {
  description = "Seqera Platform credentials ID"
  value       = seqera_aws_credential.aws_keys.credentials_id
}

output "seqera_compute_env_id" {
  description = "Seqera Platform compute environment ID"
  value       = seqera_aws_batch_ce.batch.id
}

output "seqera_compute_env_status" {
  description = "Seqera Platform compute environment status"
  value       = seqera_aws_batch_ce.batch.status
}

# -----------------------------------------------------------------------------
# Configuration Outputs
# -----------------------------------------------------------------------------

output "work_dir" {
  description = "S3 work directory path configured for this compute environment"
  value       = local.work_dir
}

output "launch_template_id" {
  description = "ID of the EC2 launch template"
  value       = aws_launch_template.batch.id
}
