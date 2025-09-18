#!/usr/bin/env bash
set -e -o pipefail

declare CONTAINER_RUNTIME CLUSTER_CONFIG SKIP_KNATIVE_INSTALL REGISTRY_NAME REGISTRY_PORT

info() {
  echo -e "[\e[93mINFO\e[0m] $1"
}

wait_crds() {
  info "Waiting for CRDs to be established..."
  kubectl wait --for=condition=Established --all crd
}

wait_pods() {
  info "Waiting for pods in $1 to be ready..."
  kubectl wait pod --timeout=10m --for=condition=Ready -l '!job-name' -n $1
}

check_defaults() {
  info "Check and defaults input params..."
  export KIND_CLUSTER_NAME=${CLUSTER_NAME:-"knative"}

  if [ -z "$CONTAINER_RUNTIME" ]; then
    CONTAINER_RUNTIME="docker"
  fi
  info "Using container runtime: $CONTAINER_RUNTIME"

  if [ -z "$CLUSTER_CONFIG" ]; then
    CLUSTER_CONFIG="cluster/one-node-cluster.yaml"
  fi
  info "Using cluster config: $CLUSTER_CONFIG"

  if [ -z "$REGISTRY_NAME" ]; then
    REGISTRY_NAME='kind-registry'
  fi

  if [ -z "$REGISTRY_PORT" ]; then
    REGISTRY_PORT='5000'
  fi
  info "Using registry: $REGISTRY_NAME:$REGISTRY_PORT"
}

create_registry() {
  info "Checking if registry exists..."
  local running="$(${CONTAINER_RUNTIME} inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null || true)"
  if [ "${running}" = 'true' ]; then
    info "Registry exists..."
    return 0
  fi

  info "Registry does not exist, creating..."
  "$CONTAINER_RUNTIME" rm "${REGISTRY_NAME}" 2>/dev/null || true
  "$CONTAINER_RUNTIME" run \
    -d \
    --restart=always \
    -p "${REGISTRY_PORT}:5000" \
    --name "${REGISTRY_NAME}" \
    registry:2
  info "Registry started..."
}

  fi
}

load_config() {
  local config
  config=$(sed "s/\${reg_name}/${REGISTRY_NAME}/g; s/\${reg_port}/${REGISTRY_PORT}/g" "$CLUSTER_CONFIG")
  echo "$config"
}

create_cluster() {
  info "Checking if cluster exists..."
  local running_cluster=$(kind get clusters | grep "$KIND_CLUSTER_NAME" || true)
  if [ "${running_cluster}" != "$KIND_CLUSTER_NAME" ]; then
    info "Cluster exists..."
    return 0
  fi

  info "Cluster does not exist, creating with the local registry enabled in containerd..."
  kind create cluster --config=<(load_config)
  info "Waiting for the nodes to be ready..."
  kubectl wait --for=condition=ready node --all --timeout=600s
}

connect_registry() {
  info "Check if registry is connected to the cluster network..."
  local connected_registry=$("$CONTAINER_RUNTIME" network inspect kind -f '{{json .Containers}}' | grep -q "${REGISTRY_NAME}" && echo "true" || echo "false")
  if [ "${connected_registry}" != 'true' ]; then
    info "Registry is connected..."
    return 0
  fi
  
  info "Registry is not connected, connecting the registry to the cluster network..."
  "$CONTAINER_RUNTIME" network connect "kind" "${REGISTRY_NAME}" || true
  info "Connection established..."
}

install_knative() {
  info "Checking if Knative Serving is installed in the cluster..."
  local running_knative_serving=$(kubectl get crds | grep -q "services.serving.knative.dev " && echo "true" || echo "false")
  if [ "${running_knative_serving}" != 'true' ]; then  
    info "Knative Serving is not installed, installing..."
    info "Installing Knative Serving CRDs..."
    kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.19.6/serving-crds.yaml
    wait_crds

    info "Installing Knative Serving core..."
    kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.19.6/serving-core.yaml
    wait_pods "knative-serving"

    info "Installing Kourier Ingress..."
    kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.19.5/kourier.yaml

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kourier
  namespace: kourier-system
  labels:
    networking.knative.dev/ingress-provider: kourier
spec:
  ports:
  - name: http2
    port: 80
    protocol: TCP
    targetPort: 8080
    nodePort: 31080
  - name: https
    port: 443
    protocol: TCP
    targetPort: 8443
    nodePort: 31443
  selector:
    app: 3scale-kourier-gateway
  type: NodePort
EOF

    info "Waiting for Knative Ingress - Kourier to become ready..."
    wait_pods "kourier-system"

    info "Setting up Kourier as default ingress gateway..."
    kubectl patch configmap/config-network -n knative-serving --type merge -p '{"data":{"ingress.class":"kourier.ingress.networking.knative.dev"}}'

    info "Configure domain to 127.0.0.1.sslip.io ..."
    kubectl patch configmap/config-domain --namespace knative-serving --type merge --patch '{"data":{"127.0.0.1.sslip.io":""}}'

    info "Finished installing Knative Serving."
  else
    info "Knative Serving is installed."
  fi

  info "Checking if Knative Eventing is installed in the cluster..."
  local running_knative_eventing=$(kubectl get crds | grep -q "brokers.eventing.knative.dev" && echo "true" || echo "false")
  if [ "${running_knative_eventing}" != 'true' ]; then  
    info "Knative Eventing is not installed, installing..."
    info "Installing Knative Eventing CRDs..."
    kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.19.4/eventing-crds.yaml
    wait_crds

    info "Installing Knative Eventing core..."
    kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.19.4/eventing-core.yaml
    wait_pods "knative-eventing"

    info "Installing in-memory channel..."
    kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.19.4/in-memory-channel.yaml
    wait_pods "knative-eventing"

    info "Installing MT-Channel broker..."
    kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.19.4/mt-channel-broker.yaml
    wait_pods "knative-eventing"

    cat <<EOF | kubectl apply -f -
apiVersion: eventing.knative.dev/v1
kind: broker
metadata:
  name: example-broker
  namespace: default
EOF

    info "Example broker installed..."
    info "Finished installing Knative Eventing."
  else
    info "Knative Eventing is installed."
  fi

  info "Knative setup completed!"
}

while getopts ":c:p:t:d:s" opt; do
  case ${opt} in
  c)
    CLUSTER_NAME=$OPTARG
    ;;
  s)
    SKIP_KNATIVE_INSTALL=true
    ;;
  \?)
    echo "Invalid option: $OPTARG" 1>&2
    echo 1>&2
    echo "Usage: kn8.sh [-c cluster-name]"
    ;;
  :)
    echo "Invalid option: $OPTARG requires an argument" 1>&2
    ;;
  esac
done
shift $((OPTIND - 1))

check_defaults
create_registry
create_cluster
connect_registry

if [ -z "$SKIP_KNATIVE_INSTALL" ]; then 
  install_knative
else
  info "Skipping Knative installation..."
fi
