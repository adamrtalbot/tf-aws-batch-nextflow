# =============================================================================
# Local Values
# Computed values and naming conventions used throughout the module
# =============================================================================

locals {
  # -------------------------------------------------------------------------
  # Naming Convention
  # All resources follow the pattern: {name}-{resource-type}
  # -------------------------------------------------------------------------
  head_ce_name       = "${var.name}-head-ce"
  compute_ce_name    = "${var.name}-compute-ce"
  head_queue_name    = "${var.name}-head-queue"
  compute_queue_name = "${var.name}-compute-queue"

  # -------------------------------------------------------------------------
  # S3 Configuration
  # -------------------------------------------------------------------------
  work_dir        = "s3://${var.work_bucket_name}/${var.work_dir_path}"
  work_bucket_arn = "arn:aws:s3:::${var.work_bucket_name}"

  # Combine work bucket with additional buckets for IAM policies
  all_bucket_arns = concat(
    [local.work_bucket_arn],
    var.additional_bucket_arns
  )

  # -------------------------------------------------------------------------
  # Seqera Platform Configuration
  # -------------------------------------------------------------------------
  seqera_credentials_name = coalesce(var.seqera_credentials_name, "${var.name}-aws-credentials")
  seqera_compute_env_name = coalesce(var.seqera_compute_env_name, var.name)

  # -------------------------------------------------------------------------
  # Allocation Strategy
  # Use appropriate strategy based on instance type (Spot vs On-Demand)
  # -------------------------------------------------------------------------
  compute_allocation_strategy = var.use_spot_instances ? (
    contains(["SPOT_CAPACITY_OPTIMIZED", "SPOT_PRICE_CAPACITY_OPTIMIZED"], var.allocation_strategy)
    ? var.allocation_strategy
    : "SPOT_CAPACITY_OPTIMIZED"
  ) : var.allocation_strategy

  # -------------------------------------------------------------------------
  # Launch Template User Data Scripts
  # Source: https://docs.seqera.io/platform-enterprise/24.2/enterprise/advanced-topics/manual-aws-batch-setup
  # -------------------------------------------------------------------------

  # User data for Fusion (includes NVMe formatting)
  # Based on Seqera Platform requirements for AWS Batch with Fusion
  user_data_fusion = <<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="//"

--//
Content-Type: text/cloud-config; charset="us-ascii"

#cloud-config
write_files:
  - path: /root/nextflow-ce.sh
    permissions: 0744
    owner: root
    content: |
      #!/usr/bin/env bash
      exec > >(tee /var/log/nextflow-ce.log|logger -t NextflowCE -s 2>/dev/console) 2>&1
      ##
      yum install -q -y jq sed wget unzip nvme-cli lvm2
      wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
      rpm -U ./amazon-cloudwatch-agent.rpm
      rm -f ./amazon-cloudwatch-agent.rpm
      curl -s https://nf-xpack.seqera.io/amazon-cloudwatch-agent/custom-v0.1.json \
        > /opt/aws/amazon-cloudwatch-agent/bin/config.json
      /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -s \
        -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
      mkdir -p /scratch/fusion
      NVME_DISKS=($(nvme list | grep 'Amazon EC2 NVMe Instance Storage' | awk '{ print $1 }'))
      NUM_DISKS=$${#NVME_DISKS[@]}
      if (( NUM_DISKS > 0 )); then
        if (( NUM_DISKS == 1 )); then
          mkfs -t xfs $${NVME_DISKS[0]}
          mount $${NVME_DISKS[0]} /scratch/fusion
        else
          pvcreate $${NVME_DISKS[@]}
          vgcreate scratch_fusion $${NVME_DISKS[@]}
          lvcreate -l 100%FREE -n volume scratch_fusion
          mkfs -t xfs /dev/mapper/scratch_fusion-volume
          mount /dev/mapper/scratch_fusion-volume /scratch/fusion
        fi
      fi
      chmod a+w /scratch/fusion
      ## ECS configuration
      mkdir -p /etc/ecs
      echo ECS_IMAGE_PULL_BEHAVIOR=once >> /etc/ecs/ecs.config
      echo ECS_ENABLE_AWSLOGS_EXECUTIONROLE_OVERRIDE=true >> /etc/ecs/ecs.config
      echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config
      echo ECS_CONTAINER_CREATE_TIMEOUT=10m >> /etc/ecs/ecs.config
      echo ECS_CONTAINER_START_TIMEOUT=10m >> /etc/ecs/ecs.config
      echo ECS_CONTAINER_STOP_TIMEOUT=10m >> /etc/ecs/ecs.config
      echo ECS_MANIFEST_PULL_TIMEOUT=10m >> /etc/ecs/ecs.config
      ## stop docker
      systemctl stop docker
      ## install AWS CLI
      curl -s https://nf-xpack.seqera.io/miniconda-awscli/miniconda-25.3.1-awscli-1.40.12.tar.gz \
        | tar xz -C /
      export PATH=$PATH:/home/ec2-user/miniconda/bin
      ln -s /home/ec2-user/miniconda/bin/aws /usr/bin/aws
      ## restart docker
      systemctl start docker
      systemctl enable --now --no-block ecs
      ## Tune kernel dirty pages parameters to avoid OOM errors
      echo "1258291200" > /proc/sys/vm/dirty_bytes
      echo "629145600" > /proc/sys/vm/dirty_background_bytes

runcmd:
  - bash /root/nextflow-ce.sh

--//--
EOF

  # User data for CLI only (no NVMe formatting)
  # Based on Seqera Platform requirements for AWS Batch without Fusion
  user_data_cli = <<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="//"

--//
Content-Type: text/cloud-config; charset="us-ascii"

#cloud-config
write_files:
  - path: /root/nextflow-ce.sh
    permissions: 0744
    owner: root
    content: |
      #!/usr/bin/env bash
      exec > >(tee /var/log/nextflow-ce.log|logger -t NextflowCE -s 2>/dev/console) 2>&1
      ##
      yum install -q -y jq sed wget unzip nvme-cli lvm2
      wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
      rpm -U ./amazon-cloudwatch-agent.rpm
      rm -f ./amazon-cloudwatch-agent.rpm
      curl -s https://nf-xpack.seqera.io/amazon-cloudwatch-agent/custom-v0.1.json \
        > /opt/aws/amazon-cloudwatch-agent/bin/config.json
      /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -s \
        -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
      ## ECS configuration
      mkdir -p /etc/ecs
      echo ECS_IMAGE_PULL_BEHAVIOR=once >> /etc/ecs/ecs.config
      echo ECS_ENABLE_AWSLOGS_EXECUTIONROLE_OVERRIDE=true >> /etc/ecs/ecs.config
      echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config
      echo ECS_CONTAINER_CREATE_TIMEOUT=10m >> /etc/ecs/ecs.config
      echo ECS_CONTAINER_START_TIMEOUT=10m >> /etc/ecs/ecs.config
      echo ECS_CONTAINER_STOP_TIMEOUT=10m >> /etc/ecs/ecs.config
      echo ECS_MANIFEST_PULL_TIMEOUT=10m >> /etc/ecs/ecs.config
      ## stop docker
      systemctl stop docker
      ## install AWS CLI v2
      curl -s https://nf-xpack.seqera.io/miniconda-awscli/miniconda-25.3.1-awscli-1.40.12.tar.gz \
        | tar xz -C /
      export PATH=$PATH:/home/ec2-user/miniconda/bin
      ln -s /home/ec2-user/miniconda/bin/aws /usr/bin/aws
      ## restart docker
      systemctl start docker
      systemctl enable --now --no-block ecs
      ## Tune kernel dirty pages parameters to avoid OOM errors
      echo "1258291200" > /proc/sys/vm/dirty_bytes
      echo "629145600" > /proc/sys/vm/dirty_background_bytes

runcmd:
  - bash /root/nextflow-ce.sh

--//--
EOF

  # -------------------------------------------------------------------------
  # Common Tags
  # Applied to all resources
  # -------------------------------------------------------------------------
  common_tags = merge(
    var.tags,
    {
      "ManagedBy" = "terraform"
      "Module"    = "tf-aws-batch-nextflow"
      "Name"      = var.name
    }
  )
}

# =============================================================================
# Validation Checks
# =============================================================================

check "fusion_requires_wave" {
  assert {
    condition     = !var.enable_fusion || var.enable_wave
    error_message = "enable_wave must be true when enable_fusion is true (Fusion relies on Wave)."
  }
}

check "head_vcpu_range" {
  assert {
    condition     = var.head_min_vcpus <= var.head_max_vcpus
    error_message = "head_min_vcpus (${var.head_min_vcpus}) cannot exceed head_max_vcpus (${var.head_max_vcpus})."
  }
}

check "compute_vcpu_range" {
  assert {
    condition     = var.compute_min_vcpus <= var.compute_max_vcpus
    error_message = "compute_min_vcpus (${var.compute_min_vcpus}) cannot exceed compute_max_vcpus (${var.compute_max_vcpus})."
  }
}
