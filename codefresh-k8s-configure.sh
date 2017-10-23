#!/usr/bin/env bash
#
#---
echo -e "The script configures your Kubernetes cluster namespace to run codefresh.io builds \n\
Please ensure:
  - Kubernetes version is 1.6 or newer, kubectl is installed and confired to your cluster
  - You have Codefresh API Access Token - see https://g.codefresh.io/api/
  - You have Codefresh Registry Token - see https://docs.codefresh.io/v1.0/docs/codefresh-registry
  - The cluster is registred in Codefresh - see https://docs.codefresh.io/v1.0/docs/codefresh-kubernetes-integration-beta#section-add-a-kubernetes-cluster
  - Your codefresh account enabled for CustomKubernetesCluster feature"

fatal() {
   echo "ERROR: $1"
   exit 1
}

usage() {
  echo "Usage:
  $0 [ options ] cluster_name

  options:
  --api-token <codefresh api token> - default \$API_TOKEN
  --registry-token <codefresh registry token> - default \$REGISTRY_TOKEN
  --namespace <kubernetes namespace>
  --context <kubectl context>
  --image-tag <codefresh/k8s-dind-config image tag - default master>

  "
}

[[ $# == 0 || $1 == "-h" ]] && usage && exit 0

set -e

# Environment
API_HOST=${API_HOST}
[[ -z "${API_HOST}" ]] && fatal "API_HOST is not set"

while [[ $1 =~ ^(--(api-token|registry-token|namespace|context|image-tag)) ]]
do
  key=$1
  value=$2

  case $key in
    -h)
      usage
      exit 0
      ;;
    --api-token)
      API_TOKEN=$value
      shift
      ;;
    --registry-token)
      REGISTRY_TOKEN=$value
      shift
      ;;
    --context)
      KUBECTL_OPTIONS="${KUBECTL_OPTIONS} --context=$value"
      shift
      ;;
    --namespace)
      KUBECTL_OPTIONS="${KUBECTL_OPTIONS} --namespace=$value"
      shift
      ;;
    --image-tag)
      IMAGE_TAG="$value"
      shift
      ;;
  esac
done

CLUSTER_NAME="${1}"
[[ -z ${CLUSTER_NAME} ]] && usage && exit 1

if [[ -z ${API_TOKEN} ]]; then
   echo "Enter Codefresh API token: (see ${API_HOST}/api ) "
   read -r -p "    " API_TOKEN
fi

if [[ -z ${REGISTRY_TOKEN} ]]; then
   echo "Enter Codefresh Docker Registry token: (see https://docs.codefresh.io/v1.0/docs/codefresh-registry )"
   read -r -p "    " REGISTRY_TOKEN
fi

if [[ -z "${API_TOKEN}" || -z "${CLUSTER_NAME}" ]]; then
  usage
  exit 1
fi

which kubectl || fatal kubectl not found

echo -e "\nPrinting kubectl contexts:"
kubectl config get-contexts

KUBECTL="kubectl $KUBECTL_OPTIONS "

echo "We are going to start Codefresh Configuration Pod using:
   $KUBECTL -f <codefresh-config-pod>"
read -r -p "Would you like to continue? [Y/n]: " CONTINUE
CONTINUE=${CONTINUE,,} # tolower
if [[ ! $CONTINUE =~ ^(yes|y) ]]; then
  echo "Exiting ..."
  exit 0
fi

POD_NAME=codefresh-configure-$(date '+%Y-%m-%d-%H%M%S')
TMP_DIR=${TMPDIR:-/tmp}/codefresh
mkdir -p "${TMP_DIR}"
POD_DEF_FILE=${TMP_DIR}/${POD_NAME}-pod.yaml

cat <<EOF >${POD_DEF_FILE}
---
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  annotations:
    forceRedeployUniqId: "N/A"
  labels:
    app: codefresh-config
spec:
  restartPolicy: Never
  containers:
  - image: codefresh/k8s-dind-config:${IMAGE_TAG:-master}
    name: k8s-dind-config
    imagePullPolicy: Always
    command:
      - "/app/k8s-dind-config"
    env:
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: API_HOST
        value: "${API_HOST}"
      - name: API_TOKEN
        value: "${API_TOKEN}"
      - name: REGISTRY_TOKEN
        value: "${REGISTRY_TOKEN}"
      - name: CLUSTER_NAME
        value: "${CLUSTER_NAME}"
EOF


cat ${POD_DEF_FILE}

echo $KUBECTL apply -f ${POD_DEF_FILE}

