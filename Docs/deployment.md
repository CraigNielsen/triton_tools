# Triton deployment

The Helm chart is in `deploy/triton/`. Its default image is `nvcr.io/nvidia/tritonserver:26.08-py3`. The chart creates a Deployment and a ClusterIP Service with HTTP (8000), gRPC (8001), and metrics (8002) ports.

## Local commands

Source `zsh.zsh` from the repository root:

```zsh
source ./zsh.zsh
```

`setup_repo` clones the Triton server source into `triton/`, checks out `v2.72.0` (the source release corresponding to container `26.08`), and creates the local branch `v2-72` from that tag. It copies the entire example model repository, including each model's `config.pbtxt`, into this repository's `deploy_models/` and logs the source and destination. Running it again keeps existing local model files and configs. The Triton source checkout stays intact; both the clone and `deploy_models/` are ignored by Git.

`deploy` runs `helm upgrade --install` for this chart and creates the `triton` namespace if needed. It uses the current Kubernetes context and mounts this repository's `deploy_models/` at `/models` in the container. Each run changes a pod annotation so Triton restarts and reads updated model files and configs. Additional Helm arguments can be passed to the command, for example `deploy --dry-run --debug`.

`find_onnx_models` prints the absolute path of each model directory using the ONNX Runtime backend. It checks `backend` and `platform` in `config.pbtxt` and also finds models with `.onnx` files even if they have no config. A listed directory may still need model weights downloaded before Triton can load it.

`fetch_models` runs this repository's `fetch_models.sh`. It activates your existing `pyenv` environment named `tritonenv` and does not install system or Python packages. Install `tensorflow`, `tf2onnx`, and `onnx` in that environment before fetching Inception; also have `curl` available. With no arguments it fetches both missing ONNX models: it converts Inception V3 and downloads DenseNet. Use `fetch_models densenet_onnx` or `fetch_models inception_onnx` to fetch just one. The script logs each model and its absolute destination in `deploy_models/`, and skips any model file already present. The five other ONNX examples and the Python `simple_identity` example already have model files, so the chart's default deployment requires neither download.

## Models and GPU

The local mount uses a Kubernetes `hostPath`. The same absolute path to `deploy_models/` must exist on the node running Triton, so this is suited to a local single-node k3s cluster or nodes sharing that path. For a remote cluster, use an existing PersistentVolumeClaim instead: set `modelRepository.existingClaim` in `deploy/triton/values.yaml` or pass `--set modelRepository.existingClaim=YOUR_CLAIM` to `deploy`. The claim must exist in the `triton` namespace and contain a valid Triton model repository. The claim takes precedence over `hostPath`.

Triton reads each model's `config.pbtxt` from within its model directory, so edit `deploy_models/<model>/config.pbtxt` directly. The chart starts in explicit model-control mode and loads `simple_identity` by default. Run `fetch_models` before loading Inception or DenseNet, and adjust `loadModels` in the values file to select the models to load. ONNX Runtime supports CPU inference; `simple_sequence` and `simple_dyna_sequence` already specify `KIND_CPU` in their configs. Other ONNX configs can be set to `KIND_CPU` when CPU placement is required.

The default `gpu: false` does not request a GPU. Set `gpu: true` to add a `nvidia.com/gpu` resource limit (one GPU by default, controlled by `gpuCount`). The cluster needs a working NVIDIA device plugin and suitable GPU nodes. Set `runtimeClassName: nvidia` if your k3s or Kubernetes setup requires that runtime class. GPU-only models cannot load without a GPU.

The source clone and container image have separate versions: `v2.72.0` is the Triton server source tag corresponding to container release `26.08`.
