variable "scripts" {
  description = "List of local script paths to concatenate into user_data"
  type        = list(string)
}

variable "inline_snippets" {
  type        = list(string)
  default     = []
  description = "Raw shell script snippets to prepend/append inline."
}

variable "separator" {
  type    = string
  default = "\n\n"
}
