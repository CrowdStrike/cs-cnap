#!/bin/bash

STATUS=$(aws cloudformation describe-stacks --stack-name cwp-demo-stack --region us-east-2 --query 'Stacks[].StackStatus')
STATUS_REASON=$(aws cloudformation describe-stacks --stack-name cwp-demo-stack --region us-east-2 --query 'Stacks[].StackStatusReason')

if [[ $STATUS == *"CREATE_COMPLETE"* ]]; then
  echo ""
  echo "Stack deployment complete!  Please run configure"
  echo ""
elif  [[ $STATUS == *"CREATE_FAILED"* ]]; then
  echo ""
  echo $STATUS
  echo ""
  echo $STATUS_REASON
  echo ""
else
  echo ""
  echo "Not complete, stack status:"
  echo $STATUS
  echo ""
fi