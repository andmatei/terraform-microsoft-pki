terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# SSM Document to initialize the hosts

resource "aws_ssm_document" "setup" {
  name          = "rdg-setup"
  document_type = "Automation"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "configure instance on launch"
    # TODO: Continue
  })
}

# IAM

resource "aws_iam_role" "rdg_host" {
  name = "rdg-host-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = {
      Effect = "Allow"
      Action = "sts:AssumeRole",
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
    }
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonSSMDirectoryServiceAccess",
  ]
}

resource "aws_iam_instance_profile" "rdg_host" {
  name = "rdg-host-profile"
  role = aws_iam_role.rdg_host.name
}

# TODO: Execution Resource IAM Role
# TODO: EventBridge IAM Role

# ALB

resource "aws_lb" "this" {
  load_balancer_type = "network"
  subnets            = var.public_subnets
}

resource "aws_lb_target_group" "rdp" {
  port     = 3389
  protocol = "TCP"
  vpc_id   = var.vpc_id

  deregistration_delay = 60

  stickiness {
    enabled = true
    type    = "source_ip"
  }
}

resource "aws_lb_target_group" "https" {
  port     = 443
  protocol = "TCP"
  vpc_id   = var.vpc_id

  deregistration_delay = 60

  stickiness {
    enabled = true
    type    = "source_ip"
  }
}

resource "aws_lb_target_group" "rdg" {
  port     = 3391
  protocol = "UDP"
  vpc_id   = var.vpc_id

  deregistration_delay = 60

  stickiness {
    enabled = true
    type    = "source_ip"
  }
}

resource "aws_lb_listener" "rdp" {
  load_balancer_arn = aws_lb.this.arn
  port              = 3389
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rdp.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

resource "aws_lb_listener" "rdg" {
  load_balancer_arn = aws_lb.this.arn
  port              = 3391
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rdg.arn
  }
}

resource "aws_launch_template" "this" {
  instance_type = var.instance_type
  image_id      = var.ami_id
  key_name      = var.key_pair

  iam_instance_profile {
    name = aws_iam_instance_profile.rdg_host.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 50
      volume_type = "gp2"
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "RDGW"
    }
  }
}

resource "aws_autoscaling_group" "this" {
  name                = "ag-rdgw"
  vpc_zone_identifier = var.public_subnets

  min_size              = var.rdg_hosts_count
  max_instance_lifetime = var.rdg_hosts_count
  desired_capacity      = var.rdg_hosts_count
  target_group_arns = [
    aws_lb_target_group.rdp,
    aws_lb_target_group.rdg,
    aws_lb_target_group.https,
  ]

  initial_lifecycle_hook {
    name                 = "DomainJoinHook"
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    default_result       = "ABANDON"
    heartbeat_timeout    = 1200
  }

  initial_lifecycle_hook {
    name                 = "DomainUnjoinHook"
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
    default_result       = "ABANDON"
    heartbeat_timeout    = 600
  }

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }
}

resource "aws_security_group" "this" {
  name        = "sg-rdgw"
  description = "Enable RDP access from the Internet"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "rdp" {
  security_group_id = aws_security_group.this.id
  ip_protocol       = "tcp"
  from_port         = 3389
  to_port           = 3389
  cidr_ipv4         = var.cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.this.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.cidr_block
}


resource "aws_vpc_security_group_ingress_rule" "rdg" {
  security_group_id = aws_security_group.this.id
  ip_protocol       = "udp"
  from_port         = 3391
  to_port           = 3391
  cidr_ipv4         = var.cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "rdg" {
  security_group_id = aws_security_group.this.id
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.cidr_block
}

