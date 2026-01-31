# --- Database Subnet Group ---
resource "aws_db_subnet_group" "default" {
  name       = "${local.config.app_name}-db-subnet-group"

  # Combining them guarantees we cover at least 2 AZs.
  subnet_ids = [aws_subnet.public.id, aws_subnet.private.id]

  tags = merge(local.common_tags, {
    Name = "${local.config.app_name}-db-subnet-group"
  })
}

# --- Database Security Group ---
resource "aws_security_group" "db_sg" {
  name        = "${local.config.app_name}-db-sg"
  description = "Allow MySQL access from Web Server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from Web SG"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# --- Primary RDS Instance (Multi-AZ) ---
resource "aws_db_instance" "default" {
  identifier           = "${local.config.app_name}-db-primary"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true

  # High Availability & Backup Settings
  multi_az                  = true
  backup_retention_period   = 7
  db_subnet_group_name      = aws_db_subnet_group.default.name
  vpc_security_group_ids    = [aws_security_group.db_sg.id]

  tags = merge(local.common_tags, {
    Name = "${local.config.app_name}-db-primary"
  })
}

# --- Read Replica ---
resource "aws_db_instance" "replica" {
  identifier             = "${local.config.app_name}-db-replica"
  instance_class         = "db.t3.micro"
  replicate_source_db    = aws_db_instance.default.identifier
  skip_final_snapshot    = true

  # Replica specific settings
  vpc_security_group_ids = [aws_security_group.db_sg.id]


  tags = merge(local.common_tags, {
    Name = "${local.config.app_name}-db-replica"
  })
}

# --- Store DB Host in SSM for App to Retrieve ---
resource "aws_ssm_parameter" "db_host" {
  name        = "/${local.config.app_name}/database/host"
  description = "Primary DB Hostname"
  type        = "String"
  value       = aws_db_instance.default.address
  tags        = local.common_tags
}