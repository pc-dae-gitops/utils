terraform {
  backend "s3" {
    bucket         = "ww-management-cluster-terraform-state"
    key            = "$ENVIRONMENT/$TYPE/$NAME/$TEMPLATE_STATE_PATH/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "nab-terraform-remote-state-lock-table"
  }
}