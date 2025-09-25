# General
project_name = "cicd-lab"
region       = "eu-central-1"

# VPC & subnets (parametrized)
vpc_cidr      = "10.0.0.0/16"
public_cidrs  = ["10.0.1.0/24", "10.0.3.0/24"]
private_cidrs = ["10.0.2.0/24", "10.0.4.0/24"]

# Key handling
# Leave empty to auto-generate an SSH keypair
key_name = ""

enable_prometheus = false

nat_instance_type       = "m7i-flex.large"
gitlab_type             = "m7i-flex.large"
jenkins_controller_type = "m7i-flex.large"
jenkins_agent_type      = "m7i-flex.large"
app_instance_type       = "m7i-flex.large"
# prometheus_instance_type = "m7i-flex.large"
