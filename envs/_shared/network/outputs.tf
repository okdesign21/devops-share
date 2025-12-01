output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "nat_instance_id" {
  description = "NAT instance ID"
  value       = try(module.nat_instance.instance_id, null)
}

output "sg_nat_id" {
  value = try(aws_security_group.nat.id, null)
}

output "key_name" {
  value = try(local.effective_key_name, null)
}

output "ssm_instance_profile_name" {
  value = try(aws_iam_instance_profile.ssm.name, null)
}

output "private_subnet_cidrs" {
  value = try(local.private_cidrs, null)
}

output "nat_instance_public_ip" {
  value = module.nat_instance.public_ip
}

output "ssm_access_policy_arn" {
  description = "IAM policy ARN for 'Devs' group SSM access to all instances (automatically attached)"
  value       = aws_iam_policy.ssm_access.arn
}

output "devs_group_name" {
  description = "Devs group name (resolved by Terraform)"
  value       = data.aws_iam_group.devs.group_name
}

output "ssm_only_sg_id" {
  description = "Security group ID for SSM-only access"
  value       = aws_security_group.ssm_only.id
}

output "ubuntu_ami_id" {
  description = "Resolved Ubuntu 24.04 AMI ID"
  value       = data.aws_ssm_parameter.ubuntu_24.value
  sensitive   = true
}