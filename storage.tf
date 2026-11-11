resource "aws_s3_bucket" "rolec" {
  provider      = aws.account_b
  bucket        = "devops-rolec-data-${var.account_b_id}"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "rolec" {
  provider                = aws.account_b
  bucket                  = aws_s3_bucket.rolec.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "rolec" {
  provider = aws.account_b
  bucket   = aws_s3_bucket.rolec.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_ownership_controls" "rolec" {
  provider = aws.account_b
  bucket   = aws_s3_bucket.rolec.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
