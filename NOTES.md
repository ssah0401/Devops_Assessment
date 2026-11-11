# Assessment notes

## Task 1 — One map, five distinct instances

The reusable EC2 module has one input variable, `instances`, with exactly five named objects. Input validation rejects duplicate instance types, root volume types/sizes, key names and public keys, and requires provisioned IOPS for io1/io2. Five `aws_key_pair` resources are created with `for_each` from that same map. Each instance and root volume carries Name, Environment and Owner tags.

| Instance | Instance type | Root type | GiB | IOPS | Key pair |
| --- | --- | --- | ---: | ---: | --- |
| web | t3.micro | gp2 | 10 | Default | assessment-web |
| worker | t3.small | gp3 | 16 | Default | assessment-worker |
| batch | t3.medium | standard | 20 | N/A | assessment-batch |
| api | m5.large | io1 | 24 | 1000 | assessment-api |
| critical-db | m5.xlarge | io2 | 32 | 3000 | assessment-critical-db |

**Protected instance: `critical-db`.** I chose it to represent the workload most likely to contain valuable state. A literal `lifecycle { prevent_destroy = true }` blocks Terraform deletion/replacement while its resource block remains in configuration. The map is partitioned across a regular resource block (four instances) and a protected resource block (one instance). Terraform requires literal lifecycle values, so `prevent_destroy = each.key == "critical-db"` is invalid. This uses two shared resource definitions, not five hardcoded instance blocks. Removing the protected name from the input is rejected. Changing a replacement-triggering argument also encounters the guard.

The guard is not a backup or an AWS-wide deletion barrier. Removing the resource block/module from the configuration removes its protection; direct EC2 API deletion is outside Terraform's control. Preserve the guard through review and use backups for persistent data. The latest AMI lookup makes the example region-portable; pin a tested AMI before production rollout because a newer AMI may require replacement, which the protected instance will reject.

Five different boot-volume types require the legacy Magnetic `standard` type alongside gp2, gp3, io1 and io2. st1/sc1 are unsuitable as root volumes. Magnetic is included to satisfy the assignment's five distinct types, not as a production performance recommendation. Size must also fit the selected AMI's root snapshot; the supplied Amazon Linux configuration starts at 10 GiB. The selected IOPS values are within the conservative io1/io2 ratios checked by the module. Availability and quotas still require a real account plan/apply. [AWS EBS volume types](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html)

Both module and root export maps of instance name to instance ID and private IP.

## Task 2 — Remote state and locking

With local state on two different computers, each operator has a separate view of the world and a separate local lock. Both can apply simultaneously, attempt overlapping changes, create duplicates or overwrite a shared copy of state. Terraform does lock a local state file on one machine; the problem is that independent local copies do not coordinate.

The main root uses an S3 backend and a DynamoDB lock table with a String partition key named `LockID`. Every operator must use the same backend bucket, key, region and workspace. Terraform atomically acquires the shared lock before a state-writing operation. A second apply waits with `-lock-timeout=5m` or fails to acquire the lock. This serializes access to that state; it does not coordinate unrelated states managing the same resources. Do not disable locking.

The bootstrap creates the backend before the main stack is initialized. The bucket has versioning, SSE-S3 encryption, public-access blocking, a TLS-only policy and deletion protection through Terraform. The table uses on-demand billing, encryption, PITR, Terraform deletion protection and AWS deletion protection. Backend users need `s3:ListBucket` on the state bucket, `s3:GetObject`/`s3:PutObject` on the state key, and `dynamodb:DescribeTable`, `GetItem`, `PutItem`, `DeleteItem` on the lock table. Backend credentials are separate from the AWS resource provider configuration; both are configured explicitly.

