# --- Secret Management ---
resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/${local.config.app_name}/database/password"
  description = "The database password for the web app"
  type        = "SecureString"
  value       = var.db_password
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

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  # UPDATED USER DATA: robust variable injection using db_config.php
  user_data = base64encode(<<-EOF
              #!/bin/bash

              # 1. Install Dependencies (Stable PHP 7.4)
              yum update -y
              amazon-linux-extras enable php7.4
              yum clean metadata
              yum install -y httpd php php-cli php-mysqlnd jq

              systemctl start httpd
              systemctl enable httpd

              # 2. Write Database Configuration File
              # We use a standard heredoc (CONFIG) so we can inject Terraform variables.
              # We escape the $ signs for PHP variables (\$host) so Bash doesn't try to expand them.
              cat <<CONFIG > /var/www/html/db_config.php
              <?php
              \$db_host = "${aws_db_instance.default.address}";
              \$db_user = "${var.db_username}";
              \$db_pass = "${var.db_password}";
              \$db_name = "lab_app";
              ?>
              CONFIG

              # 3. Create Application File (index.php)
              # We use a QUOTED heredoc ('PHP') so Bash ignores everything inside.
              # This protects the PHP logic variables like $conn, $result, etc.
              cat << 'PHP' > /var/www/html/index.php
              <?php
              // Enable Error Reporting
              ini_set('display_errors', 1);
              ini_set('display_startup_errors', 1);
              error_reporting(E_ALL);

              // Import the configuration we just wrote
              require 'db_config.php';

              // Retry Logic
              $max_retries = 5;
              $attempt = 0;
              $conn = null;

              while ($attempt < $max_retries) {
                  // Suppress warnings with @ to handle connection errors manually
                  $conn = @new mysqli($db_host, $db_user, $db_pass);
                  if ($conn->connect_error) {
                      $attempt++;
                      sleep(2);
                      continue;
                  }
                  break;
              }

              if (!$conn || $conn->connect_error) {
                  http_response_code(503);
                  echo "<h1>Service Unavailable</h1>";
                  echo "<p>Database connection failed: " . ($conn ? $conn->connect_error : "Unknown error") . "</p>";
                  echo "<p>Host: $db_host | User: $db_user</p>";
                  exit();
              }

              // Database Setup
              $conn->query("CREATE DATABASE IF NOT EXISTS $db_name");
              $conn->select_db($db_name);

              $sql = "CREATE TABLE IF NOT EXISTS feature_toggles (
                  id INT(6) UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                  feature_name VARCHAR(30) NOT NULL UNIQUE,
                  is_enabled BOOLEAN DEFAULT FALSE
              )";
              $conn->query($sql);

              $conn->query("INSERT IGNORE INTO feature_toggles (feature_name, is_enabled) VALUES ('dark_mode', 1)");

              $result = $conn->query("SELECT is_enabled FROM feature_toggles WHERE feature_name = 'dark_mode'");
              $row = $result->fetch_assoc();
              $darkMode = $row['is_enabled'];

              $bg_color = $darkMode ? "#333" : "#fff";
              $text_color = $darkMode ? "#fff" : "#000";
              ?>

              <!DOCTYPE html>
              <html>
              <head>
                  <style>
                      body { background-color: <?php echo $bg_color; ?>; color: <?php echo $text_color; ?>; font-family: sans-serif; padding: 2rem; }
                      .card { border: 1px solid #ccc; padding: 20px; border-radius: 8px; }
                  </style>
              </head>
              <body>
                  <h1>Lab App Part 3: Database Connected</h1>
                  <div class="card">
                      <h3>Database Status</h3>
                      <p><strong>Connection:</strong> Success (Primary)</p>
                      <p><strong>Host:</strong> <?php echo $db_host; ?></p>
                  </div>

                  <div class="card" style="margin-top: 20px;">
                      <h3>Feature Toggle Demo</h3>
                      <p>Feature: <strong>Dark Mode</strong></p>
                      <p>Status: <strong><?php echo $darkMode ? "Enabled" : "Disabled"; ?></strong></p>
                  </div>
              </body>
              </html>
              PHP

              # 4. Create Health Check
              echo '{"status": "healthy"}' > /var/www/html/health

              # 5. Graceful Shutdown Script
              cat << 'SCRIPT' > /usr/local/bin/graceful_shutdown.sh
              #!/bin/bash
              echo "Graceful shutdown triggered..." >> /var/log/shutdown.log
              sleep 10
              INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
              ASG_NAME=$(aws autoscaling describe-auto-scaling-instances --instance-ids $INSTANCE_ID --region ${var.region} --query 'AutoScalingInstances[0].AutoScalingGroupName' --output text)
              aws autoscaling complete-lifecycle-action \
                --lifecycle-hook-name ${local.config.app_name}-termination-hook \
                --auto-scaling-group-name $ASG_NAME \
                --lifecycle-action-result CONTINUE \
                --instance-id $INSTANCE_ID \
                --region ${var.region}
              SCRIPT
              chmod +x /usr/local/bin/graceful_shutdown.sh
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
  name                = "${local.config.app_name}-asg"
  vpc_zone_identifier = [aws_subnet.public.id, aws_subnet.public_2.id]
  target_group_arns   = [aws_lb_target_group.app_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  min_size         = local.config.asg_min_size
  max_size         = local.config.asg_max_size
  desired_capacity = local.config.asg_desired_capacity
  launch_template {
    id      = aws_launch_template.web_server.id
    version = "$Latest"
  }
  tag {
    key = "Name"
    value = "${local.config.app_name}-asg-instance"
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