function setup_environment_variables() {
    region=$(curl -sq http://169.254.169.254/latest/meta-data/placement/availability-zone/)
    region=${region: :-1}
    accountId=$(aws sts get-caller-identity | jq -r .Account)
}

function install_kubernetes_client_tools() {
    printf "\nInstall K8s Client Tools"
    mkdir -p /usr/local/bin/
    curl --retry 5 -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.23.13/2022-10-31/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mv ./kubectl /usr/local/bin/
    mkdir -p /root/bin
    ln -s /usr/local/bin/kubectl /root/bin/
    ln -s /usr/local/bin/kubectl /opt/aws/bin
#!/bin/bash
source <(/usr/local/bin/kubectl completion bash)
EOF
    chmod +x /etc/profile.d/kubectl.sh
    curl --retry 5 -o helm.tar.gz https://get.helm.sh/helm-v3.10.3-linux-amd64.tar.gz
    tar -xvf helm.tar.gz
    chmod +x ./linux-amd64/helm
    mv ./linux-amd64/helm /usr/local/bin/helm
    ln -s /usr/local/bin/helm /opt/aws/bin
    rm -rf ./linux-amd64/
# Install awscli v2
    curl -O "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -o awscli-exe-linux-x86_64.zip
    sudo ./aws/install
    rm awscli-exe-linux-x86_64.zip
    mv /bin/aws /bin/aws.v1
    ln -s /usr/local/aws-cli/v2/current/dist/aws /bin/aws
}

function setup_kubeconfig() {
    clusterArn="arn:aws:eks:$region:$accountId:cluster/$K8S_CLUSTER_NAME"
    mkdir -p /home/ec2-user/.kube
    source /root/.bashrc
    cat > /home/ec2-user/.kube/config <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${K8S_CA_DATA}
    server: ${K8S_ENDPOINT}
  name: ${clusterArn}
contexts:
- context:
    cluster: ${clusterArn}
    user: ${clusterArn}
  name: ${clusterArn}
current-context: ${clusterArn}
kind: Config
preferences: {}
users:
- name: ${clusterArn}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
        - --region
        - ${region}
        - eks
        - get-token
        - --cluster-name
        - ${K8S_CLUSTER_NAME}
EOF
    printf "\nKube Config:\n"
    cat /home/ec2-user/.kube/config
    mkdir -p /root/.kube/
    cp /home/ec2-user/.kube/config /root/.kube/
    chown -R ec2-user:${user_group} /home/ec2-user/.kube/
    # Add SSM Config for ssm-user
    /sbin/useradd -d /home/ssm-user -u 1001 -s /bin/bash -m --user-group ssm-user
    mkdir -p /home/ssm-user/.kube/
    cp /home/ec2-user/.kube/config /home/ssm-user/.kube/config
    chown -R ssm-user:ssm-user /home/ssm-user/
    chmod -R og-rwx /home/ssm-user/.kube
}

function deploy_load_balancer(){
  echo LB Controller Role ARN is ${LoadBalancerControllerIAMRoleArn}
  echo K8s Cluster Name is ${K8S_CLUSTER_NAME}
  cat >aws-load-balancer-controller-service-account.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${LoadBalancerControllerIAMRoleArn}
    
EOF
  kubectl apply -f aws-load-balancer-controller-service-account.yaml --kubeconfig=/home/ec2-user/.kube/config

  helm repo add eks https://aws.github.io/eks-charts && helm repo update
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --kubeconfig /home/ec2-user/.kube/config \
  -n kube-system \
  --set clusterName=${K8S_CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
  # Verify 2/2 running with with kubectl get deployment -n kube-system aws-load-balancer-controller
}

setup_environment_variables
install_kubernetes_client_tools
setup_kubeconfig
deploy_load_balancer