DynamoDB locking is implemented because the assignment explicitly requests it. It is deprecated upstream. This package pins a tested Terraform range that supports it. For a future migration, coordinate all clients and move to S3 `use_lockfile = true`; do not mix clients using incompatible lock mechanisms. [HashiCorp S3 backend and locking](https://developer.hashicorp.com/terraform/language/backend/s3)

## Task 3 — Users, groups and cross-account roles

`group1` contains engine and ci, with encrypted programmatic keys and no login profiles. Neither has permission to create login profiles. `group2` contains alice and bob, each with a login profile requiring password reset and an encrypted programmatic key. Group membership does not itself create console or CLI credentials; those resources are explicit. The group2 self-service policy uses `${aws:username}` to allow each user to change only their own password.

roleA allows all actions except `iam:*`, with an explicit IAM deny. It trusts alice and bob only. Administrative access is exercised after assuming the role through either CLI or console. IAM-dependent operations such as passing a role are consequently denied in roleA. This matches the assignment but is not an organizational isolation boundary: broad STS, Organizations or other service administration may create indirect escalation paths if other configurations allow them. In production, restrict role assumption/delegation and use organizational guardrails appropriate to the environment.

roleB trusts engine, alice and bob; ci is intentionally excluded. roleB's only permission is assuming roleC. roleC is provisioned in Account B and trusts only roleB's ARN in Account A. Both sides of the cross-account authorization are present: roleB's identity permission and roleC's trust policy. Only roleC's named bucket and object ARNs occur in its S3 permission policy. The bucket is private, uses SSE-S3, and has enforced bucket ownership; KMS grants are not needed for this example.

**1. Would I give engine and ci IAM users with access keys in production?** No. I would use short-lived workload identities: CI OIDC federation into a tightly scoped IAM role with issuer, audience and repository/branch subject restrictions; engine would use an EC2 instance profile, ECS task role, EKS Pod Identity/IRSA, or another workload federation mechanism matching where it runs. Human operators should use IAM Identity Center with MFA and temporary CLI sessions. The users/keys here implement the requested exercise, and their secrets are PGP-encrypted rather than emitted in plaintext. That does not make long-lived keys preferable: they still require controlled delivery, rotation and revocation.

**2. Why trust roleB's ARN instead of Account A root?** An `arn:aws:iam::000000000000:root` principal delegates trust to the account, not just its root user. Account A can then authorize other principals to assume roleC through identity policies. Trusting `arn:aws:iam::000000000000:role/roleB` limits the entry point to sessions of that role. Whoever can legitimately assume roleB can follow the chain, but other Account A users/roles cannot directly assume roleC merely by adding an identity-policy allow. Account B administrators can still change the trust policy; this design does not claim to restrict them. AWS binds a role principal to its internal principal ID, so deleting/recreating roleB requires updating roleC's trust. [AWS role trust principals](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_principal.html)

## Task 4 — Custom CI policy and exclusions

`policies/ci-policy.json` is attached directly to ci; no broad managed policy or group1 role grants enlarge its privileges.

- ECR login needs `ecr:GetAuthorizationToken` on `*`; repository-scoped push operations, including the AWS-documented `BatchGetImage`, target only `assessment-app`. No repository creation/deletion, policy changes or image deletion is allowed. [AWS ECR push permissions](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-push-iam.html)
- RegisterTaskDefinition targets only revisions of `assessment-app`. UpdateService targets one service, with cluster and task-definition conditions. The pipeline must explicitly supply that family's task-definition ARN on update. It cannot create/delete services, run arbitrary tasks or operate other families/services. Current ECS authorization documentation supports task-definition resources for registration. [AWS ECS authorization reference](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ecs.html)
- `iam:PassRole` is required when registering/deploying definitions with execution/task roles. Only the two pre-existing named roles may be passed, and only to `ecs-tasks.amazonaws.com`. They must themselves have appropriately narrow runtime policies; no role creation, policy editing or general role passing is granted.
- Artifacts allow ListBucket and GetObject on one named bucket and its objects. This supports listing a build and retrieving its files. No upload, delete, ACL/policy changes, account-wide bucket listing or object-version access is granted. The pipeline uses explicit bucket and region values. Assume SSE-S3 artifacts; a different SSE-KMS setup needs a separately reviewed exact-key decrypt grant.

I left out ECS discovery and DescribeServices because this minimal pipeline supplies a complete task-definition JSON, captures the ARN returned by registration, and submits UpdateService directly. It does not use a service-stability waiter or console. A pipeline using those features would need narrowly scoped read permissions added explicitly. Infrastructure provisioning, CloudWatch log reads, Secrets Manager access and IAM administration are also outside this pipeline's responsibilities.

Registering a family and updating the designated service still lets CI change its container code/configuration and settings allowed by UpdateService. This is required deployment authority; IAM is not a task-definition-content validator. Protect the pipeline/repository and the two passed roles accordingly.

## Task 5 — The two bugs

**Trust-policy bug:** `arn:aws:iam::000000000000:user/roleB` identifies an IAM user named roleB. The caller is a role, whose correct ARN is `arn:aws:iam::000000000000:role/roleB`. Those are different principal types and identities. If that user does not exist, AWS rejects the principal during policy creation; if it exists, its trust does not authorize roleB's sessions. The implementation references `aws_iam_role.roleB.arn` rather than hardcoding the wrong path. Its resulting trust is:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Principal": {"AWS": "arn:aws:iam::000000000000:role/roleB"}
  }]
}
```

**Permissions-policy bug:** `s3:*` with `Resource: "*"` is valid IAM syntax, but authorizes S3 across all resources and violates the single-bucket requirement. It is a scope/security bug, not the cause of an STS trust failure. The fix keeps full S3 actions and restricts resources to the chosen bucket ARN **and** its object ARN:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "s3:*",
    "Resource": [
      "arn:aws:s3:::devops-rolec-data-111111111111",
      "arn:aws:s3:::devops-rolec-data-111111111111/*"
    ]
  }]
}
```

The bucket ARN covers bucket-level operations such as listing; the trailing `/*` covers objects. Only one of these would leave part of the requested access missing. Account-wide S3 actions without a bucket resource are deliberately not authorized. `iam.tf` also uses the Account B provider for roleC and grants roleB `sts:AssumeRole` on roleC, which are required deployment/authorization details beyond those two snippet bugs.
