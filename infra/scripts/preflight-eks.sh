#!/usr/bin/env bash
set -euo pipefail
region="${POC_AWS_REGION:-}"
project="${POC_PROJECT_NAME:-substrate-poc}"
[[ -n "$region" && "$project" =~ ^[a-z][a-z0-9-]{2,30}$ ]] || { printf 'Configurar región y proyecto válidos\n' >&2; exit 2; }
for binary in aws node; do command -v "$binary" >/dev/null || { printf 'Falta %s\n' "$binary" >&2; exit 2; }; done
aws sts get-caller-identity --region "$region" >/dev/null
versions="$(aws eks describe-cluster-versions --region "$region" --cluster-versions 1.37 --output json)"
printf '%s' "$versions" | node -e '
let raw="";process.stdin.on("data",x=>raw+=x).on("end",()=>{
 const versions=JSON.parse(raw).clusterVersions||[];
 if(!versions.some(v=>v.clusterVersion==="1.37" && v.versionStatus==="STANDARD_SUPPORT")){
  console.error("EKS 1.37 no está en soporte estándar en la región");process.exit(1)
 }
})'
aws eks describe-addon-versions --region "$region" --kubernetes-version 1.37 --addon-name aws-ebs-csi-driver --query 'addons[0].addonVersions[0].addonVersion' --output text | node -e '
let raw="";process.stdin.on("data",x=>raw+=x).on("end",()=>{if(!raw.trim()||raw.trim()==="None")process.exit(1)})'
existing="$(aws eks list-clusters --region "$region" --query "length(clusters[?@=='$project'])" --output text)"
[[ "$existing" == 0 ]] || { printf 'Ya existe el clúster %s; revisar estado antes de aplicar\n' "$project" >&2; exit 1; }
offering="$(aws ec2 describe-instance-type-offerings --region "$region" --location-type availability-zone --filters Name=instance-type,Values=t3a.xlarge --query 'length(InstanceTypeOfferings)' --output text)"
[[ "$offering" =~ ^[0-9]+$ ]] && (( offering >= 2 )) || { printf 't3a.xlarge no aparece en dos AZ de %s\n' "$region" >&2; exit 1; }
quota="$(aws service-quotas get-service-quota --region "$region" --service-code ec2 --quota-code L-1216C47A --query 'Quota.Value' --output text)"
node -e 'const q=Number(process.argv[1]);if(!Number.isFinite(q)||q<4)process.exit(1)' "$quota" || { printf 'Cuota On-Demand Standard menor a 4 vCPU\n' >&2; exit 1; }
instances="$(aws ec2 describe-instances --region "$region" --filters Name=instance-state-name,Values=pending,running --output json)"
printf '%s' "$instances" | node -e '
let raw="";process.stdin.on("data",x=>raw+=x).on("end",()=>{
 const quota=Number(process.argv[1]);const data=JSON.parse(raw);
 const instances=(data.Reservations||[]).flatMap(r=>r.Instances||[]);
 let used=0;
 for(const instance of instances){
  const cpu=instance.CpuOptions;
  if(!cpu||!Number.isFinite(cpu.CoreCount)||!Number.isFinite(cpu.ThreadsPerCore)){
   console.error("No se pudo calcular vCPU en uso");process.exit(1)
  }
  used+=cpu.CoreCount*cpu.ThreadsPerCore;
 }
 if(quota-used<4){console.error(`Cuota vCPU insuficiente: ${used}/${quota} en uso`);process.exit(1)}
})' "$quota"
printf 'PASS: EKS 1.37, EBS CSI, t3a.xlarge y al menos 4 vCPU disponibles en %s.\n' "$region"
