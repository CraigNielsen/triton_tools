# Triton tools

The Helm chart runs Triton in **explicit model-control mode**. Although every model under `deploy_models/` is mounted at `/models`, Triton loads only the models listed under `loadModels` in `deploy/triton/values.yaml`. The default is `simple_identity`. Add another model name to that list and run `deploy` again to load it.

This repository contains local tools and a Helm chart for running NVIDIA Triton Inference Server in k3s or Kubernetes.

## Quick start

```zsh
source ./zsh.zsh
setup_repo
deploy
```

- `setup_repo` clones Triton and prepares `deploy_models/`.
- `fetch_models` downloads the optional ONNX example models.
- `find_onnx_models` lists models that use the ONNX backend.
- `deploy` installs or updates Triton in the `triton` namespace.

See [`Docs/deployment.md`](Docs/deployment.md) for deployment details.
