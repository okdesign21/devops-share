output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "nat_instance_id" {
  value = try(module.nat_instance.id, null)
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


