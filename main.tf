resource "aws_instance" "main" {
  ami           = local.ami_id
  instance_type = "t3.micro"
  vpc_security_group_ids = [local.sg_id]
  subnet_id = local.private_subnet_id
  
  tags = merge(
    {
        Name = "${local.common_name}" # roboshop-dev-catalogue
    },
    local.common_tags
  )
}

resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    password = "DevOps321"
    host        = aws_instance.main.private_ip
  }

  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} ${var.environment} ${var.app_version}"
    ]
  }
}

