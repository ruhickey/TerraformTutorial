## Terraform Pipeline Example

[![Yamllint GitHub Actions](https://github.com/ruhickey/TerraformTutorial/actions/workflows/yamllint.yml/badge.svg?branch=mainline)](https://github.com/ruhickey/TerraformTutorial/actions/workflows/yamllint.yml)

## Development
### Amazon Web Services (AWS)
#### Initial Setup
This will create a code pipeline in AWS.

**NOTE: We work from aws directory so make sure to start there.**
```bash
cd aws
```

**NOTE: The Github Connection is a Hardcoded ARN as there is manual approval involved.**

```bash
cd pipelines
terraform init
terraform plan
terraform apply
```

#### Deploying a development setup per user
Add the following to your ~/.bashrc or ~/.zshrc file.
```
export TF_VAR_disambiguator="$USER"
```
Check out a workspace in terraform. This makes sure you have a different state file saved.
```
terraform workspace new $USER
```
Deploying EC2 instance.
```
cd dev
terraform plan
terraform apply
```
This should create an EC2 instance called `ExampleServer-${USER}`. This is useful for checking changes before committing.

Once all has been tested, you can push your code and it should create an EC2 instance
called `ExampleServer-dev` through the pipeline.

#### Pipeline Updates
When updating the pipeline to add new stages. You update the code and do a `terraform plan`.
Once code is committed, the pipeline will automatically update itself.

## Google Cloud Platform (GCP)