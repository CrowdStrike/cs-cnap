#!/bin/bash
source .bashrc

STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION --query 'Stacks[].StackStatus')
STATUS_REASON=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION --query 'Stacks[].StackStatusReason')

if [[ $STATUS == *"CREATE_COMPLETE"* ]]; then
  echo -e "\nStack deployment complete!  Please run"
  echo -e "\nconfigure\n"
elif  [[ $STATUS == *"CREATE_FAILED"* ]]; then
  echo -e "\n$STATUS"
  echo -e "\n $STATUS_REASON"
else
  echo -e "\n$STATUS\n"
fi