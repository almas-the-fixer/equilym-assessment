# Pharmacy Stock Availability API - Set A

## Prerequisites

Linux or WSL2, Git, Python 3.10+, Docker with Compose, Terraform CLI, and kubectl with kind or minikube.

## Linux and Git

Run the supplied fixture analysis:

```sh
chmod +x scripts/analyze_logs.sh
./scripts/analyze_logs.sh logs/access.log
```

Exact fixture commands and the derived result are in `evidence/linux-log-analysis.txt`.

Create a branch and commit completed work:

```sh
git switch -c assessment/set-a
git add .
git diff --cached --stat
git -c user.name="Candidate" -c user.email="candidate@example.com" commit -m "Complete Set A DevOps assessment"
```

Do not commit `.terraform/`, `*.tfstate*`, `generated/service.env`, credentials, or tokens.

## Python

```sh
python3 -m unittest discover -s tests -v
python3 -m app.server
```

Stop with Ctrl+C. The server listens on `127.0.0.1:8080`.

## Docker Compose

Generate `generated/service.env` first (see Terraform below), then:

```sh
docker compose up --build -d
curl -i http://127.0.0.1:8080/healthz
curl -i http://127.0.0.1:8080/readyz
curl -i 'http://127.0.0.1:8080/api/stock?sku=MED-101'
docker compose logs --tail=100
docker compose down
```

The Dockerfile runs as UID 10001 and probes `/healthz`.

## CI

GitHub Actions runs syntax checks and unit tests before the Docker build. `.github/workflows/ci.yml` uses commit SHA image
tagging and `contents: read` permissions. It does not push to a registry.

To demonstrate test gating locally:

```sh
cp tests/test_server.py /tmp/test_server.py
python3 -c "p='tests/test_server.py'; s=open(p).read(); open(p,'w').write(s.replace('self.assertEqual(route(\\x27/healthz\\x27)[0], 200)', 'self.assertEqual(500, 200)'))"
python3 -m unittest discover -s tests -v
git restore tests/test_server.py
```

## Terraform

Run from `infra/`:

```sh
cd infra
terraform fmt
terraform init
terraform validate
terraform plan -var-file=dev.tfvars.example
terraform apply -auto-approve -var-file=dev.tfvars.example
cd ..
```

This creates `generated/service.env`. It is ignored and must remain uncommitted.

## Kubernetes

Build and load the image into kind:

```sh
docker build -t pharmacy-stock:local .
kind create cluster --name assessment
kind load docker-image pharmacy-stock:local --name assessment
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl -n devops-assessment rollout status deployment/pharmacy-stock
kubectl -n devops-assessment get pods
kubectl -n devops-assessment port-forward service/pharmacy-stock 8080:80
```

With port-forward running, call `http://127.0.0.1:8080/healthz`, `/readyz`, and the stock endpoint.

Controlled bad rollout:

```sh
kubectl -n devops-assessment set env deployment/pharmacy-stock FAIL_MODE=1
kubectl -n devops-assessment rollout status deployment/pharmacy-stock --timeout=30s
kubectl -n devops-assessment get deployment,pods
kubectl -n devops-assessment describe deployment pharmacy-stock
kubectl -n devops-assessment get pods -l app=pharmacy-stock
kubectl -n devops-assessment logs -l app=pharmacy-stock --tail=50
kubectl -n devops-assessment rollout undo deployment/pharmacy-stock
kubectl -n devops-assessment rollout status deployment/pharmacy-stock
kubectl -n devops-assessment get pods
```

Restore the ConfigMap/healthy environment as needed:

```sh
kubectl -n devops-assessment set env deployment/pharmacy-stock FAIL_MODE=0
```

For cleanup:

```sh
kubectl delete namespace devops-assessment
kind delete cluster --name assessment
docker compose down
```

## Monitoring and recovery

The fixture has 24 requests and 2 HTTP 5xx responses, so the 5xx rate is 8.33%. A practical exercise alert is
**alert when 5xx exceeds 5% of requests over a 5-minute window**, with a minimum 20-request volume to avoid a
tiny-volume false positive. A readiness failure makes `/readyz` return 503 and removes Pods from Service endpoints;
a liveness failure means `/healthz` is unavailable or process is unhealthy and Kubernetes restarts the container.

Bad rollout diagnosis follows `kubectl get`, `describe`, `logs`, and `rollout status`. Recovery is `kubectl rollout undo`
and verification of 2/2 Pods Ready. This is separate from a read-only root filesystem concern: app writes no runtime
files, so read-only root plus dropped Linux capabilities can be compatible.

Security checks:

1. The container and Pods run without root and drop all capabilities.
2. Git ignores state, generated environment data, and evidence logs; no credentials are stored in source.

Incident runbook:

1. Check `kubectl get deployment,pods` and rollout status.
2. Describe unhealthy Pods and read recent logs.
3. Confirm readiness versus liveness probe behavior.
4. Undo the failed rollout and confirm 2/2 Ready Pods.
5. If the rollback is unhealthy, stop traffic and inspect the prior revision and configuration.
