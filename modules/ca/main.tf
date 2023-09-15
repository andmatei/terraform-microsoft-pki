terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.3.0"
    }
  }
}

data "aws_directory_service_directory" "ad" {
  directory_id = var.ad_id
}

data "aws_cloudhsm_v2_cluster" "hsm_cluster" {
  cluster_id = var.cloudhsm_cluster_id
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "ca-ssm-role"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Principal = {
            Service = "ec2.amazonaws.com"
          },
          Action = "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "ssm_instance" {
  role       = aws_iam_role.ec2_ssm_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm_ad" {
  role       = aws_iam_role.ec2_ssm_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMDirectoryServiceAccess"
}

resource "aws_iam_policy" "cloudhsm_initializer" {
  name        = "CloudHSMInitializer"
  description = "Provides access to initialize and activate a CloudHSM cluster"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "cloudhsm:InitializeCluster",
          "cloudhsm:DescribeClusters",
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "hsm_initializer" {
  role       = aws_iam_role.ec2_ssm_role.id
  policy_arn = aws_iam_policy.cloudhsm_initializer.arn
}

resource "aws_iam_instance_profile" "ca_ssm_role_profile" {
  name = "ca-ssm-role-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

data "aws_ami" "windows_ec2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }
}

resource "aws_instance" "ca" {
  ami                  = data.aws_ami.windows_ec2.id
  instance_type        = "t2.micro"
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.ca_ssm_role_profile.name

  security_groups = concat(var.security_group_ids, [data.aws_cloudhsm_v2_cluster.hsm_cluster.security_group_id])
  subnet_id       = var.subnet_id
}

locals {
  ca_initializer = file("${path.module}/assets/ca-init.ps1")
  hsm_initializer = templatefile(
    "${path.module}/assets/ca-init.ps1",
    {
      cluster_id = "${var.cloudhsm_cluster_id}"
    }
  )
}

resource "aws_ssm_document" "initialize_ca" {
  name          = "initialize-ca"
  document_type = "Command"
  content = jsonencode(
    {
      schemaVersion = "2.2",
      description   = "Conenct CA instance to CloudHSM cluster and AD",
      mainSteps = [
        {
          action = "aws:domainJoin",
          name   = "domainJoin",
          inputs = {
            "directoryId"    = data.aws_directory_service_directory.ad.id,
            "directoryName"  = data.aws_directory_service_directory.ad.name,
            "dnsIpAddresses" = data.aws_directory_service_directory.ad.dns_ip_addresses
          }
        },
        {
          action = "aws:runPowerShellScript",
          name   = "connectHSM",
          inputs = {
            runCommand = [
              "${local.hsm_initializer}",
            ]
          }
        },
      ]
    }
  )
}

resource "aws_ssm_association" "initialize_ca" {
  name = aws_ssm_document.initialize_ca.name
  targets {
    key    = "InstanceIds"
    values = [aws_instance.ca.id]
  }
}
