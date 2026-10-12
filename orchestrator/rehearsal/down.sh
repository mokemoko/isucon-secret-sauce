#!/usr/bin/env bash
# up.sh で作ったリソースを tag Project=isucon-rehearsal で探して全て削除し、残っていないことを確認する
set -euo pipefail
TAG=isucon-rehearsal
DIR=${DIR:-$HOME/isucon/rehearsal}
f=Name=tag:Project,Values=$TAG

ids=$(aws ec2 describe-instances --filters $f Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$ids" ]; then
  aws ec2 terminate-instances --instance-ids $ids >/dev/null
  echo "terminate 待ち: $ids" >&2
  aws ec2 wait instance-terminated --instance-ids $ids
fi
for v in $(aws ec2 describe-volumes --filters $f Name=status,Values=available --query 'Volumes[].VolumeId' --output text); do
  aws ec2 delete-volume --volume-id $v
done
for g in $(aws ec2 describe-security-groups --filters $f --query 'SecurityGroups[].GroupId' --output text); do
  aws ec2 delete-security-group --group-id $g
done
aws ec2 describe-key-pairs --filters $f --query 'KeyPairs[].KeyName' --output text | grep -q . && aws ec2 delete-key-pair --key-name $TAG
rm -rf "$DIR"

# 残存確認 (terminated 以外のインスタンス、ボリューム、SG、鍵)
left=$(
  aws ec2 describe-instances --filters $f Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down --query 'Reservations[].Instances[].InstanceId' --output text
  aws ec2 describe-volumes --filters $f --query 'Volumes[].VolumeId' --output text
  aws ec2 describe-security-groups --filters $f --query 'SecurityGroups[].GroupId' --output text
  aws ec2 describe-key-pairs --filters $f --query 'KeyPairs[].KeyName' --output text
)
if [ -n "$(echo $left)" ]; then echo "残存リソースあり: $left" >&2; exit 1; fi
echo "clean: $TAG のリソースは残っていません"
