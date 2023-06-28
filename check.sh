#!/bin/bash

status=$(aws cloudformation describe-stacks --stack-name cwp-demo-stack --region us-east-2 --query 'Stacks[].StackStatus')

if [[ $status == *"CREATE_COMPLETE"* ]]; then
  echo "Stack deployment complete!  Please run configure"
else
  echo "Not complete, stack status: "
  echo $status
fi