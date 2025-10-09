# read AMI info so we can determine snapshot root size (if any)
data "aws_ami" "this" {
  id = var.ami_id
}

data "aws_subnet" "this" {
  id = var.subnet_id
}

locals {
  ami_root_device_type = try(data.aws_ami.this.root_device_type, "")
  ami_root_device_name = try(data.aws_ami.this.root_device_name, "/dev/sda1")
  ami_root_size = try(
    lookup({ for m in data.aws_ami.this.block_device_mappings : m.device_name => m }, local.ami_root_device_name).ebs.volume_size,
    try(data.aws_ami.this.block_device_mappings[0].ebs.volume_size, 0)
  )

  requested_root_size = var.root_volume_size_gb
  # For EBS-backed AMIs ensure not smaller than AMI snapshot size.
  effective_root_size = local.requested_root_size == 0 ? 0 : (local.ami_root_device_type == "ebs" ? max(local.requested_root_size, local.ami_root_size) : local.requested_root_size)
}

# Fail if instance-store AMI and user didn't request override (per your rule)
resource "null_resource" "fail_instance_store_no_override" {
  count = (local.ami_root_device_type != "ebs" && local.requested_root_size == 0) ? 1 : 0
  provisioner "local-exec" {
    command = "echo 'ERROR: AMI ${var.ami_id} is instance-store and no root override requested (refuse as configured)'; exit 1"
  }
}

# Fail if instance-store AMI + override but no snapshot provided
resource "null_resource" "fail_instance_store_no_snapshot" {
  count = (local.ami_root_device_type != "ebs" && local.requested_root_size > 0 && var.root_snapshot_id == "") ? 1 : 0
  provisioner "local-exec" {
    command = "echo 'ERROR: AMI ${var.ami_id} is instance-store; to create an EBS root you must supply root_snapshot_id'; exit 1"
  }
}

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.sg_ids
  associate_public_ip_address = var.associate_public_ip
  user_data                   = var.user_data
  user_data_replace_on_change = true
  source_dest_check           = var.enable_source_dest_check
  iam_instance_profile        = var.iam_instance_profile

  tags = merge(var.tags, { Name = var.name })

  # only set root_block_device for:
  # - EBS-backed AMI when effective_root_size > 0 (user requested override)
  # - instance-store AMI when user provided root_snapshot_id and requested_root_size > 0
  dynamic "root_block_device" {
    for_each = (
      (local.ami_root_device_type == "ebs" && local.effective_root_size > 0) ||
      (local.ami_root_device_type != "ebs" && local.requested_root_size > 0 && var.root_snapshot_id != "")
    ) ? [1] : []
    content {
      device_name           = local.ami_root_device_name
      volume_type           = var.root_volume_type
      delete_on_termination = true
      volume_size           = local.effective_root_size > 0 ? local.effective_root_size : local.requested_root_size
    }
  }
}

# Optional data volume (useful with instance-store AMI to get persistent storage)
resource "aws_ebs_volume" "data" {
  count             = var.create_data_volume ? 1 : 0
  availability_zone = data.aws_subnet.this.availability_zone
  size              = var.data_volume_size_gb
  type              = var.root_volume_type
  tags = {
    Name = "${var.name}-data"
  }
}

resource "aws_volume_attachment" "data_attach" {
  count       = var.create_data_volume ? 1 : 0
  device_name = var.data_device_name
  volume_id   = aws_ebs_volume.data[0].id
  instance_id = aws_instance.this.id
  force_detach = true
}
