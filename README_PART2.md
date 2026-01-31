# Infrastructure as Code Lab - Part 2

## 1. Tool Selection (Part 1)

I have chosen **Terraform** for this lab.
**Reasoning:** Terraform's modularity and ability to use `locals` for data manipulation make it excellent for demonstrating the "Layered Configuration" approach.

## 2. Infrastructure Description

This repository deploys a scalable web infrastructure:

* **VPC:** Custom VPC with 2 Public Subnets (for High Availability) and Private subnets.
* **Load Balancer (ALB):** Public-facing ALB that distributes traffic to the Auto Scaling Group.
* **Auto Scaling Group (ASG):** Manages EC2 instances (Min: 2) running Apache.
* **Security:**
  * **ALB SG:** Allows HTTP (80) from everywhere.
  * **Web SG:** Allows HTTP only from the ALB SG.
* **Secrets:** SSM Parameter Store for DB credentials.

## 3. Configuration Management Strategy

We use a **Layered Configuration** approach:

1. **`config/default.json`**: Baseline settings (VPC CIDR, Instance Type, ASG Capacity).
2. **`config/development.json`**: Overrides (Dev tags).
3. **`main.tf`**: Merges these files dynamically.

## 4. Part 2: Graceful Operational Handling

### Health Check Endpoint

We implemented a custom `/health` endpoint.

* **Implementation:** The User Data script verifies it can connect to SSM to retrieve the database password.
* **Logic:**
  * If successful, it creates `/var/www/html/health` with content `{"status": "healthy"}`.
  * The ALB checks this file. If it exists and returns 200 OK, the instance is healthy.
  * If the file is missing (secret retrieval failed), the ALB marks the instance unhealthy and replaces it.

### Graceful Shutdown Process

We implemented **Auto Scaling Lifecycle Hooks** to handle termination gracefully.

1. **Trigger:** When the ASG decides to terminate an instance (scale-in), it triggers the `autoscaling:EC2_INSTANCE_TERMINATING` hook.
2. **Wait State:** The instance enters a `Terminating:Wait` state. It stays here until the timeout expires or a success signal is sent.
3. **Shutdown Script:** A script (`/usr/local/bin/graceful_shutdown.sh`) is provisioned on the instance.
   * **Drain:** It sleeps for 10 seconds to allow existing requests to finish (Connection Draining).
   * **Signal:** It uses the AWS CLI to send the `complete-lifecycle-action` signal to the ASG.
4. **Termination:** Once the signal is received, the ASG proceeds to actual termination.

## How to Deploy

1. **Init & Plan:**
   ```bash
   terraform init
   terraform plan -var="environment=development" ```

2. **Apply:** 

```bash 
   terraform apply -var="environment=development"
``` 


3. **Verify:** 

   * Go to the EC2 Console > Load Balancers and find the DNS Name of your new ALB.
   * Access http://<ALB-DNS-Name> to see the app.
   * Access http://<ALB-DNS-Name>/health to see the JSON health status. 

Thanks, -Anas 
