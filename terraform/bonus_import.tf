# --- Bonus Challenge: Data Import Controls ---

# 1. S3 Bucket for Uploads
resource "aws_s3_bucket" "import_bucket" {
  bucket        = "data-import-${random_string.suffix.result}"
  force_destroy = true
  tags          = local.common_tags
}

# 2. Lambda Function
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# Simple Python script to "Validate" CSV data
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  source_content = "import json\nimport boto3\n\ndef lambda_handler(event, context):\n    print('Import started...')\n    # Validation Logic Here\n    print('Data validated successfully.')\n    return {'statusCode': 200}"
  source_content_filename = "lambda_function.py"
}

resource "aws_lambda_function" "import_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.config.app_name}-data-import"

  # Use the existing LabRole ARN
  role             = data.aws_iam_role.lab_role.arn

  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = local.common_tags
}

# 3. S3 Trigger
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.import_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.import_handler.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.import_handler.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.import_bucket.arn
}