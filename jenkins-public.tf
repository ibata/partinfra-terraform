data "aws_iam_policy_document" "jenkins-assume-role-policy" {

    statement {
        effect = "Allow"
        actions = [
            "sts:AssumeRole",
        ]

        principals {
            type = "Service"
            identifiers = [
                "ec2.amazonaws.com"
            ]
        }
    }
}

resource "aws_iam_role" "jenkins-role" {
    name = "JenkinsRole"
    assume_role_policy = "${data.aws_iam_policy_document.jenkins-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "jenkins-access-policy" {
    role = "${aws_iam_role.jenkins-role.name}"
    policy_arn = "${lookup(var.unmanaged_role_arns, "mozdef-logging")}"
}

resource "aws_iam_instance_profile" "jenkins-profile" {
    name = "jenkins-profile"
    roles = ["${aws_iam_role.jenkins-role.name}"]
}

resource "aws_security_group" "jenkins-public-ec2-sg" {
    name                    = "jenkins-public-ec2-sg"
    description             = "jenkins-public SG"
    vpc_id                  = "${aws_vpc.apps-shared-vpc.id}"
}

resource "aws_security_group_rule" "jenkins-public-ec2-sg-allowsharedssh" {
    type                    = "ingress"
    from_port               = 22
    to_port                 = 22
    protocol                = "tcp"
    cidr_blocks             = ["${aws_vpc.apps-shared-vpc.cidr_block}"]
    security_group_id       = "${aws_security_group.jenkins-public-ec2-sg.id}"
}

resource "aws_security_group_rule" "jenkins-public-ec2-sg-allowhttpfromjenkins-public-elb" {
    type                     = "ingress"
    from_port                = 8080
    to_port                  = 8080
    protocol                 = "tcp"
    source_security_group_id = "${aws_security_group.jenkins-public-elb-sg.id}"

    security_group_id        = "${aws_security_group.jenkins-public-ec2-sg.id}"
}

resource "aws_security_group_rule" "jenkins-public-ec2-sg-allowmesosframework" {
    type                     = "ingress"
    from_port                = 10000
    to_port                  = 65535
    protocol                 = "tcp"
    source_security_group_id = "${module.mesos-cluster-staging.mesos-cluster-master-sg-id}"

    security_group_id        = "${aws_security_group.jenkins-public-ec2-sg.id}"
}

resource "aws_security_group_rule" "jenkins-public-ec2-sg-allowprodmesosframework" {
    type                     = "ingress"
    from_port                = 10000
    to_port                  = 65535
    protocol                 = "tcp"
    source_security_group_id = "${module.mesos-cluster-production.mesos-cluster-master-sg-id}"

    security_group_id        = "${aws_security_group.jenkins-public-ec2-sg.id}"
}

resource "aws_security_group_rule" "jenkins-public-ec2-sg-allowjnlpfromslave" {
    type                     = "ingress"
    from_port                = 50000
    to_port                  = 50000
    protocol                 = "tcp"
    source_security_group_id = "${module.mesos-cluster-staging.mesos-cluster-slave-sg-id}"

    security_group_id        = "${aws_security_group.jenkins-public-ec2-sg.id}"
}

resource "aws_security_group_rule" "jenkins-public-ec2-sg-allowjnlpfromprodslave" {
    type                     = "ingress"
    from_port                = 50000
    to_port                  = 50000
    protocol                 = "tcp"
    source_security_group_id = "${module.mesos-cluster-production.mesos-cluster-slave-sg-id}"

    security_group_id        = "${aws_security_group.jenkins-public-ec2-sg.id}"
}

resource "aws_security_group_rule" "jenkins-public-ec2-sg-allowhttpfromall" {
    type                     = "ingress"
    from_port                = 8080
    to_port                  = 8080
    protocol                 = "tcp"
    cidr_blocks              = [
        "${aws_vpc.apps-shared-vpc.cidr_block}",
        "${aws_vpc.apps-staging-vpc.cidr_block}",
        "${aws_vpc.apps-production-vpc.cidr_block}"
    ]

    security_group_id        = "${aws_security_group.jenkins-public-ec2-sg.id}"
}

resource "aws_security_group_rule" "jenkins-public-ec2-sg-allowallegress" {
    type                    = "egress"
    from_port               = 0
    to_port                 = 0
    protocol                = "-1"
    cidr_blocks             = ["0.0.0.0/0"]
    security_group_id       = "${aws_security_group.jenkins-public-ec2-sg.id}"
}

resource "aws_instance" "jenkins-public-ec2" {
    ami                     = "${lookup(var.aws_amis, var.aws_region)}"
    instance_type           = "t2.medium"
    disable_api_termination = true
    key_name                = "ansible"
    vpc_security_group_ids  = ["${aws_security_group.jenkins-public-ec2-sg.id}"]
    iam_instance_profile    = "${aws_iam_instance_profile.jenkins-profile.name}"
    subnet_id               = "${aws_subnet.apps-shared-1c.id}"

    root_block_device {
        volume_type = "gp2"
        volume_size = 100
    }

    tags {
        Name                = "jenkins-public"
        app                 = "jenkins"
        env                 = "shared"
        project             = "partinfra"
    }
}

resource "aws_security_group" "jenkins-public-elb-sg" {
    name        = "jenkins-public-elb-sg"
    description = "jenkins-public ELB SG"
    vpc_id      = "${aws_vpc.apps-shared-vpc.id}"
}


resource "aws_security_group_rule" "jenkins-public-elb-sg-allowhttps" {
    type              = "ingress"
    from_port         = 443
    to_port           = 443
    protocol          = "tcp"
    cidr_blocks       = ["0.0.0.0/0"]

    security_group_id = "${aws_security_group.jenkins-public-elb-sg.id}"
}

resource "aws_security_group_rule" "jenkins-public-elb-sg-allowall" {
    type              = "egress"
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]

    security_group_id = "${aws_security_group.jenkins-public-elb-sg.id}"
}

resource "aws_elb" "jenkins-public-elb" {
    name                        = "jenkins-public-elb"
    security_groups             = ["${aws_security_group.jenkins-public-elb-sg.id}"]
    subnets                     = ["${aws_subnet.apps-shared-1c.id}"]
    internal                    = false

    listener {
        instance_port             = 8081
        instance_protocol         = "http"
        lb_port                   = 443
        lb_protocol               = "https"
        ssl_certificate_id        = "${lookup(var.ssl_certificates, "mesos-elb-${var.aws_region}")}"
    }

    health_check {
        healthy_threshold         = 2
        unhealthy_threshold       = 2
        timeout                   = 3
        target                    = "TCP:8080"
        interval                  = 30
    }

    instances = ["${aws_instance.jenkins-public-ec2.id}"]
    cross_zone_load_balancing   = true
    idle_timeout                = 400
    connection_draining         = true
    connection_draining_timeout = 400

    tags {
        Name                      = "jenkins-public-elb"
        app                       = "jenkins"
        env                       = "shared"
        project                   = "partinfra"
    }
}
