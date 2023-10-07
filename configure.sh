#!/bin/bash
function setup_environment_variables() {
    #TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    #REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/placement/availability-zone/)
    REGION=$(curl -sq http://169.254.169.254/latest/meta-data/placement/availability-zone/)
    REGION=${REGION: :-1}
    ACCOUNT_ID=$(aws sts get-caller-identity | jq -r .Account)
    CLUSTER_CA_DATA=$(aws ssm get-parameter --region ca-central-1 --name cnap-eks-ca-data --query 'Parameter.Value' | sed 's/"//' | sed 's/"//')
    CLUSTER_ARN=$(aws ssm get-parameter --region ca-central-1 --name cnap-eks-arn --query 'Parameter.Value' | sed 's/"//' | sed 's/"//')
    CLUSTER_NAME=$(aws ssm get-parameter --region ca-central-1 --name cnap-eks-name --query 'Parameter.Value' | sed 's/"//' | sed 's/"//')
    CLUSTER_ENDPOINT=$(aws ssm get-parameter --region ca-central-1 --name cnap-eks-endpoint --query 'Parameter.Value' | sed 's/"//' | sed 's/"//')
    LB_ROLE_ARN=$(aws ssm get-parameter --region ca-central-1 --name cnap-lb-role-arn --query 'Parameter.Value' | sed 's/"//' | sed 's/"//')
    CP_ROLE_ARN=$(aws ssm get-parameter --region ca-central-1 --name cnap-cp-role-arn --query 'Parameter.Value' | sed 's/"//' | sed 's/"//')
}

function install_kubernetes_client_tools() {
    printf "\nInstall K8s Client Tools"
    mkdir -p /usr/local/bin/
    curl --retry 5 -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.24.13/2023-05-11/bin/linux/amd64/kubectl
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
}

function setup_kubeconfig() {
    mkdir -p /home/ec2-user/.kube
    source /root/.bashrc
    cat > /home/ec2-user/.kube/config <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA_DATA}
    server: ${CLUSTER_ENDPOINT}
  name: ${CLUSTER_ARN}
contexts:
- context:
    cluster: ${CLUSTER_ARN}
    user: ${CLUSTER_ARN}
  name: ${CLUSTER_ARN}
current-context: ${CLUSTER_ARN}
kind: Config
preferences: {}
users:
- name: ${CLUSTER_ARN}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
        - --region
        - ${REGION}
        - eks
        - get-token
        - --cluster-name
        - ${CLUSTER_NAME}
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
  echo LB Controller Role ARN is ${LB_ROLE_ARN}
  echo K8s Cluster Name is ${CLUSTER_NAME}
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
    eks.amazonaws.com/role-arn: ${LB_ROLE_ARN}
    
EOF
  kubectl apply -f aws-load-balancer-controller-service-account.yaml --kubeconfig=/home/ec2-user/.kube/config
  helm repo add eks https://aws.github.io/eks-charts && helm repo update
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --kubeconfig /home/ec2-user/.kube/config \
  -n kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
  # Verify 2/2 running with with kubectl get deployment -n kube-system aws-load-balancer-controller
}

function setup_eksctl {
  ARCH=amd64
  PLATFORM=$(uname -s)_$ARCH
  curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
  curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
  tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
  sudo mv /tmp/eksctl /usr/local/bin
}

function add_code_pipeline_role {
  eksctl create iamidentitymapping --cluster $CLUSTER_NAME --region=$REGION \
  --arn $CP_ROLE_ARN --username cp-admin --group system:masters \
  --no-duplicate-arns
}

setup_environment_variables
install_kubernetes_client_tools
setup_kubeconfig
deploy_load_balancer
setup_eksctl
add_code_pipeline_role