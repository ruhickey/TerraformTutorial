#!/usr/bin/env bash

if [[ -f ./TERRAFORM_NEEDS_APPLY ]]; then
  aws codepipeline start-pipeline-execution --name TerraformPipeline
fi