terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.21"
    }
  }

  backend "s3" {
    bucket = "terraform-state-ruhickey"
    key = "statefiles/pipelines/state"
    region = "eu-west-1"
  }

  required_version = ">= 1.2.4"
}

# This needs to be setup through the console so we just connect using ARN.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
locals {
  github_connection_arn = "arn:aws:codestar-connections:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:connection/64454de3-d46a-46fc-968a-f2c044b024d8"
}

resource "aws_s3_bucket" "source_bucket" {
  bucket = "terraform-source-bucket-ruhickey"
  force_destroy = true
}

resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid = ""
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role   = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.source_bucket.arn,
          "${aws_s3_bucket.source_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "codestar-connections:UseConnection"
        ],
        Resource = local.github_connection_arn
      },
      {
        Effect = "Allow",
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_s3_bucket_acl" "codepipeline_bucket_acl" {
  bucket = aws_s3_bucket.source_bucket.id
  acl    = "private"
}

resource "aws_iam_role" "codebuild_role" {
  name = "codebuild_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid = ""
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_plan_policy" {
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  role       = aws_iam_role.codebuild_role.name
}

# Need to scope this down
resource "aws_iam_role_policy_attachment" "codebuild_admin_plan_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.codebuild_role.name
}

resource "aws_codebuild_project" "pipeline_apply" {
  name         = "PipelineApply"
  service_role = aws_iam_role.codebuild_role.arn
  build_timeout = 5

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type         = "LINUX_CONTAINER"
  }

  concurrent_build_limit = 1

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspecs/pipeline.yml"
    git_clone_depth = 0
  }
}

resource "aws_codebuild_project" "terraform_plan" {
  name         = "PlanDevo"
  service_role = aws_iam_role.codebuild_role.arn
  build_timeout = 5

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type         = "LINUX_CONTAINER"
  }

  concurrent_build_limit = 1

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspecs/plan.yml"
    git_clone_depth = 0
  }
}

resource "aws_codebuild_project" "terraform_apply" {
  name         = "ApplyDevo"
  service_role = aws_iam_role.codebuild_role.arn
  build_timeout = 5

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type         = "LINUX_CONTAINER"
  }

  concurrent_build_limit = 1

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspecs/apply.yml"
    git_clone_depth = 0
  }
}

resource "aws_codepipeline" "codepipeline" {
  name     = "TerraformPipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.source_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      category = "Source"
      name     = "Source"
      owner    = "AWS"
      provider = "CodeStarSourceConnection"
      version  = "1"
      output_artifacts = ["SourceArtifact"]
      configuration = {
        ConnectionArn = local.github_connection_arn
        FullRepositoryId = "ruhickey/TerraformTutorial"
        BranchName = "mainline"
      }
    }
  }

  stage {
    name = "Pipeline"
    action {
      category = "Build"
      name     = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      input_artifacts = ["SourceArtifact"]
      output_artifacts = ["PipelineArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.pipeline_apply.name
      }
    }
  }

  stage {
    name = "Devo"

    action {
      category = "Build"
      name     = "Plan"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      input_artifacts = ["SourceArtifact"]
      namespace = "PlanOutput"
      run_order = 1
      configuration = {
        ProjectName = aws_codebuild_project.terraform_plan.name
      }
    }

    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
      run_order = 2
      configuration = {
        ExternalEntityLink = "https://${data.aws_region.current.name}.console.aws.amazon.com/codesuite/codebuild/${data.aws_caller_identity.current.account_id}}/projects/PlanDevo/build/#{PlanOutput.CODEBUILD_BUILD_ID}/?region=${data.aws_region.current.name}"
      }
    }

    action {
      category = "Build"
      name     = "Apply"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      input_artifacts = ["SourceArtifact"]
      run_order = 3
      configuration = {
        ProjectName = aws_codebuild_project.terraform_plan.name
      }
    }
  }
}