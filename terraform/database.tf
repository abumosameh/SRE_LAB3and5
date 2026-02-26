# ------------------------------------------------------------------------------
# DATABASE TIER (DynamoDB)
# ------------------------------------------------------------------------------
resource "aws_dynamodb_table" "lab_database" {
  name           = "Lab5-Products"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "Lab5-DynamoDB-Table"
  }
}

# ------------------------------------------------------------------------------
# CACHING TIER (ElastiCache Redis)
# ------------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "lab5-redis-subnet-group"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_elasticache_cluster" "redis_cache" {
  cluster_id           = "lab5-redis-cluster"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  security_group_ids   = [aws_security_group.redis_sg.id]
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name

  tags = {
    Name = "Lab5-Redis-Cache"
  }
}
