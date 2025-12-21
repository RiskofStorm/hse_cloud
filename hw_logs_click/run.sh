cd terraform
terraform init
terraform apply



# curl -X POST http://<nginx_public_ip>/write_log -H "Content-Type: application/json" -d '{"message":"test", "level":"INFO"}'
