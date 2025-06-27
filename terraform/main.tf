provider "aws" {
  region = var.aws_region
}


resource "aws_instance" "example1" {
    ami = var.ami_value
    instance_type = var.instance_type_value
    vpc_security_group_ids = [aws_security_group.mysg.id]
    iam_instance_profile   = aws_iam_instance_profile.s3_creator_uploader_profile.name 

    user_data = base64encode(templatefile("./${var.stage}_script.sh", {
    REPO_URL            = var.repo_url_value
    JAVA_VERSION        = var.java_version_value # Match JAVA_VERSION in script
    REPO_DIR_NAME       = var.repo_dir_name    # Match REPO_DIR_NAME in script
    STOP_INSTANCE       = var.stop_after_minutes # Match STOP_INSTANCE in script
    S3_BUCKET_NAME      = var.s3_bucket_name     # Match S3_BUCKET_NAME in script
    AWS_REGION_FOR_SCRIPT = var.aws_region       # NEW: Pass the AWS region from your provider config
    GITHUB_TOKEN  = var.github_token
    GIT_REPO_PATH = var.git_repo_path
  }))

  tags = {
    Name = "MyInstance-${var.stage}"
  }

  depends_on = [
    aws_s3_bucket.example
  ]
}



resource "aws_security_group" "mysg" {
  name = "webig-${var.stage}"

  ingress {
    description = "HTTP from vpc"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "Web.sg-${var.stage}"
  }

  
}

resource "aws_s3_bucket" "example" {
  bucket = var.s3_bucket_name 

  #force_destroy = true 

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "example" {
  bucket = aws_s3_bucket.example.id

  rule {
    id     = "delete_app_logs_after_7_days"
    status = "Enabled"

    filter {
      prefix = "logs/${var.stage}/"
    }

    lifecycle {
    ignore_errors = true
    }

    expiration {
      days = 7
    }
  }
}


resource "aws_iam_role" "s3_creator_uploader_role" {
  name = "s3_creator_uploader_access_role-${var.stage}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com" 
        }
      },
    ]
  })

  tags = {
    Name = "S3CreatorUploaderRole-${var.stage}"
  }
}

resource "aws_iam_policy" "s3_creator_uploader_policy" {
  name        = "s3_creator_uploader_policy-${var.stage}"
  description = "Provides permissions to create S3 buckets, upload objects, and manage lifecycle configurations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:CreateBucket",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:PutBucketLifecycleConfiguration",   # <-- NEW: Permission to create/update lifecycle config
          "s3:GetBucketLifecycleConfiguration",   # <-- NEW: Required to read the configuration
          "s3:DeleteBucketLifecycle",           # <-- NEW: Permission to delete lifecycle config (your error)
        ]
        Resource = "*"
      },
      {
        Effect   = "Deny"
        Action   = [
          "s3:Get*",  # This is a broad deny, but GetBucketLifecycleConfiguration will be allowed if explicitly permitted
          "s3:List*",
        ]
        Resource = "*"
      },
    ]
  })
}

# Attach S3 Creator/Uploader Policy to the Role
resource "aws_iam_role_policy_attachment" "s3_creator_uploader_attachment" {
  role       = aws_iam_role.s3_creator_uploader_role.name
  policy_arn = aws_iam_policy.s3_creator_uploader_policy.arn
}

# --- IAM Instance Profile for S3 Creator/Uploader Role ---
# An instance profile is required to attach an IAM role to an EC2 instance.
resource "aws_iam_instance_profile" "s3_creator_uploader_profile" {
  name_prefix = "s3-creator-uploader-profile-${var.stage}"
  role = aws_iam_role.s3_creator_uploader_role.name # Reference the role created above

  tags = {
    Name = "S3CreatorUploaderInstanceProfile-${var.stage}"
  }
}
