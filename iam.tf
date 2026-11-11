locals {
  console_users = toset(["alice", "bob"])
  all_users     = toset(["engine", "ci", "alice", "bob"])
  ci_policy = replace(replace(file("${path.module}/policies/ci-policy.json"),
  "000000000000", var.account_a_id), "us-east-1", var.region)
}
resource "aws_iam_user" "users" {
  for_each = local.all_users
  name     = each.key
  tags     = { Environment = "assessment", Owner = "devops" }
}
resource "aws_iam_group" "group1" { name = "group1" }
resource "aws_iam_group" "group2" { name = "group2" }
resource "aws_iam_group_membership" "group1" {
  name  = "group1-members"
  group = aws_iam_group.group1.name
  users = [aws_iam_user.users["engine"].name, aws_iam_user.users["ci"].name]
}
resource "aws_iam_group_membership" "group2" {
  name  = "group2-members"
  group = aws_iam_group.group2.name
  users = [for name in local.console_users : aws_iam_user.users[name].name]
}
resource "aws_iam_user_login_profile" "console" {
  for_each                = local.console_users
  user                    = aws_iam_user.users[each.key].name
  pgp_key                 = var.credential_pgp_keys[each.key]
  password_length         = 24
  password_reset_required = true
}
resource "aws_iam_access_key" "programmatic" {
  for_each = local.all_users
  user     = aws_iam_user.users[each.key].name
  pgp_key  = var.credential_pgp_keys[each.key]
}
resource "aws_iam_group_policy" "console_password" {
  name  = "change-own-initial-password"
  group = aws_iam_group.group2.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "iam:ChangePassword", Resource = "arn:aws:iam::${var.account_a_id}:user/$${aws:username}" },
      { Effect = "Allow", Action = "iam:GetAccountPasswordPolicy", Resource = "*" }
    ]
  })
}
resource "aws_iam_role" "roleA" {
  name = "roleA"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = [for name in local.console_users : aws_iam_user.users[name].arn] } }]
  })
}
resource "aws_iam_role_policy" "roleA" {
  name = "administration-except-iam"
  role = aws_iam_role.roleA.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "AdminOutsideIAM", Effect = "Allow", NotAction = "iam:*", Resource = "*" },
      { Sid = "DenyIAM", Effect = "Deny", Action = "iam:*", Resource = "*" }
    ]
  })
}
resource "aws_iam_role" "roleB" {
  name = "roleB"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = [for name in ["engine", "alice", "bob"] : aws_iam_user.users[name].arn] } }]
  })
}
resource "aws_iam_role_policy" "roleB" {
  name = "assume-only-roleC"
  role = aws_iam_role.roleB.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.roleC.arn }]
  })
}
resource "aws_iam_group_policy" "console_roles" {
  name  = "assume-assigned-roles"
  group = aws_iam_group.group2.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = [aws_iam_role.roleA.arn, aws_iam_role.roleB.arn] }]
  })
}
resource "aws_iam_user_policy" "engine" {
  name = "assume-roleB"
  user = aws_iam_user.users["engine"].name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.roleB.arn }]
  })
}
resource "aws_iam_user_policy" "ci" {
  name   = "ci-pipeline-least-privilege"
  user   = aws_iam_user.users["ci"].name
  policy = local.ci_policy
}
# Task 5 corrected trust: role/roleB, never user/roleB or Account A root.
locals {
  rolec_trust = {
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = aws_iam_role.roleB.arn }
    }]
  }
}
resource "aws_iam_role" "roleC" {
  provider           = aws.account_b
  name               = "roleC"
  assume_role_policy = jsonencode(local.rolec_trust)
}
resource "aws_iam_role_policy" "roleC_s3" {
  provider = aws.account_b
  name     = "roleC-s3-access"
  role     = aws_iam_role.roleC.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:*"
      Resource = [aws_s3_bucket.rolec.arn, "${aws_s3_bucket.rolec.arn}/*"]
    }]
  })
}
