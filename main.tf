provider "aws" {
  region = "us-east-1"
}

resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = var.public_key
}

resource "aws_s3_bucket" "images_bucket" {
  bucket = "my-images-bucket"
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
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI (HVM), SSD Volume Type
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer.key_name

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

resource "aws_network_interface" "web_server_eni" {
  subnet_id       = aws_instance.web_server.subnet_id
  security_groups = [aws_security_group.web_sg.id]
  tags = {
    Name = "WebServerENI"
  }
}

resource "aws_network_interface_attachment" "web_server_eni_attachment" {
  instance_id          = aws_instance.web_server.id
  network_interface_id = aws_network_interface.web_server_eni.id
  device_index         = 0
}

output "bucket_name" {
  value = aws_s3_bucket.images_bucket.bucket
}

output "web_server_public_ip" {
  value = aws_instance.web_server.public_ip
}
