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

## Test CPU models

After deployment, commands such as `test_simple_identity`, `test_simple`, and `test_densenet_onnx` send HTTP inference requests and print the input shape and response. Run `test_cpu_models` to try every CPU-capable example; the image models first require `fetch_models`. Each tested model must also be present under `loadModels` in the Helm values.

The tests use `http://localhost:8000` by default. If that address cannot reach Triton through Lima, run `forward_triton` in another terminal. If Triton responds that a model is unavailable, check `curl -i localhost:8000/v2/models/MODEL_NAME/ready` and verify the model is loaded. Set `TRITON_HTTP_URL` to use another address.

See [`Docs/deployment.md`](Docs/deployment.md) for deployment details.
