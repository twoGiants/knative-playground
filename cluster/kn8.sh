#!/usr/bin/env bash
set -e -o pipefail

declare CLUSTER_CONFIG SKIP_KNATIVE_INSTALL

info() {
  echo -e "[\e[93mINFO\e[0m] $1"
}

check_defaults() {
  info "Check and defaults input params..."
  export KIND_CLUSTER_NAME=${CLUSTER_NAME:-"knative"}

  if [ -z "$CONTAINER_RUNTIME" ]; then
    CONTAINER_RUNTIME="docker"
  fi

  if [ -z "$CLUSTER_CONFIG" ]; then
    CLUSTER_CONFIG="cluster/one-node-cluster.yaml"
  fi

  info "Using container runtime: $CONTAINER_RUNTIME"
}

create_registry() {
  info "Checking if registry exists..."
  reg_name='kind-registry'
  reg_port='5000'
  running="$(${CONTAINER_RUNTIME} inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
  if [ "${running}" != 'true' ]; then
    info "Registry does not exist, creating..."
    "$CONTAINER_RUNTIME" rm "${reg_name}" 2>/dev/null || true
    "$CONTAINER_RUNTIME" run \
      -d \
      --restart=always \
      -p "${reg_port}:5000" \
      --name "${reg_name}" \
      registry:2
    info "Registry started..."
  else
    info "Registry exists..."
  fi
}

load_config() {
  local config
  config=$(sed "s/\${reg_name}/${reg_name}/g; s/\${reg_port}/${reg_port}/g" "$CLUSTER_CONFIG")
  echo "$config"
}

create_cluster() {
  info "Checking if cluster exists..."
  running_cluster=$(kind get clusters | grep "$KIND_CLUSTER_NAME" || true)
  if [ "${running_cluster}" != "$KIND_CLUSTER_NAME" ]; then
    info "Cluster does not exist, creating with the local registry enabled in containerd..."
    kind create cluster --config=<(load_config)
    info "Waiting for the nodes to be ready..."
    kubectl wait --for=condition=ready node --all --timeout=600s
  else
    info "Cluster exists..."
  fi
}

connect_registry() {
  info "Check if registry is connected to the cluster network..."
  connected_registry=$("$CONTAINER_RUNTIME" network inspect kind -f '{{json .Containers}}' | grep -q "${reg_name}" && echo "true" || echo "false")
  if [ "${connected_registry}" != 'true' ]; then
    info "Registry is not connected, connecting the registry to the cluster network..."
    "$CONTAINER_RUNTIME" network connect "kind" "${reg_name}" || true
    info "Connection established..."
  else
    info "Registry is connected..."
  fi
}

install_knative() {
  info "Checking if Knative Serving is installed in the cluster..."
  running_knative_serving=$(kubectl get crds | grep -q "services.serving.knative.dev " && echo "true" || echo "false")
  if [ "${running_knative_serving}" != 'true' ]; then  
    info "Knative Serving is not installed, installing ..."
    kubectl apply -f https://storage.googleapis.com/knative-nightly/serving/latest/serving-crds.yaml
    kubectl apply -f https://storage.googleapis.com/knative-nightly/serving/latest/serving-core.yaml

    info "Waiting for Knative Serving to become ready"
    sleep 5; while echo && kubectl get pods -n knative-serving | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

    info "Setting up Kourier"
    kubectl apply -f https://storage.googleapis.com/knative-nightly/net-kourier/latest/kourier.yaml

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

    info "Waiting for Knative Ingress - Kourier to become ready"
    sleep 5; while echo && kubectl get pods -n kourier-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

    info "Setting up Kourier as default ingress gateway"
    kubectl patch configmap/config-network -n knative-serving --type merge -p '{"data":{"ingress.class":"kourier.ingress.networking.knative.dev"}}'

    info "Configure domain to 127.0.0.1.sslip.io"
    kubectl patch configmap/config-domain --namespace knative-serving --type merge --patch '{"data":{"127.0.0.1.sslip.io":""}}'
  else
    info "Knative Serving is installed..."
  fi

  info "Checking if Knative Eventing is installed in the cluster..."
  running_knative_eventing=$(kubectl get crds | grep -q "brokers.eventing.knative.dev" && echo "true" || echo "false")
  if [ "${running_knative_eventing}" != 'true' ]; then  
    info "Knative Eventing is not installed, installing ..."
    kubectl apply --selector knative.dev/crd-install=true --filename https://storage.googleapis.com/knative-nightly/eventing/latest/eventing.yaml
    sleep 5
    kubectl apply --filename https://storage.googleapis.com/knative-nightly/eventing/latest/eventing.yaml

    info "Waiting for Knative Eventing to become ready"
    sleep 5; while echo && kubectl get pods -n knative-eventing | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
  else
    info "Knative Eventing is installed..."
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
