# --- Bonus Challenge: Audit Logging ---

# 1. S3 Bucket for Logs (Allowed)
resource "aws_s3_bucket" "audit_logs" {
  bucket        = "audit-logs-${random_string.suffix.result}"
  force_destroy = true
  tags          = local.common_tags
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}


# 2. CloudWatch Dashboard (Allowed)
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.config.app_name}-ops-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.web_asg.name]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "ASG CPU Utilization"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.default.identifier]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "Database CPU"
        }
      }
    ]
  })
}