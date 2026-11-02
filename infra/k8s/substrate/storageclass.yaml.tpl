apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: substrate-poc-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  tagSpecification_1: "Project=${POC_PROJECT_NAME}"
  tagSpecification_2: "Purpose=substrate-poc"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: false
