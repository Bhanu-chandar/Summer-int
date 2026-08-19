variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix applied to every resource."
  type        = string
  default     = "summerint"
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro/t2.micro are free-tier eligible in most regions."
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "public_key_path" {
  description = "Path to the SSH public key uploaded as an EC2 key pair."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "private_key_path" {
  description = <<-EOT
    Path to the PRIVATE key matching public_key_path, used in the generated
    Ansible inventory and the ssh_command output. Leave empty to derive it by
    stripping ".pub" (works for id_rsa/id_rsa.pub, but not for ".pem" keys).
  EOT
  type        = string
  default     = ""
}

variable "ssh_allowed_cidr" {
  description = <<-EOT
    CIDR allowed to reach port 22. Defaults to 0.0.0.0/0 so the lab works
    anywhere, but you should narrow this to your own IP (e.g. "203.0.113.4/32").
  EOT
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR block, e.g. 203.0.113.4/32."
  }
}

variable "http_allowed_cidr" {
  description = "CIDR allowed to reach port 80."
  type        = string
  default     = "0.0.0.0/0"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 16
}

variable "ansible_ssh_user" {
  description = "Login user for the AMI, written into the generated Ansible inventory."
  type        = string
  default     = "ec2-user"
}

variable "extra_ingress_ports" {
  description = <<-EOT
    Additional TCP ports to open to var.http_allowed_cidr. Task 4 allows the
    app on port 80 *or* 8080; set this to [8080] if you deploy on 8080 and
    want to reach it without an SSH tunnel.
  EOT
  type        = list(number)
  default     = []
}

variable "jenkins_ingress_enabled" {
  description = <<-EOT
    Open port 8080 for a Jenkins controller running on this instance (Task 5/6).
    GitHub's webhook (Task 6) must be able to reach Jenkins, so this opens to
    var.jenkins_allowed_cidr.
  EOT
  type        = bool
  default     = false
}

variable "jenkins_allowed_cidr" {
  description = "CIDR allowed to reach Jenkins on 8080 when jenkins_ingress_enabled is true."
  type        = string
  default     = "0.0.0.0/0"
}
