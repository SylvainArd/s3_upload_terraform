provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "terraform_role" {
  name = "terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "terraform_policy" {
  name        = "terraform-policy"
  description = "Policy for Terraform to manage S3 and EC2"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:CreateBucket",
          "s3:PutBucketAcl",
          "s3:PutBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:CreateSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_attach" {
  role       = aws_iam_role.terraform_role.name
  policy_arn = aws_iam_policy.terraform_policy.arn
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "terraform-instance-profile"
  role = aws_iam_role.terraform_role.name
}

resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = var.public_key
}

resource "aws_s3_bucket" "images_bucket" {
  bucket = "my-unique-images-bucket-123456" # Changez ce nom pour un nom unique
}

resource "aws_s3_bucket_acl" "images_bucket_acl" {
  bucket = aws_s3_bucket.images_bucket.bucket
  acl    = "public-read"
}

resource "aws_s3_bucket_website_configuration" "images_bucket_website" {
  bucket = aws_s3_bucket.images_bucket.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_instance" "web_server" {
  ami                  = "ami-04505e74c0741db8d" # Utilisez une AMI valide pour votre région
  instance_type        = "t2.micro"
  key_name             = aws_key_pair.deployer.key_name
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y httpd php php-cli php-json php-mbstring git
    sudo systemctl start httpd
    sudo systemctl enable httpd

    # Installer Composer
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    php -r "unlink('composer-setup.php');"
  EOF

  tags = {
    Name = "WebServer"
  }

  vpc_security_group_ids = [aws_security_group.web_sg.id]
}

resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow HTTP and SSH traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "bucket_name" {
  value = aws_s3_bucket.images_bucket.bucket
}

output "web_server_public_ip" {
  value = aws_instance.web_server.public_ip
}
