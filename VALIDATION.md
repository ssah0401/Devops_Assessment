# Validation results

Completed on 23 October 2026 using Terraform 1.13.5 and hashicorp/aws 5.100.0 on macOS arm64. The full final validation script returned exit code 0. See `validation.log` for its output.

| Validation | Result |
| --- | --- |
| `terraform fmt -check -recursive` | PASS |
| Main configuration `terraform validate` | PASS |
| EC2 module `terraform validate` | PASS |
| Backend bootstrap `terraform validate` | PASS |
| Main Terraform mock tests | 2 passed, 0 failed |
| EC2 Terraform mock tests | 7 passed, 0 failed |
| Backend Terraform mock tests | 1 passed, 0 failed |
| CI policy authorization cases | 13 passed |
| `critical-db` deletion guard | PASS: expected destruction rejection after successful mock creation |

The policy cases include allowed image-push/deploy/artifact reads and denied other repositories, services, families, clusters, task roles, role-passing targets, artifact writes, and unrelated AWS permissions. The Python evaluator covers the Action/Resource/Condition subset used by this policy; it is not AWS's IAM simulator.

Terraform tests use provider mocks; the deletion check also uses mocks and removes its temporary state. These checks verify configuration/schema validity, resource graph and input behavior, policy construction, and the Terraform lifecycle guard. No AWS resources were deployed. Live apply, AWS IAM/Access Analyzer evaluation, actual STS chaining, image push and ECS rollout, account quotas/AMI availability, PGP credential delivery, and concurrent remote-backend integration were not executed because real account details and credentials were not supplied. Supply the deployment prerequisites in README.md before performing those integration checks.
