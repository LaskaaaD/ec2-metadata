# EC2 Metadata Reporter

Collects EC2 instance metadata via IMDSv2 and uploads report to S3.

## Usage
./ec2-metadata.sh [--bucket s3://bucket/prefix] [--output /path/to/file.txt]

## Requirements
- AWS CLI v2
- IAM instance role with s3:PutObject (preferred) or configured credentials

## Collected data
- Instance ID, Public IP, Private IP
- Security Groups
- Operating System (from /etc/os-release)
- Users with bash/sh shells

## Example output
Instance ID:      i-0123456789abcdef0
Public IP:        1.2.3.4
Private IP:       172.31.0.1
Security Groups:  my-security-group
Operating System: Ubuntu 24.04.4 LTS
Users (bash/sh):  root,ubuntu