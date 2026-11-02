resource "aws_security_group" "public_web" {
  count       = var.public_access_enabled ? 1 : 0
  name        = "${var.project_name}-public-web"
  description = "Temporary public entrypoint for PoC operator"
  vpc_id      = aws_vpc.poc.id
}

resource "aws_vpc_security_group_ingress_rule" "public_web_clients" {
  for_each          = var.public_access_enabled ? toset(var.public_web_cidrs) : toset([])
  security_group_id = aws_security_group.public_web[0].id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
  description       = "Temporary PoC web access"
}

resource "aws_vpc_security_group_egress_rule" "public_web_nodes" {
  count             = var.public_access_enabled ? 1 : 0
  security_group_id = aws_security_group.public_web[0].id
  ip_protocol       = "tcp"
  from_port         = 30080
  to_port           = 30080
  cidr_ipv4         = aws_vpc.poc.cidr_block
  description       = "Forward to poc-web NodePort"
}

resource "aws_lb" "public_web" {
  count                            = var.public_access_enabled ? 1 : 0
  name                             = "${var.project_name}-web"
  internal                         = false
  load_balancer_type               = "network"
  subnets                          = aws_subnet.public[*].id
  security_groups                  = [aws_security_group.public_web[0].id]
  enable_cross_zone_load_balancing = true
  tags                             = { Name = "${var.project_name}-web" }

}

resource "aws_lb_target_group" "public_web" {
  count              = var.public_access_enabled ? 1 : 0
  name               = "${var.project_name}-web"
  port               = 30080
  protocol           = "TCP"
  target_type        = "instance"
  vpc_id             = aws_vpc.poc.id
  preserve_client_ip = false
  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }
}

resource "aws_lb_listener" "public_web" {
  count             = var.public_access_enabled ? 1 : 0
  load_balancer_arn = aws_lb.public_web[0].arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_web[0].arn
  }
}

resource "aws_autoscaling_attachment" "public_web" {
  count                  = var.public_access_enabled ? 1 : 0
  autoscaling_group_name = aws_eks_node_group.poc.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.public_web[0].arn
}

resource "aws_vpc_security_group_ingress_rule" "public_web_node_port" {
  count                        = var.public_access_enabled ? 1 : 0
  security_group_id            = aws_eks_cluster.poc.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 30080
  to_port                      = 30080
  referenced_security_group_id = aws_security_group.public_web[0].id
  description                  = "NLB to poc-web NodePort"
}
