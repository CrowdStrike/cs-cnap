DG="\033[1;30m"
RD="\033[0;31m"
NC="\033[0;0m"
LB="\033[1;34m"
env_up(){
   EnvHash=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 6)
   S3Bucket=cnap-${EnvHash}
   AWS_REGION='us-west-2'
   S3Prefix='templates'
   StackName='cwp-demo-stack'
   TemplateName='entry.yaml'

   echo -e "$LB\n"
   echo -e "Welcome to CNAP$NC"
   echo -e "$LB\n"
   echo -e "You will asked to provide a Falcon API Key Client ID and Secret." 
   echo -e "You can create one at https://falcon.crowdstrike.com/support/api-clients-and-keys"
   echo -e "$LB\n"
   echo -e "The ev Days Workshop environment requires the following API Scope permissions:"
   echo -e " - AWS Accounts:R"
   echo -e " - CSPM registration:R/W"
   echo -e " - CSPM remediation:R/W"
   echo -e " - Customer IOA rules:R/W"
   echo -e " - Hosts:R"
   echo -e " - Falcon Container Image:R/W"
   echo -e " - Falcon Images Download:R"
   echo -e " - Kubernetes Protection Agent:W"
   echo -e " - Sensor Download:R"
   echo -e " - Event streams:R"
   read -p "Enter your Falcon API Key Client ID: " CLIENT_ID
   read -p "Enter your Falcon API Key Client Secret: " CLIENT_SECRET
   echo -e "For the next variable (Falcon CID), use the entire string include the 2-character hash which you can find at https://falcon.crowdstrike.com/hosts/sensor-downloads"
   read -p "Enter your Falcon CID: " CS_CID
   read -p "Enter your Falcon Cloud [us-1]: " CS_CLOUD
   CS_CLOUD=${CS_CLOUD:-us-1}
   echo -e "Enter an existing key-pair in us-west-2 for connecting to EC2 instances. You can create one at https://us-west-2.console.aws.amazon.com/ec2#KeyPairs:"
   read -p "Enter your EC2 key-pair name [cs-key]: " KeyPairName
   KeyPairName=${KeyPairName:-cs-key}

   aws s3api create-bucket --bucket $S3Bucket --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
   
   cd cs-cnap/templates
   aws s3 cp . s3://${S3Bucket} --recursive 
   echo -e "$LB\n"
   echo -e "Standing up environment...$NC"

   aws cloudformation create-stack \
   --stack-name $StackName \
   --template-url https://${S3Bucket}.s3.amazonaws.com/${TemplateName} \
   --region $AWS_REGION \
   --disable-rollback \
   --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
   --parameters \
   ParameterKey=S3Bucket,ParameterValue=${S3Bucket} \
   ParameterKey=KeyPairName,ParameterValue=${KeyPairName} \
   ParameterKey=FalconClientID,ParameterValue=$CLIENT_ID \
   ParameterKey=FalconClientSecret,ParameterValue=$CLIENT_SECRET \
   ParameterKey=CrowdStrikeCloud,ParameterValue=$CS_CLOUD \
   ParameterKey=FalconCID,ParameterValue=$CS_CID

    echo -e "The Cloudformation stack will take 20-30 minutes to complete.$NC"
    echo -e "\n\nCheck the status at any time with the command \n\naws cloudformation describe-stacks --stack-name devdays-cnap-stack --region $AWS_REGION$NC\n\n"
}
env_up
