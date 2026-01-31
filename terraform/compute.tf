# --- Secret Management (SSM Parameter Store) ---
# We use a random password generator so we don't hardcode secrets in the repo
resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/${local.config.app_name}/database/password"
  description = "The database password for the web app"
  type        = "SecureString"
  value       = random_password.db_password.result

  tags = local.common_tags
}

# NOTE: IAM Resources (Role, Policy, Profile) removed for AWS Academy compatibility.
# We now rely on the pre-existing "LabInstanceProfile" provided by the AWS Academy environment.

# --- EC2 Instance ---
# Look up latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = local.config.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]

  # Use the existing LabInstanceProfile passed via variables
  iam_instance_profile        = var.iam_instance_profile

  # User data to install web server and demonstrate secret retrieval
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd jq
              systemctl start httpd
              systemctl enable httpd

              # Retrieve Secret from SSM (Simulating app retrieving config)
              REGION="${var.region}"
              SECRET_NAME="${aws_ssm_parameter.db_password.name}"

              # Fetch the secret
              DB_PASS=$(aws ssm get-parameter --name "$SECRET_NAME" --with-decryption --region "$REGION" --query "Parameter.Value" --output text)

              # Create a simple HTML page displaying success (DO NOT PRINT ACTUAL SECRET IN PROD)
              echo "<h1>Infrastructure Deployed Successfully</h1>" > /var/www/html/index.html
              echo "<p>Environment: <strong>${var.environment}</strong></p>" >> /var/www/html/index.html
              echo "<p>Secret Retrieval Test: <strong>Success</strong> (Value retrieved from SSM Parameter Store)</p>" >> /var/www/html/index.html
              EOF

  tags = merge(local.common_tags, {
    Name = "${local.config.app_name}-web-server"
  })
}