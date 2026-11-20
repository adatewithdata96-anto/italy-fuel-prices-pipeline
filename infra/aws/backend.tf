# Remote state. Create the bucket once (by hand or with a small bootstrap stack), then uncomment.
# Without this block the state is stored locally in terraform.tfstate (fine for a first try,
# not for a team).
#
# terraform {
#   backend "s3" {
#     bucket       = "<your-terraform-state-bucket>"
#     key          = "italy-fuel-prices-pipeline/dev/terraform.tfstate"
#     region       = "eu-west-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
