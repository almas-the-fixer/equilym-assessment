Manifests:
- namespace.yaml
- configmap.yaml
- deployment.yaml
- service.yaml

Probes use /readyz for readiness and /healthz for liveness.
Set FAIL_MODE=1 only for the controlled local incident and restore it to 0 afterward.
