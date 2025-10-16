locals {
  static_contents = [for p in var.scripts : try(file(abspath(p)), p)]
  static_hash     = join("", [for s in local.static_contents : sha256(s)])
  contents        = concat(var.inline_snippets, local.static_contents)
}

