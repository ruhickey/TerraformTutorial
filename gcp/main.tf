terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  credentials = file("/etc/terraform/credentials/gcp.json")

  project = "terraform-russell-hickey"
  region  = "europe-west2"
  zone    = "europe-west2-a"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}