# =============================================================
# Packer шаблон: Nginx AMI для AWS
# Ubuntu 22.04 LTS + Nginx последней стабильной версии
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
 
variable "nginx_version" {
  default = "1.26"
  description = "Nginx minor version (1.24 или 1.26)"
}
 
variable "build_env" {
  default = "prod"
  description = "prod / staging"
}
 
# ── Локальные значения ───────────────────────────────────────
locals {
  timestamp  = formatdate("YYYYMMDD-hhmm", timestamp())
  ami_name   = "nginx-${var.nginx_version}-ubuntu2204-${local.timestamp}"
}
 
# ── Source: AWS EBS ──────────────────────────────────────────
source "amazon-ebs" "nginx" {
  region        = var.aws_region
  instance_type = "t3.micro"    # бесплатный tier — достаточно для сборки
  ssh_username  = "ubuntu"
 
  # Берём последний официальный Ubuntu 22.04 LTS от Canonical
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]  # Canonical официальный ID
    most_recent = true
  }
 
  ami_name        = local.ami_name
  ami_description = "Nginx ${var.nginx_version} on Ubuntu 22.04 LTS — built by image-factory"
 
  # Копируем AMI в несколько регионов (раскомментируй если нужно)
  # ami_regions = ["eu-west-1", "ap-southeast-1"]
 
  tags = {
    Name        = local.ami_name
    Software    = "nginx"
    Version     = var.nginx_version
    BaseOS      = "ubuntu-22.04"
    BuildDate   = local.timestamp
    BuildEnv    = var.build_env
    ManagedBy   = "image-factory"
  }
 
  # Диск: 8GB gp3 — достаточно для Nginx
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true    # шифруем по умолчанию
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
 
  # Шаг 2: Ansible устанавливает и настраивает Nginx
  provisioner "ansible" {
    playbook_file = "ansible/playbooks/nginx.yml"
    extra_arguments = [
      "--extra-vars", "nginx_version=${var.nginx_version}",
      "--extra-vars", "build_env=${var.build_env}",
      "-v",
    ]
  }
 
  # Шаг 3: smoke test прямо внутри VM
  provisioner "shell" {
    script = "tests/smoke_test.sh"
  }
 
  # Шаг 4: финальный cleanup перед созданием snapshot
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /tmp/* /var/tmp/*",
      "sudo rm -f /root/.bash_history /home/ubuntu/.bash_history",
      "sudo truncate -s 0 /var/log/syslog /var/log/auth.log || true",
      "echo 'Cleanup done'",
    ]
  }
 
  # Выводим имя AMI в конце
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
 
