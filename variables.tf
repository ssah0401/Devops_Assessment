variable "region" {
  type    = string
  default = "us-east-1"
}
variable "account_a_id" {
  type    = string
  default = "000000000000"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_a_id))
    error_message = "Account A must be a 12-digit AWS account ID."
  }
}
variable "account_b_id" {
  type    = string
  default = "111111111111"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_b_id))
    error_message = "Account B must be a 12-digit AWS account ID."
  }
}
variable "account_a_profile" {
  type    = string
  default = "account-a"
}
variable "account_b_profile" {
  type    = string
  default = "account-b"
}
variable "credential_pgp_keys" {
  description = "Base64-encoded public PGP keys (or keybase:user) for all four users. Never private keys."
  type        = map(string)
  validation {
    condition     = toset(keys(var.credential_pgp_keys)) == toset(["engine", "ci", "alice", "bob"]) && alltrue([for k in values(var.credential_pgp_keys) : length(trimspace(k)) > 0])
    error_message = "Supply public PGP keys for exactly engine, ci, alice and bob."
  }
}
variable "instances" {
  description = "Five distinct configurations. critical-db is the protected instance. Supply five distinct SSH public keys."
  type = map(object({
    instance_type = string
    key_name      = string
    public_key    = string
    environment   = string
    owner         = string
    root_volume = object({
      type = string
      size = number
      iops = optional(number)
    })
  }))
}
