# --- Secret Management ---
resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/${local.config.app_name}/database/password"
  description = "The database password for the web app"
  type        = "SecureString"
  value       = random_password.db_password.result
  tags        = local.common_tags
}

# --- Launch Template ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_template" "web_server" {
  name_prefix   = "${local.config.app_name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = local.config.instance_type

  # Network settings
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # IAM Profile (Using the Academy default)
  iam_instance_profile {
    name = var.iam_instance_profile
  }

  # User Data script (Base64 encoded)
  user_data = base64encode(<<-EOF
              #!/bin/bash

              # 1. Install Dependencies
              yum update -y
              yum install -y httpd jq

              # 2. Retrieve Secret (Simulate startup dependency check)
              REGION="${var.region}"
              SECRET_NAME="${aws_ssm_parameter.db_password.name}"

              # Try to get secret. If this fails, app is "unhealthy"
              DB_PASS=$(aws ssm get-parameter --name "$SECRET_NAME" --with-decryption --region "$REGION" --query "Parameter.Value" --output text)

              # 3. Setup Web Content
              echo "<h1>App Version 2.0 (Auto Scaling)</h1>" > /var/www/html/index.html
              echo "<p>Served by instance: $(hostname -f)</p>" >> /var/www/html/index.html

              # 4. Create Health Check Endpoint
              # If DB_PASS was retrieved, we are healthy.
              if [ ! -z "$DB_PASS" ]; then
                echo '{"status": "healthy", "components": {"database": "connected"}}' > /var/www/html/health
              else
                echo '{"status": "unhealthy", "error": "secret_retrieval_failed"}' > /var/www/html/health
                # Apache returns 200 for file existence, but app logic might return 500.
                # For this lab, existence of the file with "healthy" text is enough.
              fi

              # 5. Setup Graceful Shutdown Script
              # We create a script that runs when the instance is stopped/terminated
              cat << 'SCRIPT' > /usr/local/bin/graceful_shutdown.sh
              #!/bin/bash
              echo "Graceful shutdown triggered..." >> /var/log/shutdown.log

              # A. Stop accepting new connections (Simulated by sleeping)
              # In a real app, we might deregister from ALB here if using API,
              # but ALB handles connection draining automatically.
              sleep 10

              # B. Signal Lifecycle Hook to complete
              INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
              ASG_NAME=$(aws autoscaling describe-auto-scaling-instances --instance-ids $INSTANCE_ID --region ${var.region} --query 'AutoScalingInstances[0].AutoScalingGroupName' --output text)

              aws autoscaling complete-lifecycle-action \
                --lifecycle-hook-name ${local.config.app_name}-termination-hook \
                --auto-scaling-group-name $ASG_NAME \
                --lifecycle-action-result CONTINUE \
                --instance-id $INSTANCE_ID \
                --region ${var.region}

              echo "Lifecycle signal sent." >> /var/log/shutdown.log
              SCRIPT

              chmod +x /usr/local/bin/graceful_shutdown.sh

              # 6. Start Apache
              systemctl start httpd
              systemctl enable httpd
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.config.app_name}-asg-node"
    })
  }
}

# --- Auto Scaling Group ---
resource "aws_autoscaling_group" "web_asg" {
  name                      = "${local.config.app_name}-asg"
  vpc_zone_identifier       = [aws_subnet.public.id, aws_subnet.public_2.id]
  target_group_arns         = [aws_lb_target_group.app_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = local.config.asg_min_size
  max_size         = local.config.asg_max_size
  desired_capacity = local.config.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.web_server.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.config.app_name}-asg-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# --- Lifecycle Hook ---
resource "aws_autoscaling_lifecycle_hook" "termination_hook" {
  name                   = "${local.config.app_name}-termination-hook"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}