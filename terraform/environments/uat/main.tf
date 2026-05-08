data "terraform_remote_state" "nonprod" {
  backend = "s3"

  config = {
    bucket  = "samosachaat-terraform-state-906352610196"
    key     = "envs/dev/terraform.tfstate"
    region  = "us-west-2"
    encrypt = true
  }
}
