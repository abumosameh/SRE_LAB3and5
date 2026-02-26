output "load_balancer_dns" {
  description = "The DNS name of the application load balancer. Use this URL to access your web application."
  value       = aws_lb.lab_alb.dns_name
}

output "redis_endpoint" {
  description = "The endpoint URL for your ElastiCache Redis cluster."
  value       = aws_elasticache_cluster.redis_cache.cache_nodes[0].address
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.lab_database.name
}
