# =============================================================================
# IAM Resources for AWS Batch with Seqera Platform
#
# This file creates all IAM roles and policies required for manual AWS Batch
# setup as documented at:
# https://docs.seqera.io/platform-enterprise/24.2/enterprise/advanced-topics/manual-aws-batch-setup
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# IAM Policies
# =============================================================================

# -----------------------------------------------------------------------------
# Batch Job Policy
# Permissions for compute jobs: S3 access and CloudWatch logs
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "batch_job" {
  name        = "${var.name}-batch-job-policy"
  description = "Policy for Nextflow compute jobs - S3 and CloudWatch access"
  tags        = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 bucket-level permissions
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketLocation"
        ]
        Resource = local.all_bucket_arns
      },
      # S3 object-level permissions
      {
        Sid    = "S3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:GetObjectAttributes",
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [for arn in local.all_bucket_arns : "${arn}/*"]
      },
      # CloudWatch Logs permissions
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/batch/job:*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Head Job Policy
# Extended permissions for head job: Batch API access for job submission
# Permissions based on Seqera Platform requirements for Nextflow orchestration
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "head_job" {
  name        = "${var.name}-head-job-policy"
  description = "Policy for Nextflow head job - Batch API and monitoring access"
  tags        = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # AWS Batch operations
      {
        Sid    = "BatchOperations"
        Effect = "Allow"
        Action = [
          "batch:DescribeJobQueues",
          "batch:DescribeComputeEnvironments",
          "batch:DescribeJobs",
          "batch:DescribeJobDefinitions",
          "batch:ListJobs",
          "batch:SubmitJob",
          "batch:CancelJob",
          "batch:TerminateJob",
          "batch:RegisterJobDefinition",
          "batch:TagResource"
        ]
        Resource = "*"
      },
      # ECS operations for task monitoring
      {
        Sid    = "ECSOperations"
        Effect = "Allow"
        Action = [
          "ecs:DescribeTasks",
          "ecs:DescribeContainerInstances"
        ]
        Resource = "*"
      },
      # EC2 operations for instance inspection
      {
        Sid    = "EC2Operations"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInstanceStatus",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      # CloudWatch Logs operations
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:PutRetentionPolicy"
        ]
        Resource = "*"
      },
      # Secrets Manager for pipeline secrets
      {
        Sid    = "SecretsManagerList"
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:tower-*"
      },
      # KMS for encrypted resources
      {
        Sid    = "KMSEncryption"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:CreateGrant",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      # IAM PassRole for execution and job roles
      {
        Sid    = "PassJobRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.batch_execution.arn,
          aws_iam_role.compute_job.arn
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Seqera User Policy
# Permissions for Seqera Platform user to pass job roles to Batch
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "seqera_pass_role" {
  name        = "${var.name}-seqera-pass-role-policy"
  description = "Policy for Seqera user to pass IAM roles to AWS Batch"
  tags        = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PassJobRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.head_job.arn,
          aws_iam_role.compute_job.arn,
          aws_iam_role.batch_execution.arn
        ]
      }
    ]
  })
}

# =============================================================================
# IAM Roles
# =============================================================================

# -----------------------------------------------------------------------------
# Batch Service Role
# Used by AWS Batch to launch and manage EC2 instances
# -----------------------------------------------------------------------------
resource "aws_iam_role" "batch_service" {
  name        = "${var.name}-batch-service-role"
  description = "Role for AWS Batch service to manage compute environments"
  tags        = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "batch.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "batch_service" {
  role       = aws_iam_role.batch_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# -----------------------------------------------------------------------------
# ECS Instance Role
# Used by EC2 instances in the compute environment
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_instance" {
  name        = "${var.name}-ecs-instance-role"
  description = "Role for EC2 instances in AWS Batch compute environment"
  tags        = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecs" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_cloudwatch" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_batch_job" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = aws_iam_policy.batch_job.arn
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Spot Fleet Role (conditional)
# Required only when using Spot instances
# -----------------------------------------------------------------------------
resource "aws_iam_role" "spot_fleet" {
  count       = var.use_spot_instances ? 1 : 0
  name        = "${var.name}-spot-fleet-role"
  description = "Role for EC2 Spot Fleet to request and manage Spot instances"
  tags        = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "spotfleet.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "spot_fleet" {
  count      = var.use_spot_instances ? 1 : 0
  role       = aws_iam_role.spot_fleet[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

# -----------------------------------------------------------------------------
# Batch Execution Role
# Used by ECS to pull container images and write logs
# -----------------------------------------------------------------------------
resource "aws_iam_role" "batch_execution" {
  name        = "${var.name}-batch-execution-role"
  description = "Role for ECS task execution - container image pull and logging"
  tags        = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "batch_execution" {
  role       = aws_iam_role.batch_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow pulling from ECR
resource "aws_iam_role_policy_attachment" "batch_execution_ecr" {
  role       = aws_iam_role.batch_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -----------------------------------------------------------------------------
# Head Job Role
# Role assumed by the Nextflow head job container
# -----------------------------------------------------------------------------
resource "aws_iam_role" "head_job" {
  name        = "${var.name}-head-job-role"
  description = "Role for Nextflow head job - orchestrates workflow execution"
  tags        = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "head_job_batch" {
  role       = aws_iam_role.head_job.name
  policy_arn = aws_iam_policy.batch_job.arn
}

resource "aws_iam_role_policy_attachment" "head_job_head" {
  role       = aws_iam_role.head_job.name
  policy_arn = aws_iam_policy.head_job.arn
}

resource "aws_iam_role_policy_attachment" "head_job_s3_readonly" {
  role       = aws_iam_role.head_job.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# -----------------------------------------------------------------------------
# Compute Job Role
# Role assumed by Nextflow compute task containers
# -----------------------------------------------------------------------------
resource "aws_iam_role" "compute_job" {
  name        = "${var.name}-compute-job-role"
  description = "Role for Nextflow compute jobs - executes workflow tasks"
  tags        = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "compute_job" {
  role       = aws_iam_role.compute_job.name
  policy_arn = aws_iam_policy.batch_job.arn
}
