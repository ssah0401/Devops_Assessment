output "instance_ids" { value = module.ec2.instance_ids }
output "private_ips" { value = module.ec2.private_ips }
output "role_arns" {
  value = { roleA = aws_iam_role.roleA.arn, roleB = aws_iam_role.roleB.arn, roleC = aws_iam_role.roleC.arn }
}
output "encrypted_console_passwords" {
  sensitive = true
  value     = { for name, login in aws_iam_user_login_profile.console : name => login.encrypted_password }
}
output "encrypted_cli_credentials" {
  sensitive = true
  value     = { for name, key in aws_iam_access_key.programmatic : name => { access_key_id = key.id, encrypted_secret = key.encrypted_secret } }
}
