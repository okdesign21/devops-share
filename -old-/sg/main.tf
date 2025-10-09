
resource "aws_security_group" "prom" {
  name   = "prom-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = local.alb_only
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "sg_prom" {
  value = aws_security_group.prom.id
}
