locals {
  static_contents = [for p in var.scripts : file(abspath(p))]
  contents        = concat(var.inline_snippets, local.static_contents)
}

