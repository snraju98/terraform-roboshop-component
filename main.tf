resource "aws_instance" "main" {
  ami           = local.ami_id
  instance_type = "t3.micro"
  vpc_security_group_ids = [local.sg_id]
  subnet_id = local.private_subnet_id
  
  tags = merge(
    {
        Name = "${local.common_name}" # roboshop-dev-catalogue
    },
    local.common_tags
  )
}

resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    password = "DevOps321"
    host        = aws_instance.main.private_ip
  }

  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} ${var.environment} ${var.app_version}"
    ]
  }
}

resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on = [terraform_data.main]
}

resource "aws_ami_from_instance" "main" {
  name               = "${local.common_name}-${var.app_version}-${aws_instance.main.id}" # roboshop-dev-catalogue-v3-instance-id
  source_instance_id = aws_instance.main.id
  depends_on = [aws_ec2_instance_state.main]
  tags = merge(
    {
        Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
    },
    local.common_tags
  )
}

resource "aws_launch_template" "main" {
  name = "${local.common_name}"

  image_id = aws_ami_from_instance.main.id # AMI ID

  instance_initiated_shutdown_behavior = "terminate"
  instance_type = "t3.micro"
  vpc_security_group_ids = [local.sg_id]
  update_default_version = true 

  # Oncce the instances are created, these will become instance tags
  tag_specifications {
    resource_type = "instance"

    tags = merge(
      {
          Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
      },
      local.common_tags
    )
  }

  # Oncce the instances are created, these will become volume tags
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      {
          Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
      },
      local.common_tags
    )
  }

  # Launch template resource tags
  tags = merge(
      {
          Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
      },
      local.common_tags
  )
}

resource "aws_lb_target_group" "main" {
  name     = "${local.common_name}"
  port     = var.component == "frontend" ? "80" : "8080"
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  deregistration_delay = 30

  health_check {
    healthy_threshold = 2
    interval = 10
    matcher = "200-299"
    path = var.component == "frontend" ? "/" : "/health"
    port = var.component == "frontend" ? "80" : "8080"
    protocol = "HTTP"
    timeout = 5
    unhealthy_threshold = 2
  }
}


resource "aws_autoscaling_group" "main" {
  name                      = "${local.common_name}"
  max_size                  = 10
  min_size                  = 1
  health_check_grace_period = 120
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = false

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  vpc_zone_identifier       = [local.private_subnet_id]

  target_group_arns = [aws_lb_target_group.main.arn] # Autoscaling launches into specific target group

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  dynamic "tag" {
    for_each = merge(
      {
        Name = "${local.common_name}"
      },
      local.common_tags
    )
    content{
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  # with in 15min autoscaling should be successful to launch instances
  timeouts {
    delete = "15m"
  }
}

resource "aws_autoscaling_policy" "main" {
  autoscaling_group_name = aws_autoscaling_group.main.name
  name                   = "${local.common_name}"
  policy_type            = "TargetTrackingScaling"
  estimated_instance_warmup = 120
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0
  }
}

resource "aws_lb_listener_rule" "main" {
  listener_arn = local.alb_listener_arn
  priority     = var.rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = [local.host_header]
    }
  }
}

/* resource "terraform_data" "catalogue_delete" {
  triggers_replace = [
    aws_instance.catalogue.id
  ]
  depends_on = [aws_autoscaling_policy.catalogue]

  # executes where terraform is running
  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.catalogue.id}"
  }
} */