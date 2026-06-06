resource "google_project_service" "enabled" {
  for_each = local.enabled_apis

  project = var.project_id
  service = each.value

  # Never auto-disable on destroy: a stray `terraform destroy` of this stack
  # must not silently break sibling projects or unrelated workloads sharing
  # the API. Re-enabling is cheap; recovering from an accidental disable is
  # not.
  disable_on_destroy         = false
  disable_dependent_services = false
}
