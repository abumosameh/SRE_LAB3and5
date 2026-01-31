# Infrastructure as Code Lab - Part 1

## 1. Tool Selection and Comparison

**Comparison:**
* **AWS CloudFormation:** Native to AWS, uses JSON/YAML. It manages state automatically on the AWS backend. Deeply integrated but can be verbose and is strictly limited to AWS.
* **Terraform:** Open-source, uses HashiCorp Configuration Language (HCL). It manages state via a local or remote state file. It is cloud-agnostic (can manage AWS, Azure, Google, etc., simultaneously) and generally considered to have a more readable syntax.

**Selection:**
We have chosen **Terraform** for this lab.
**Reasoning:** Terraform's modularity and ability to use `locals` for data manipulation make it excellent for demonstrating the "Layered Configuration" approach requested. Its HCL syntax is also generally more approachable for defining complex dependencies than raw JSON/YAML.

## 2. Infrastructure Description
This repository deploys a web infrastructure consisting of:
* **VPC:** Custom Virtual Private Cloud with Public and Private subnets.
* **Compute:** An EC2 instance running an Apache web server.
* **Security:** Security Groups allowing HTTP (80) and SSH (22).
* **Secrets:** An AWS Systems Manager Parameter Store entry for database credentials.

## 3. Configuration Management Strategy
We implement a **Layered Configuration** approach to separate code from configuration.

1.  **`config/default.json`**: Contains the baseline settings (e.g., standard VPC CIDR, small instance type).
2.  **`config/development.json`**: Contains overrides specific to the dev environment (e.g., specific tags, slightly different instance sizing if needed).
3.  **Merging Logic**: Inside `main.tf`, Terraform reads the default file and optionally merges the development file on top of it based on the `environment` variable. This ensures DRY (Don't Repeat Yourself) principles—we only define overrides, not the whole config again.

## 4. Secret Management
We use **AWS Systems Manager (SSM) Parameter Store**.
* The Terraform code creates a secure string parameter named `/lab-app/database/password` (or `/lab-app-dev/...`).
* **AWS Academy Note:** The EC2 instance utilizes the pre-configured `LabInstanceProfile` to obtain necessary permissions (including `ssm:GetParameter`) instead of creating custom IAM roles, ensuring compatibility with learner lab restrictions.
* The EC2 User Data script demonstrates how to retrieve this secret programmatically without hardcoding it in the application.

## How to Deploy

1.  Initialize Terraform:
    ```bash
    terraform init
    ```

2.  Plan (View changes):
    ```bash
    terraform plan -var="environment=development"
    ```

3.  Apply (Deploy):
    ```bash
    terraform apply -var="environment=development"
    ```

4.  Verify:
    * Visit the Public IP of the created EC2 instance in your browser.
    * You should see a success message indicating the secret was retrieved.
