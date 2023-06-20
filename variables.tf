variable "region" {

  type    = string
  default = "eu-north-1"

}

variable "docker_host" {

  type    = string
  default = "unix:///var/run/docker.sock"

}

variable "aws_profile" {
  type    = string
  default = ""
}