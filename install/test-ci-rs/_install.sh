export GLOO_MESH_LICENSE_KEY="SECRET"
export GLOO_VERSION=2.0.23


kubectl config use-context $USER-test-ci-rs

helm repo add gloo-mesh-enterprise https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-enterprise
helm repo add gloo-mesh-agent https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-agent
helm repo update

kubectl create namespace gloo-mesh
kubectl label ns gloo-mesh skip-docker-review=yes

helm upgrade --install gloo-mesh-enterprise gloo-mesh-enterprise/gloo-mesh-enterprise \
--namespace gloo-mesh \
--version=${GLOO_VERSION} \
--set licenseKey=${GLOO_MESH_LICENSE_KEY} \
-f gloo-mesh.helm.yaml \
--wait


kubectl -n gloo-mesh rollout status deploy/gloo-mesh-mgmt-server

export ENDPOINT_GLOO_MESH=k8s-node-test-ci-rs-01.test.com:$(kubectl -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.spec.ports[1].nodePort}')
export HOST_GLOO_MESH=$(echo ${ENDPOINT_GLOO_MESH} | cut -d: -f1)

echo "Gloo mesh endpoint: $ENDPOINT_GLOO_MESH"
echo "Gloo mesh host: $HOST_GLOO_MESH"

kubectl apply -f test-ci-rs.yaml

helm upgrade --install gloo-mesh-agent gloo-mesh-agent/gloo-mesh-agent \
  --namespace gloo-mesh \
  --set relay.serverAddress=${ENDPOINT_GLOO_MESH} \
  --set relay.authority=gloo-mesh-mgmt-server.gloo-mesh \
  --set rate-limiter.enabled=false \
  --set ext-auth-service.enabled=false \
  --set cluster=test-ci-rs \
  --version ${GLOO_VERSION} \
  --wait

kubectl apply -f ./gloo-mesh-ui-service.yaml
kubectl --namespace ot create service externalname gloo --external-name gloo-mesh-ui-service.gloo-mesh.svc.test-ci-rs

# Register e-w gateway
kubectl apply -f global-workspace.yaml

# Assign region
kubectl label nodes --all topology.kubernetes.io/region=qa-rs