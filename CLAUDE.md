# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform module for **manually** creating AWS Batch compute environments integrated with Seqera Platform (Nextflow Tower). This module does NOT use Batch Forge - all AWS resources are created explicitly via Terraform.

## Architecture

```
Seqera Platform
  └── Compute Environment (seqera_aws_batch_ce)
        └── References manually-created AWS resources:
              ├── Head Job Queue → Head Compute Environment (On-Demand)
              └── Compute Queue → Compute Environment (On-Demand or Spot)
```

Key design: The `seqera_aws_batch_ce` resource specifies `head_queue` and `compute_queue` WITHOUT a `forge` block, which tells Seqera to use pre-existing AWS Batch resources.

## Commands

```bash
terraform init      # Initialize providers and modules
terraform fmt       # Format code
terraform validate  # Validate configuration
terraform plan      # Preview changes
terraform apply     # Apply infrastructure changes
```

Required environment variables:
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"
export SEQERA_ACCESS_TOKEN="..."
```

## File Structure

| File | Purpose |
|------|---------|
| `versions.tf` | Terraform and provider version constraints (aws ~> 5.0, seqera >= 0.1) |
| `variables.tf` | Input variables with validation rules |
| `locals.tf` | Naming conventions and computed values |
| `iam.tf` | IAM roles and policies for Batch, ECS, head/compute jobs |
| `main.tf` | Launch template, Batch CEs, Job Queues, Seqera resources |
| `outputs.tf` | Exported ARNs, names, and IDs |

## Key Resources

### IAM (iam.tf)
- `aws_iam_policy.batch_job` - S3 + CloudWatch access for compute jobs
- `aws_iam_policy.head_job` - Extended policy with Batch API access
- `aws_iam_role.batch_service` - AWS Batch service role
- `aws_iam_role.ecs_instance` - EC2 instance role
- `aws_iam_role.batch_execution` - ECS task execution role
- `aws_iam_role.head_job` / `compute_job` - Container task roles

### AWS Batch (main.tf)
- `aws_launch_template.batch` - User data: CloudWatch, NVMe mounting, AWS CLI
- `aws_batch_compute_environment.head` - On-Demand CE for head jobs
- `aws_batch_compute_environment.compute` - On-Demand or Spot CE for tasks
- `aws_batch_job_queue.head` / `compute` - Job queues

### Seqera Platform (main.tf)
- `seqera_aws_credential.aws_keys` - AWS credentials (via IAM user)
- `seqera_aws_batch_ce.batch` - Compute environment (manual mode)

## Manual Mode Pattern

The key to manual setup is specifying queues without the `forge` block:

```hcl
resource "seqera_aws_batch_ce" "this" {
  config = {
    head_queue    = aws_batch_job_queue.head.name      # Manual mode
    compute_queue = aws_batch_job_queue.compute.name   # Manual mode
    # NO forge block = manual mode
  }
}
```

## Variable Defaults

- `head_max_vcpus`: 128
- `compute_max_vcpus`: 256
- `instance_types`: ["optimal"]
- `use_spot_instances`: false
- `enable_wave`: false
- `enable_fusion`: false

## Reference Documentation

- [Seqera Manual AWS Batch Setup](https://docs.seqera.io/platform-enterprise/24.2/enterprise/advanced-topics/manual-aws-batch-setup)
- [Seqera Terraform Provider](https://registry.terraform.io/providers/seqeralabs/seqera/latest/docs)
- [AWS Batch Terraform Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/batch_compute_environment)
