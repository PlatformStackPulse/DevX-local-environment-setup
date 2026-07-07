#!/usr/bin/env bash
set -euo pipefail

awslocal s3 mb s3://devx-local-assets || true

awslocal sqs create-queue \
  --queue-name devx-local-events || true

awslocal sns create-topic \
  --name devx-local-topic || true

awslocal dynamodb create-table \
  --table-name devx-local \
  --attribute-definitions \
  AttributeName=PK,AttributeType=S \
  AttributeName=SK,AttributeType=S \
  --key-schema \
  AttributeName=PK,KeyType=HASH \
  AttributeName=SK,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST || true

echo "LocalStack baseline resources are ready."
