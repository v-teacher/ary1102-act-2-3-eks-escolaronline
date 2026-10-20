#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"
ACT_PROFILE="${AWS_PROFILE:-learner-lab}"
ACT_ACCOUNT=$(aws sts get-caller-identity --profile "$ACT_PROFILE" --query Account --output text)
ACT_REGISTRY="$ACT_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com"
aws ecr get-login-password --profile "$ACT_PROFILE" --region us-east-1 | docker login --username AWS --password-stdin "$ACT_REGISTRY"
for ACT_SERVICE in frontend get-products create-product update-product delete-product; do
  docker tag "ary1102-act23-$ACT_SERVICE:validation" "$ACT_REGISTRY/ary1102-act23-$ACT_SERVICE:validation"
  docker push "$ACT_REGISTRY/ary1102-act23-$ACT_SERVICE:validation"
done
