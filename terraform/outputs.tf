output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Elastic IP attached to the instance."
  value       = aws_eip.web.public_ip
}

output "site_url" {
  description = "Open this once Ansible has run (or after user_data + compose up)."
  value       = "http://${aws_eip.web.public_ip}"
}

output "ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = "ssh -i ${replace(pathexpand(var.public_key_path), ".pub", "")} ${var.ansible_ssh_user}@${aws_eip.web.public_ip}"
}

output "ansible_inventory_path" {
  description = "Inventory file Terraform generated for Task 1."
  value       = local_file.ansible_inventory.filename
}
