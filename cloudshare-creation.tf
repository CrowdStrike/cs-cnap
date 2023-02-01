
data "aws_ami" "amazon" {
 most_recent = true
 owners = ["amazon"]

 filter {
   name   = "owner-alias"
   values = ["amazon"]
 }

 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }
}


resource "aws_iam_role_policy" "crowdstrike_bootstrap_policy" {
  name = "crowdstrike_bootstrap_policy"
  role = aws_iam_role.crowdstrike_bootstrap_role.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}
data "aws_caller_identity" "current" {}
data "aws_iam_policy" "AdministratorAccess" {
  arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "crowdstrike_bootstrap_role" {
  name = "crowdstrike_bootstrap_role"

  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BoundaryForAdministratorAccess"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "crowdstrike_bootstrap_policy_attach" {
  role       = "${aws_iam_role.crowdstrike_bootstrap_role.name}"
  policy_arn = "${data.aws_iam_policy.AdministratorAccess.arn}"
}

resource "aws_iam_instance_profile" "crowdstrike_bootstrap_profile" {
  name = "crowdstrike_bootstrap_profile"
  role = aws_iam_role.crowdstrike_bootstrap_role.name
}


resource "aws_vpc" "global_vpc" {
  cidr_block = "172.17.0.0/16"
  tags = {
    Name = "Global VPC"
  }
}

resource "aws_subnet" "sn_private" {
  vpc_id     = aws_vpc.global_vpc.id
  cidr_block = "172.17.0.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "Private Subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.global_vpc.id
  tags = {
    Name = "Internet Gateway"
  }
}

resource "aws_route_table" "rt_private" {
  vpc_id = aws_vpc.global_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "Private Subnet Route Table"
  }
}

resource "aws_route_table_association" "rta_private" {
  subnet_id = aws_subnet.sn_private.id
  route_table_id = aws_route_table.rt_private.id
}

resource "aws_security_group" "sg_internal" {
  name        = "internal"
  description = "internal and ssh"
  vpc_id = aws_vpc.global_vpc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["172.17.0.0/16"]
  }   
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Internal SG"
  }
}


resource "aws_instance" "aws-linux-server" {
  count         = "1"
  ami           = data.aws_ami.amazon.id
  instance_type = "t2.small"
  key_name      = "cs-key"
  subnet_id                    = aws_subnet.sn_private.id
  iam_instance_profile = aws_iam_instance_profile.crowdstrike_bootstrap_profile.id
  associate_public_ip_address = true
  tags = {
#    Name = "AWS Linux 2 - ${count.index + 1}"
    Name = "Startup"
    ci-key-username = "ec2-user"
  }
  user_data = <<EOF
#!/bin/bash
echo "${var.CS_Env_Id}" > /tmp/environment.txt;
echo "export CS_Env_Id=${var.CS_Env_Id}" >> /etc/profile
echo "export EXT_IP=$(curl -s ipinfo.io/ip)"
echo 'echo -e "Welcome to the demo!\n\nUse the command \`start\` to begin."' >> /etc/profile
yum install -y git
cd /home/ec2-user
git clone https://github.com/CrowdStrike/cs-cnap.git
mv cs-cnap/start.sh /usr/local/bin/start
chmod +x /usr/local/bin/start
zip -r code cs-cnap/code/*
mv code.zip /cs-cnap/templates/.
EOF
}
