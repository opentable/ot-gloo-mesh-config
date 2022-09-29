export MGMT_CONTEXT=$USER-test-ci-rs
export GLOO_VERSION=2.0.23

kubectl config use-context $USER-sp-ci-rs

export ENDPOINT_GLOO_MESH=k8s-node-test-ci-rs-01.test.com:$(kubectl --context=$MGMT_CONTEXT -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.spec.ports[1].nodePort}')
export HOST_GLOO_MESH=$(echo ${ENDPOINT_GLOO_MESH} | cut -d: -f1)

echo "Gloo mesh endpoint: $ENDPOINT_GLOO_MESH"
echo "Gloo mesh host: $HOST_GLOO_MESH"

helm repo add gloo-mesh-enterprise https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-enterprise
helm repo add gloo-mesh-agent https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-agent
helm repo update

kubectl create namespace gloo-mesh
kubectl label ns gloo-mesh skip-docker-review=yes

# Transfer cert
kubectl get secret relay-root-tls-secret -n gloo-mesh --context=$MGMT_CONTEXT -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
kubectl create secret generic relay-root-tls-secret -n gloo-mesh --from-file ca.crt=ca.crt
rm ca.crt

# Transfer token
kubectl get secret relay-identity-token-secret -n gloo-mesh --context=$MGMT_CONTEXT -o jsonpath='{.data.token}' | base64 -d > token
kubectl create secret generic relay-identity-token-secret -n gloo-mesh --from-file token=token
rm token

helm upgrade --install gloo-mesh-agent gloo-mesh-agent/gloo-mesh-agent \
  --namespace gloo-mesh \
  --set relay.serverAddress=${ENDPOINT_GLOO_MESH} \
  --set relay.authority=gloo-mesh-mgmt-server.gloo-mesh \
  --set rate-limiter.enabled=false \
  --set ext-auth-service.enabled=false \
  --set cluster=sp-ci-rs \
  --version ${GLOO_VERSION} \
  --wait

# Register cluster in management
kubectl --context=$MGMT_CONTEXT apply -f sp-ci-rs.yaml

# Assign region
kubectl label nodes --all topology.kubernetes.io/region=qa-rs