export GLOO_VERSION=2.1.0
export GLOO_MESH_LICENSE_KEY="eyJhZGRPbnMiOiIiLCJleHAiOjE2Njg1NTY4MDAsImlhdCI6MTY2NTk2NDgwMCwiayI6IlJxd085dyIsImx0IjoidHJpYWwiLCJwcm9kdWN0IjoiZ2xvby1tZXNoIn0.38eF4YgI7-TKgDAoxhN05jTwVYnvqWgIK1vzCUDLluo"

kind delete cluster --name test-ci-rs
kind delete cluster --name sp-ci-rs

kind create cluster --name test-ci-rs --config test-ci-rs-kind.yaml
kind create cluster --name sp-ci-rs --config sp-ci-rs-kind.yaml

docker network inspect -f '{{.IPAM.Config}}' kind

kubectl config use-context kind-test-ci-rs
kubectl create namespace istio-system
kubectl label ns istio-system skip-docker-review=yes
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.14/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.14/samples/addons/grafana.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.14/samples/addons/kiali.yaml
kubectl rollout status deployment prometheus -n istio-system
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

helm upgrade --install istio-base istio/base -n istio-system --version 1.15.1 --wait
kubectl label ns istio-system topology.istio.io/network=test-ci-rs-network
helm upgrade --install istiod istio/istiod -n istio-system -f istiod-test-ci-rs.yaml  --version 1.15.1 --wait
#helm upgrade --install --namespace istio-system --create-namespace istio-ingressgateway istio/gateway -f ingress-test-ci-rs.yaml  --wait
helm upgrade --install --namespace istio-system --create-namespace istio-eastwestgateway istio/gateway -f eastwest-test-ci-rs.yaml --version 1.15.1  --wait


kubectl config use-context kind-sp-ci-rs
kubectl create namespace istio-system
kubectl label ns istio-system skip-docker-review=yes
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.14/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.14/samples/addons/grafana.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.14/samples/addons/kiali.yaml
kubectl rollout status deployment prometheus -n istio-system

helm upgrade --install istio-base istio/base -n istio-system --version 1.15.1 --wait
kubectl label ns istio-system topology.istio.io/network=sp-ci-rs-network
helm upgrade --install istiod istio/istiod -n istio-system -f istiod-sp-ci-rs.yaml  --version 1.15.1 --wait
#helm upgrade --install --namespace istio-system --create-namespace istio-ingressgateway istio/gateway -f ingress-sp-ci-rs.yaml  --wait
helm upgrade --install --namespace istio-system --create-namespace istio-eastwestgateway istio/gateway -f eastwest-sp-ci-rs.yaml  --version 1.15.1 --wait



############################################## gloo-mesh ###################################################
kubectl config use-context kind-test-ci-rs

helm repo add gloo-mesh-enterprise https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-enterprise
helm repo add gloo-mesh-agent https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-agent
helm repo update

kubectl create namespace gloo-mesh
kubectl label ns gloo-mesh skip-docker-review=yes

#upgrade --install
helm upgrade --install gloo-mesh-enterprise gloo-mesh-enterprise/gloo-mesh-enterprise \
--namespace gloo-mesh \
--version=${GLOO_VERSION} \
--set licenseKey=${GLOO_MESH_LICENSE_KEY} \
-f gloo-mesh.helm.yaml \
--wait

kubectl -n gloo-mesh rollout status deploy/gloo-mesh-mgmt-server

export ENDPOINT_GLOO_MESH=$(kubectl get node test-ci-rs-control-plane -o jsonpath='{.status.addresses[0].address}'):$(kubectl -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.spec.ports[1].nodePort}')
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


###
kubectl config use-context kind-sp-ci-rs
export MGMT_CONTEXT=kind-test-ci-rs

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

############################################## workloads ###################################################
kubectl config use-context kind-test-ci-rs
kubectl create namespace mesh-test
kubectl label namespace mesh-test istio-injection=enabled
kubectl label namespace mesh-test skip-docker-review=yes
kubectl create namespace infra
kubectl label namespace infra istio-injection=enabled
kubectl label namespace infra skip-docker-review=yes
kubectl apply -f ../workloads/test-ci-rs/curl.yaml
kubectl apply -f ../workloads/test-ci-rs/curl-infra.yaml
kubectl apply -f ../workloads/test-ci-rs/foo.yaml

kubectl config use-context kind-sp-ci-rs
kubectl create namespace mesh-test
kubectl label namespace mesh-test istio-injection=enabled
kubectl label namespace mesh-test skip-docker-review=yes
kubectl apply -f ../workloads/sp-ci-rs/curl.yaml
kubectl apply -f ../workloads/sp-ci-rs/foo.yaml
kubectl apply -f ../workloads/sp-ci-rs/bar.yaml

############################################## management ###################################################
kubectl config use-context kind-test-ci-rs
kubectl apply -f ../mgmt/root-trust-policy.yaml
kubectl apply -f gateways-workspace.yaml
kubectl apply -f ../mgmt/mesh-test-workspace.yaml
kubectl apply -f ../mgmt/infra-workspace.yaml
kubectl apply -f ../mgmt/foo-ha.yaml
kubectl apply -f ../mgmt/foo-ha-infra.yaml

