# A reusable module: "a private, versioned S3 bucket plus an IAM user that can
# only touch that bucket". Call it once per app/environment.

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Least privilege: the app may only read/write objects in this one bucket.
data "aws_iam_policy_document" "access" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }
}

resource "aws_iam_user" "app" {
  name = "${var.name}-app"
  tags = var.tags
}

resource "aws_iam_user_policy" "app" {
  name   = "bucket-access"
  user   = aws_iam_user.app.name
  policy = data.aws_iam_policy_document.access.json
}

# On real AWS you'd prefer IRSA / EKS Pod Identity (no long-lived keys).
# Note: the secret ends up in Terraform state — state is sensitive!
resource "aws_iam_access_key" "app" {
  user = aws_iam_user.app.name
}
