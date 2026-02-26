# ------------------------------------------------------------------------------
# SECURITY GROUPS
# ------------------------------------------------------------------------------
resource "aws_security_group" "alb_sg" {
  name        = "lab5-alb-sg"
  description = "Allow HTTP traffic from the internet"
  vpc_id      = aws_vpc.lab_vpc.id

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

resource "aws_security_group" "ec2_sg" {
  name        = "lab5-ec2-sg"
  description = "Allow HTTP from ALB and SSH"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis_sg" {
  name        = "lab5-redis-sg"
  description = "Allow Redis traffic from EC2"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------------------
# LOAD BALANCER
# ------------------------------------------------------------------------------
resource "aws_lb" "lab_alb" {
  name               = "lab5-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "lab_tg" {
  name     = "lab5-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.lab_vpc.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lab_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lab_tg.arn
  }
}

# ------------------------------------------------------------------------------
# LAUNCH TEMPLATE & AUTO SCALING GROUP (Bonus)
# ------------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_launch_template" "lab_lt" {
  name_prefix   = "lab5-app-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  # IAM Profile (AWS Academy uses LabInstanceProfile by default)
  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y python3 python3-pip httpd
              pip3 install flask redis boto3
              
              # Provide Redis endpoint and DynamoDB table name to application environment
              echo "export REDIS_HOST='${aws_elasticache_cluster.redis_cache.cache_nodes[0].address}'" >> /etc/profile
              echo "export DYNAMO_TABLE='${aws_dynamodb_table.lab_database.name}'" >> /etc/profile
              
              # A placeholder file letting you know it works
              echo "<h1>Lab 5 Application Server Running</h1><p>Ready for cache implementation.</p>" > /var/www/html/index.html
              
              systemctl start httpd
              systemctl enable httpd
              EOF
  )
}

resource "aws_autoscaling_group" "lab_asg" {
  name                = "lab5-asg"
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  target_group_arns   = [aws_lb_target_group.lab_tg.arn]
  
  desired_capacity = 2
  min_size         = 1
  max_size         = 4

  launch_template {
    id      = aws_launch_template.lab_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "Lab5-App-Instance"
    propagate_at_launch = true
  }
}

# ------------------------------------------------------------------------------
# CLOUDWATCH ALARMS & SCALING POLICIES (Bonus Part)
# ------------------------------------------------------------------------------
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "lab5-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.lab_asg.name
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "lab5-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "Triggers scale up when CPU is high (Lab 5 Bonus)"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.lab_asg.name
  }
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "lab5-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.lab_asg.name
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_alarm" {
  alarm_name          = "lab5-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "30"
  alarm_description   = "Triggers scale down when CPU is low (Lab 5 Bonus)"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.lab_asg.name
  }
}
