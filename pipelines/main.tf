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

#resource "aws_codestarconnections_connection" "github-connection" {
#  name = "GitHubConnection"
#  provider = aws
#}

data "aws_caller_identity" "current" {}

locals {
  github_connection_arn = "arn:aws:codestar-connections:eu-west-1:${data.aws_caller_identity.current.account_id}:connection/64454de3-d46a-46fc-968a-f2c044b024d8"
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

resource "aws_iam_role" "codebuild_plan_role" {
  name = "codebuild_plan_role"
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
  role       = aws_iam_role.codebuild_plan_role.name
}

# Need to scope this down
resource "aws_iam_role_policy_attachment" "codebuild_admin_plan_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.codebuild_plan_role.name
}

resource "aws_codebuild_project" "terraform_plan" {
  name         = "TerraformPlanV2"
  service_role = aws_iam_role.codebuild_plan_role.arn
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
    git_submodules_config {
      fetch_submodules = false
    }
  }
}

resource "aws_codebuild_project" "terraform_plan" {
  name         = "TerraformPlanV2"
  service_role = aws_iam_role.codebuild_plan_role.arn
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
    git_submodules_config {
      fetch_submodules = false
    }

  }
}

resource "aws_codepipeline" "codepipeline" {
  name     = "tf-test-pipeline"
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
        ProjectName = aws_codebuild_project.terraform_plan.name
      }
    }
  }
}