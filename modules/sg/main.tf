resource "aws_security_group" "alb" {
  name   = "alb-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  alb_only = [aws_security_group.alb.id]
}

resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 8000
    to_port         = 8000
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

resource "aws_security_group" "jenkins_srv" {
  name   = "jenkins-srv-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = local.alb_only
  }
  ingress {
    from_port = 50000
    to_port   = 50000
    protocol  = "tcp"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "jenkins_agt" {
  name   = "jenkins-agt-sg"
  vpc_id = var.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "jnlp_from_agent" {
  type                     = "ingress"
  from_port                = 50000
  to_port                  = 50000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.jenkins_agt.id
  security_group_id        = aws_security_group.jenkins_srv.id
}

resource "aws_security_group" "gitlab" {
  name   = "gitlab-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 8080
    to_port         = 8080
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

resource "aws_security_group" "nat" {
  name   = "nat-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.allowed_nat_ingress_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "sg_alb" {
  value = aws_security_group.alb.id
}

output "sg_app" {
  value = aws_security_group.app.id
}

output "sg_jenkins_srv" {
  value = aws_security_group.jenkins_srv.id
}

output "sg_jenkins_agt" {
  value = aws_security_group.jenkins_agt.id
}

output "sg_gitlab" {
  value = aws_security_group.gitlab.id
}

output "sg_prom" {
  value = aws_security_group.prom.id
}

output "sg_nat" {
  value = aws_security_group.nat.id
}
