# Pharmacy Stock Availability API - Set A

> Note From Candidate (Almas): 
**AI assistance note:** This assessment was completed with the Help of GitHub Copilot using the Copilot SDK in VS Code The Candidate ( ME ) Did use it to Save time and Write Documentation.

## Prerequisites

Linux or WSL2, Git, Python 3.10+, Docker with Compose, Terraform CLI, kubectl, and k3s.

## Linux and Git

Run the supplied fixture analysis:

```sh
chmod +x scripts/analyze_logs.sh
./scripts/analyze_logs.sh logs/access.log
```

Exact fixture commands and the derived result are in `evidence/linux-log-analysis.txt`.

## Python

```sh
python3 -m unittest discover -s tests -v
python3 -m app.server
```

Stop with Ctrl+C. The server listens on `127.0.0.1:8080`.

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

Terraform must run before Docker Compose and Kubernetes image demos because it generates `generated/service.env`.
Run these commands from the project root:

```sh
terraform -chdir=infra fmt
terraform -chdir=infra init
terraform -chdir=infra validate
terraform -chdir=infra plan -var-file=dev.tfvars.example
terraform -chdir=infra apply -auto-approve -var-file=dev.tfvars.example
```

This creates `generated/service.env`. It is ignored and must remain uncommitted.

## Docker Compose

After Terraform successfully creates `generated/service.env`, run:

```sh
docker compose up --build -d
curl -i http://127.0.0.1:8080/healthz
curl -i http://127.0.0.1:8080/readyz
curl -i 'http://127.0.0.1:8080/api/stock?sku=MED-101'
docker compose ps
docker compose logs --tail=100
docker compose down
```

The Dockerfile runs as UID 10001 and probes `/healthz`.

## Kubernetes

Build the local image and install/start k3s. If k3s is not already installed, use the official k3s installer:

```sh
docker build -t pharmacy-stock:local .
curl -sfL https://get.k3s.io | sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo chmod 600 "$KUBECONFIG"
docker save pharmacy-stock:local | sudo k3s ctr images import -
kubectl get nodes
```

The first k3s server start can take a few seconds. If `kubectl` reports permission errors, run k3s commands with
`sudo` or keep the exported `KUBECONFIG` above.

Deploy the resources:

```sh
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl -n devops-assessment rollout status deployment/pharmacy-stock
kubectl -n devops-assessment get pods -o wide
```

Access the internal Service in a separate terminal:

```sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl -n devops-assessment port-forward service/pharmacy-stock 8080:80
```

With port-forward running, call:

```sh
curl -i http://127.0.0.1:8080/healthz
curl -i http://127.0.0.1:8080/readyz
curl -i 'http://127.0.0.1:8080/api/stock?sku=MED-101'
```

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
docker compose down
sudo /usr/local/bin/k3s-uninstall.sh
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
