kubectl create namespace mesh-test
kubectl label namespace mesh-test istio-injection=enabled
kubectl label namespace mesh-test skip-docker-review=yes

kubectl apply -f curl.yaml
kubectl apply -f foo.yaml
kubectl apply -f bar.yaml

