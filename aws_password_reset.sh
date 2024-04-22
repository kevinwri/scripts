#!/bin/bash

# This script is designed to reset AWS IAM accounts using AWS-SSO and 1password command line applications.
# It assumes that you have configured 'op' and 'aws sso' prior to running the first time.
# If you are porting this to another origanization, change the ItemURL and Vault Name variables
# This script also assumed you have a tag on each AWS account for email

VaultName="Password Resets"
ItemBaseTitle="AWS Temporary Password"
ItemURL="https://PLACEHOLDER.signin.aws.amazon.com/console"

# Check for correct number of arguments
if [ $# -ne 2 ]; then
  echo "Usage: ./aws_password_reset.sh --username <AWS username>"
  exit 1
fi

# Parse arguments
while [ $# -gt 0 ]; do
  key="${1}"
  case ${key} in
      --username)
      username="${2}"


      # Validate the input username
      if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
          echo "Error: Username must contain only alphanumeric characters"
          exit 1
      fi


      shift
      shift
      ;;
      *)
      shift
      ;;
  esac
done

# Check that required commands are available
if ! command -v aws &> /dev/null; then
  echo "Error: aws CLI is not installed"
  exit 1
fi

if ! command -v op &> /dev/null; then
  echo "Error: 1Password CLI (op) is not installed"
  exit 1
fi

# Check to see if we are logged into 1Password, if not authenticate
op account get > /dev/null 2>&1 
if [ $? -ne 0 ]; then
  echo "Please sign into 1Password:"
  eval $(op signin)
  if [ $? -ne 0 ]; then
    exit 1
  fi
fi

# Check to see if we are logged into AWS
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Please sign into AWS"
  aws sso login
  if [ $? -ne 0 ]; then
    exit 1
  fi
fi

# Get user email from AWS
user_info_json=$(aws iam get-user --user-name "$username" )
if [ $? -ne 0 ]; then
  echo "Error: Failed to get AWS user info for $username. Do they exist?"
  exit 1
fi

email=$(echo $user_info_json | jq -r '.User.Tags[] | select(.Key=="email") | .Value')

if [ -z "$email" ]; then
  echo "Error: Failed to get email tag from AWS for $username"
  exit 1
fi

# Create new item title 
today=$(date +%Y-%m-%d)
NewItemTitle="$ItemBaseTitle - $username - $today"

# Check for an existing item from today
op item get "$NewItemTitle" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "AWS Temporary Password for today already exists"
  exit 0
fi

# Create 1Password item
op item create --category=login --vault="$VaultName" --title="$NewItemTitle" --url $ItemURL username="$username" --generate-password=20,letters,digits,symbols > /dev/null

if [ $? -ne 0 ]; then
  echo "Error: Failed to create 1Password item"
  exit 1
fi

# Extract password from created 1Password item
password=$(op read op://"$VaultName"/"$NewItemTitle"/password)

if [ -z "$password" ]; then
  echo "Error: Failed to get generated password from 1Password"
  exit 1
fi


# Update AWS login profile with new password
aws iam update-login-profile --user-name "$username" --password "$password" --password-reset-required

if [ $? -eq 0 ]; then
  echo "Success: Password reset for user $username"
  SharingLink=$(op item share "$NewItemTitle" --vault "Password Resets" --emails $email)
  echo "Sharing with $email"
  echo $SharingLink
else
  echo "Error: Failed to reset password for user $username"
  exit 1
fi
