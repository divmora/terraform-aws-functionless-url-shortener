# Agent Guidelines for terraform-aws-functionless-url-shortener

Terraform/OpenTofu port of [divmora/functionless-url-shortener](https://github.com/divmora/functionless-url-shortener) (SAM/CloudFormation).

## Goals & constraints
- **Feature parity with the SAM template first.** Behaviour (API routes, VTL mapping templates, resource policy, stage method settings, CloudFront behaviour, alarms) must match SAM unless an issue explicitly decides otherwise. API logging (`LoggingLevel: INFO`, `DataTraceEnabled: true`) is copied as-is by decision.
- **Terraform and OpenTofu, both `>= 1.6`.** Don't use language features newer than 1.6 in module code (tests may use `mock_provider`, which runs only on latest in CI).
- **Zero compute.** No Lambda or containers on the request path.
- **CloudFront monitoring runs through the `aws.us_east_1` provider alias**; CloudFront metrics exist only in us-east-1 with the `Region=Global` dimension.
- Before adding or changing a CloudWatch alarm, verify the metric's dimensions in the AWS docs (e.g. DynamoDB `SystemErrors` exists only per `TableName`+`Operation`).

## Shared API definition
`templates/api.yaml.tftpl` must stay in sync with `api.yaml` in the SAM repo (placeholders instead of CloudFormation intrinsics). CI will compare the VTL templates.

## Conventions
- Conventional Commits; Release Please (`terraform-module`) manages versions (`0.x` until parity is proven on real deployments).
- Run `terraform fmt -recursive`, `terraform validate`, `tflint --recursive` (and the same with `tofu`) before pushing.
