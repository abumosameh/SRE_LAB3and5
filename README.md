# Infrastructure as Code Lab - Complete 

## 1. Tool Selection

We have chosen **Terraform** for this lab.
**Reasoning:** Terraform's modularity and ability to use `locals` for data manipulation make it excellent for demonstrating the "Layered Configuration" approach. It allows us to manage complex dependencies (like VPC -> Security Groups -> RDS -> EC2) efficiently.

## 2. Infrastructure Description

This repository deploys a comprehensive, scalable web architecture:

* **VPC:** Custom VPC with 2 Public Subnets (spanning 2 AZs) and Private subnets.
* **Compute:** Auto Scaling Group (ASG) of EC2 instances running Apache/PHP.
* **Database:** Amazon RDS MySQL (Multi-AZ) with a Read Replica.
* **Load Balancing:** Application Load Balancer (ALB) distributing traffic.
* **Serverless:** AWS Lambda and S3 for data ingestion.
* **Observability:** CloudWatch Dashboard for monitoring.

## 3. Configuration Management Strategy

We use a **Layered Configuration** approach:

1. **`config/default.json`**: Baseline settings (VPC CIDR, Instance Type, ASG Capacity).
2. **`config/development.json`**: Overrides (Dev tags, specific sizing).
3. **`main.tf`**: Merges these files dynamically using `jsondecode`.

## 4. Part 2: Graceful Operational Handling

### Health Check Endpoint
* **Path:** `/health`
* **Logic:** The app checks connectivity to the database. If successful, it returns a JSON `{"status": "healthy"}`. The ALB uses this to determine if an instance is ready to receive traffic.

### Graceful Shutdown
We utilize **Auto Scaling Lifecycle Hooks**:
1. When an instance terminates, it enters a `Terminating:Wait` state.
2. A script (`graceful_shutdown.sh`) runs connection draining (simulated wait).
3. The script signals `CONTINUE` to the ASG to proceed with termination.

## 5. Part 3: Database & Resilience

### Database Architecture
* **Engine:** MySQL 8.0
* **High Availability:** Multi-AZ deployment (Primary in AZ1, Standby in AZ2).
* **Read Scalability:** A Read Replica is provisioned in a different AZ.
* **Backups:** Automated backups enabled with a 7-day retention period.

### Application Resilience
* **Retry Logic:** The PHP application includes a retry loop (5 attempts) when connecting to the database. This handles temporary connection drops during AZ failover events without crashing the app.

### Feature Toggles
* **Implementation:** A `feature_toggles` table in the database controls application behavior.
* **Demo:** The "Dark Mode" feature can be toggled instantly by updating the database record, demonstrating configuration changes without redeployment.

## 6. Bonus Challenges

### Audit Logging (CloudWatch)
* **Resource:** `aws_cloudwatch_dashboard`
* **Function:** A custom dashboard visualizes ASG CPU usage alongside RDS CPU usage, allowing correlation between web traffic and database load.

### Data Import Controls (S3 & Lambda)
* **Pipeline:** S3 Bucket -> Event Notification -> Lambda Function.
* **Function:** Uploading a `.csv` file to the import bucket triggers a Python Lambda function that validates the file format before (simulated) ingestion.

## How to Deploy

1. **Initialize:**
   ```bash
   terraform init

2. **Apply:** 

```bash 
   terraform apply -var="environment=development"
``` 


3. **Verify:** 

   * Web App: Visit the alb_dns_name output URL. You should see the PHP app with Database Status.
   * Dashboard: Go to CloudWatch > Dashboards to see the metrics.
   * Toggle: Connect to the DB and run UPDATE feature_toggles SET is_enabled=0 WHERE feature_name='dark_mode'; then refresh the app.

Thanks, -Anas 
