output "content" {
  description = "Concatenated user_data content"
  value       = join(var.separator, local.contents)
}
