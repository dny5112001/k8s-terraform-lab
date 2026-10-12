output "region" {
  value = var.region
}

output "bucket_name" {
  value = module.notes_bucket.bucket_name
}

output "app_access_key_id" {
  value = module.notes_bucket.access_key_id
}

output "app_secret_access_key" {
  value     = module.notes_bucket.secret_access_key
  sensitive = true
}
