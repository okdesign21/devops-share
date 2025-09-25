resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnets
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_target_group" "tgs" {
  for_each = { for r in var.routes : r.name => r }
  name     = "${var.name}-${each.value.name}-tg"
  port     = each.value.port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path    = each.value.health_path
    matcher = "200-399"
  }
}

resource "aws_lb_listener_rule" "rules" {
  for_each     = aws_lb_target_group.tgs
  listener_arn = aws_lb_listener.http.arn
  priority     = 10 + index(keys(aws_lb_target_group.tgs), each.key)
  action {
    type             = "forward"
    target_group_arn = each.value.arn
  }
  condition {
    path_pattern {
      values = [var.routes[index(keys(aws_lb_target_group.tgs), each.key)].path]
    }
  }
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "tg_arns" {
  value = { for k, v in aws_lb_target_group.tgs : k => v.arn }
}
