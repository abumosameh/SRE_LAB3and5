output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.app_lb.dns_name
}

output "asg_name" {
  description = "The name of the Auto Scaling Group"
  value       = aws_autoscaling_group.web_asg.name
}

# --- Part 3 Outputs ---
output "db_primary_endpoint" {
  description = "Primary RDS Endpoint"
  value       = aws_db_instance.default.address
}

output "db_replica_endpoint" {
  description = "Read Replica RDS Endpoint"
  value       = aws_db_instance.replica.address
}

output "audit_bucket_name" {
  value = aws_s3_bucket.audit_logs.id
}