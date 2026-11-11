# DevOps assessment

Complete Terraform implementation of Tasks 1–5, with custom CI policy JSON, explanations, repeatable offline checks, and dependency lock files. See [NOTES.md](NOTES.md) for the direct assessment answers and design limits. See [VALIDATION.md](VALIDATION.md) for the recorded validation results.

## Contents

| Path | Purpose |
| --- | --- |
| `modules/ec2/` | Five instances and five key pairs driven by one map; protected `critical-db`; ID/IP outputs |
| `bootstrap/` | Versioned, encrypted, private S3 state bucket and DynamoDB lock table |
| `iam.tf` | Account A users/groups/roles; Account B roleC; corrected trust and bucket permissions |
| `policies/ci-policy.json` | Standalone least-privilege CI policy for the assignment's account IDs |
| `tests/`, `modules/ec2/tests/`, `bootstrap/tests/` | Terraform provider-mocked plan tests |
| `scripts/` | One-command validation, CI policy authorization cases, and deletion-guard check |

## Requirements

- Terraform **1.13.5** recommended; supported range **1.12.x–1.13.x**. The range intentionally retains the requested, deprecated DynamoDB backend locking support and supports plan-time test overrides.
- Python 3.9+ and Bash for the validation scripts. No third-party Python packages.
- Internet access for the initial AWS provider download. AWS credentials are unnecessary for offline validation.
- For deployment: AWS CLI profiles `account-a` and `account-b`, authorized in the respective accounts. The assignment's `000000000000` and `111111111111` are illustrative IDs; replace them with actual accounts before deployment.

## Validate without AWS deployment

From this directory:

```bash
./scripts/validate.sh
```

If the desired Terraform executable is not on PATH:

```bash
TERRAFORM=/absolute/path/to/terraform ./scripts/validate.sh
```

The script initializes with `-backend=false`, validates all three configurations, runs all mock plan tests, runs CI policy allow/deny cases, and proves that `prevent_destroy` rejects a mocked destruction. The deletion test expects exactly that rejection and treats it as success; its temporary mock state is removed. No test uses the real AWS provider for resource operations.

## Deployment

1. Configure the two authorized AWS CLI profiles and confirm the account identities. A real plan/apply incurs AWS charges. Account A needs EC2, VPC and IAM provisioning permissions; Account B needs IAM and bucket provisioning permissions. Backend provisioning also needs S3 and DynamoDB permissions in Account A.
2. Copy `terraform.tfvars.json.example` to `terraform.tfvars.json`. Replace **all five example SSH public keys** with your own distinct public keys; keep the matching private keys outside Terraform. The included example keys are public-only fixtures and have no usable private keys in this package. Replace every `credential_pgp_keys` value with its recipient's real public PGP key, base64-encoded, or a valid `keybase:username`. Each user's key encrypts their generated CLI secret; alice/bob's keys also encrypt their initial console passwords. Add `account_a_id`, `account_b_id`, and profile/region settings if overriding the defaults. No secret values belong in input files.
3. Bootstrap the backend **once**, before initializing the main stack. Use the same real Account A ID and region as the main stack:

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap plan -var='account_a_id=YOUR_ACCOUNT_A_ID' -out=bootstrap.tfplan
terraform -chdir=bootstrap apply bootstrap.tfplan
```

Keep `bootstrap/terraform.tfstate` secure and backed up; bootstrap intentionally uses local state to avoid a circular backend dependency. Use a separate, pre-existing administrative backend for bootstrap in a team setting. Do not concurrently bootstrap from different machines.

4. Copy `backend.hcl.example` to `backend.hcl`; set its bucket, region, profile, allowed Account A ID and lock table to the bootstrap output. These settings must match the deployed bootstrap. Initialize, review the real plan, then apply the reviewed plan:

```bash
terraform init -backend-config=backend.hcl
terraform plan -lock-timeout=5m -out=assessment.tfplan
terraform apply -lock-timeout=5m assessment.tfplan
terraform output instance_ids
terraform output private_ips
```

If migrating an already-applied local main stack, use `terraform init -migrate-state -backend-config=backend.hcl` instead, after backing up local state and coordinating a pause in all applies. Existing resources that were not created in this state must be imported; do not create duplicate users, roles, or buckets.

5. Deliver credentials only to their intended recipients. `terraform output -json encrypted_cli_credentials` returns IDs and base64 PGP-encrypted secrets. `terraform output -json encrypted_console_passwords` returns base64 PGP-encrypted initial passwords. Recipients base64-decode and decrypt with their own PGP private key. alice/bob must change their password at first login. Use the Account A sign-in URL for console access. Configure the decrypted CLI keys securely; never commit them. Even with encrypted outputs, restrict state and plan access.
6. The CI policy targets an **existing** ECR repository `assessment-app`, ECS cluster/service `assessment-cluster/assessment-service`, task-definition family `assessment-app`, runtime roles `assessment-ecs-execution` and `assessment-ecs-task`, and artifact bucket `devops-build-artifacts-<Account A ID>`, in the configured region. Task 4 is an IAM policy task: those application resources are prerequisites, not provisioned here. The file is the concrete policy for the supplied IDs/region; Terraform substitutes Account A ID and region when attaching it to `ci`.

The five EC2 instances are provisioned in a dedicated private subnet with no public IPs or security-group ingress/egress. SSH keys are installed, but interactive access requires explicitly designed private connectivity and security-group rules. No public SSH exposure is added by this assignment.

## Role use

- `engine`: CLI only; can assume roleB, then roleC.
- `ci`: CLI only; receives only the custom pipeline policy; cannot assume roleA or roleB.
- `alice`, `bob`: console and CLI; can assume roleA for non-IAM administration or roleB, then roleC, for the bucket workflow. Their base user policy only permits assigned role assumption and changing their own password.
- `roleB`: its sole identity permission is `sts:AssumeRole` on roleC. It has no direct S3 access.
- `roleC`: created using the Account B provider; trusts exactly roleB and grants S3 access only to `devops-rolec-data-<Account B ID>` and its objects.

Use `aws sts assume-role --role-arn <roleB-ARN> --role-session-name bucket-hop` with engine/alice/bob's CLI identity, then use the returned temporary credentials to assume roleC. CLI configuration supports chained `role_arn`/`source_profile` profiles; do not expect a direct console switch from Account A's original user to satisfy a trust policy that requires roleB.

## Teardown

A full destroy is deliberately blocked by `critical-db`'s lifecycle guard. Backend bucket/table deletion is also guarded, and DynamoDB has service-side deletion protection. For authorized teardown, back up data/state and deliberately change the relevant guards under review. Empty buckets only after data-retention requirements are met. Never use `-lock=false` or force-unlock an active operation.
