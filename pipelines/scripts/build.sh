#!/usr/bin/env bash

PLAN_FILE=terraform.plan

terraform plan > $PLAN_FILE
grep -q 'No changes.' $PLAN_FILE
SHOULD_APPLY=$?

cat $PLAN_FILE

if [[ $SHOULD_APPLY -eq 1 ]]; then
  touch ./TERRAFORM_NEEDS_APPLY
  terraform apply -auto-approve
fi
