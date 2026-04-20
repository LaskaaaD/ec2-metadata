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