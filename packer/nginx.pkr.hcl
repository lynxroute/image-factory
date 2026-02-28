# =============================================================
# Packer шаблон: Nginx AMI для AWS
# Ubuntu 24.04 LTS + Nginx последней стабильной версии
# =============================================================

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.3"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.1"
    }
  }
}

# ── Переменные ───────────────────────────────────────────────
variable "aws_region" {
  default = "us-east-1"
}

variable "os_version" {
  default     = "ubuntu2404"
  description = "OS версия для имени AMI"
}

variable "nginx_version" {
  default     = "1.26"
  description = "Nginx minor version"
}

variable "build_env" {
  default     = "prod"
  description = "prod / staging"
}

variable "build_timestamp" {
  default     = ""
  description = "Timestamp из CI (Europe/Riga). Если пусто — генерируется локально"
}

# ── Локальные значения ───────────────────────────────────────
locals {
  timestamp = var.build_timestamp != "" ? var.build_timestamp : formatdate("YYYYMMDD-hhmm", timestamp())
  ami_name  = "nginx-${var.nginx_version}-${var.os_version}-${local.timestamp}"
}

# ── Source: AWS EBS ──────────────────────────────────────────
source "amazon-ebs" "nginx" {
  region        = var.aws_region
  instance_type = "t3.micro"
  ssh_username  = "ubuntu"

  # Ubuntu LTS: 24.04 (Noble) — обновить на следующий LTS в апреле 2026
  # Следующий LTS: Ubuntu 26.04, выйдет ~апрель 2026
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  ami_name        = local.ami_name
  ami_description = "Nginx ${var.nginx_version} on Ubuntu 24.04 LTS - built by image-factory"

  # Копируем AMI в несколько регионов (раскомментируй если нужно)
  # ami_regions = ["eu-west-1", "ap-southeast-1"]

  tags = {
    Name      = local.ami_name
    Software  = "nginx"
    Version   = var.nginx_version
    BaseOS    = var.os_version
    BuildDate = local.timestamp
    BuildEnv  = var.build_env
    ManagedBy = "image-factory"
  }

  # Диск: 8GB gp3
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # Временная security group — только SSH для Packer
  temporary_security_group_source_cidrs = ["0.0.0.0/0"]
}

# ── Build ────────────────────────────────────────────────────
build {
  name    = "nginx-ami"
  sources = ["source.amazon-ebs.nginx"]

  # Шаг 1: ждём пока Ubuntu полностью загрузится
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init...'",
      "cloud-init status --wait || true",
      "echo 'Ready!'",
    ]
  }

  # Шаг 2: Ansible устанавливает и настраивает Nginx + OS hardening
  provisioner "ansible" {
    playbook_file = "ansible/playbooks/nginx.yml"
    extra_arguments = [
      "--extra-vars", "nginx_version=${var.nginx_version}",
      "--extra-vars", "build_env=${var.build_env}",
      "-v",
    ]
  }

  # Шаг 3: smoke test внутри VM
  provisioner "shell" {
    script = "tests/smoke_test.sh"
  }

  # Шаг 4: AWS Marketplace cleanup — перед snapshot
  provisioner "shell" {
    script = "scripts/cleanup.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }

  # Манифест с AMI ID
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
