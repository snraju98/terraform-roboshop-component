locals {
    
    ami_id = data.aws_ami.joindevops.id
    sg_id = data.aws_ssm_parameter.sg_id.value
    private_subnet_id = split(",", data.aws_ssm_parameter.private_subnet_ids.value)[0]
    common_name = "${var.project}-${var.environment}-${var.component}"
    common_tags = {
        Project = "${var.project}"
        Environment = "${var.environment}"
        Terraform = "true"
    }
}