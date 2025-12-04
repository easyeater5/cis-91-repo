variable "project" { }

variable "region" {
  default = "us-central1"
}

variable "zone" {
  default = "us-central1-c"
}

variable "scale" {
  description = "The number of web instances to create."
  type        = number
}