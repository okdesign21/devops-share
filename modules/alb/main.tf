locals {
  routes_by_name   = { for r in var.routes : r.name => r }
  route_names      = keys(local.routes_by_name)
  computed_default = coalesce(var.default_tg_name, try(local.route_names[0], null))

  # Normalize routes to always use headers list (support both header and headers)
  normalized_routes = {
    for k, v in local.routes_by_name : k => merge(v, {
      host_headers = v.headers != null ? v.headers : (v.header != null ? [v.header] : [])
    })
  }
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnets
  lifecycle { prevent_destroy = false }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  count             = local.computed_default != null ? 1 : 0

  default_action {
    # If HTTPS is enabled, redirect HTTP to HTTPS
    type = var.enable_https ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    target_group_arn = var.enable_https ? null : aws_lb_target_group.tgs[local.computed_default].arn
  }
}

resource "aws_lb_listener" "https" {
  count             = var.enable_https && local.computed_default != null ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tgs[local.computed_default].arn
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

# HTTP listener rules (only when not redirecting to HTTPS)
resource "aws_lb_listener_rule" "http_rules" {
  for_each     = local.computed_default != null && !var.enable_https ? local.normalized_routes : {}
  listener_arn = aws_lb_listener.http[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tgs[each.key].arn
  }

  condition {
    host_header {
      values = each.value.host_headers
    }
  }
}

# HTTPS listener rules  
resource "aws_lb_listener_rule" "https_rules" {
  for_each     = local.computed_default != null && var.enable_https ? local.normalized_routes : {}
  listener_arn = aws_lb_listener.https[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tgs[each.key].arn
  }

  condition {
    host_header {
      values = each.value.host_headers
    }
  }
}

resource "aws_lb_listener" "http_404" {
  count             = local.computed_default == null ? 1 : 0
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

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "tg_arns" {
  value = { for k, v in aws_lb_target_group.tgs : k => v.arn }
}
