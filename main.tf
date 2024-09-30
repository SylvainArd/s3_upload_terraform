terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 4.0.0"
    }
    random = {
      source = "hashicorp/random"
      version = ">= 3.1.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "random" {
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = var.public_key
}

resource "aws_s3_bucket" "images_bucket" {
  bucket = "sylvain-ard-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "images_bucket"
  }
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

resource "aws_s3_bucket_policy" "images_bucket_policy" {
  bucket = aws_s3_bucket.images_bucket.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.images_bucket.bucket}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "${aws_cloudfront_distribution.s3_distribution.arn}"
        }
      }
    }
  ]
}
EOF
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "S3-OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  description                       = "OAC for S3 bucket"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.images_bucket.bucket}.s3.amazonaws.com"
    origin_id   = "S3-${aws_s3_bucket.images_bucket.bucket}"

    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 distribution"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.images_bucket.bucket}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "S3 distribution"
  }
}

# Rôle IAM pour l'instance EC2
resource "aws_iam_role" "ec2_role" {
  name = "ec2-s3-access-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Politique IAM pour autoriser l'accès à S3 depuis l'instance EC2
resource "aws_iam_policy" "s3_access_policy" {
  name        = "S3AccessPolicy"
  description = "Politique permettant l'accès à S3 pour EC2"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${aws_s3_bucket.images_bucket.bucket}",
        "arn:aws:s3:::${aws_s3_bucket.images_bucket.bucket}/*"
      ]
    }
  ]
}
EOF
}

# Attachement de la politique IAM au rôle EC2
resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# Création du profil d'instance pour attacher le rôle IAM à l'instance EC2
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# Création de l'instance EC2 avec le rôle IAM pour accéder à S3
resource "aws_instance" "web_server" {
  ami           = "ami-00beae93a2d981137"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer.key_name

  # Attachement du profil d'instance pour le rôle IAM
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

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

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "web_server_public_ip" {
  value = aws_instance.web_server.public_ip
}
