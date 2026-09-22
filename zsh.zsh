# Source this file from zsh to load project aliases and shell functions.
# Keep all project-specific aliases and shell functions here.
typeset -g TRITON_TOOLS_ROOT="${${(%):-%x}:A:h}"

# Aliases
alias setup_repo='triton_setup_repo'
alias deploy='triton_deploy'
alias find_onnx_models='triton_find_onnx_models'
alias fetch_models='triton_fetch_models'

# Shell functions
triton_setup_repo() {
  local target="$TRITON_TOOLS_ROOT/triton"
  local source_models="$target/docs/examples/model_repository"
  local deploy_models="$TRITON_TOOLS_ROOT/deploy_models"

  if [[ ! -d "$target/.git" ]]; then
    if [[ -e "$target" ]]; then
      print -u2 -- "Cannot clone Triton: $target exists but is not a Git checkout"
      return 1
    fi
    git clone --branch v2.72.0 --depth 1 https://github.com/triton-inference-server/server.git "$target" || return
  fi

  if ! git -C "$target" show-ref --verify --quiet refs/heads/v2-72; then
    git -C "$target" checkout v2.72.0 || return
    git -C "$target" checkout -b v2-72 || return
  else
    print -r -- "Triton branch v2-72 already exists; keeping the current checkout"
  fi

  if [[ ! -d "$source_models" ]]; then
    print -u2 -- "Example model repository missing at $source_models"
    return 1
  fi

  if [[ ! -d "$deploy_models" ]]; then
    cp -R "$source_models" "$deploy_models" || return
    print -r -- "Copied models and configs: $source_models -> $deploy_models"
  else
    print -r -- "Keeping existing local models and configs: $deploy_models"
  fi
}

triton_deploy() {
  local models_dir="$TRITON_TOOLS_ROOT/deploy_models"
  if [[ ! -d "$models_dir" ]]; then
    print -u2 -- "Triton model repository not found at $models_dir; run setup_repo first"
    return 1
  fi
  helm upgrade --install triton "$TRITON_TOOLS_ROOT/deploy/triton" \
    --namespace triton --create-namespace \
    --values "$TRITON_TOOLS_ROOT/deploy/triton/values.yaml" \
    --set-string "modelRepository.hostPath=$models_dir" \
    --set-string "redeployToken=$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM" "$@"
}

triton_find_onnx_models() {
  local models_dir="$TRITON_TOOLS_ROOT/deploy_models"
  if [[ ! -d "$models_dir" ]]; then
    print -u2 -- "Triton model repository not found at $models_dir; run setup_repo first"
    return 1
  fi

  local config model_file model_path
  local -A found
  for config in "$models_dir"/*/config.pbtxt(N); do
    if grep -Eq '^[[:space:]]*(backend|platform)[[:space:]]*:[[:space:]]*"onnxruntime(_onnx)?"' "$config"; then
      found[${config:h}]=1
    fi
  done
  for model_file in "$models_dir"/*/*/*.onnx(N); do
    found[${model_file:h:h}]=1
  done

  for model_path in ${(ok)found}; do
    print -r -- "$model_path"
  done
}

triton_fetch_models() {
  local script="$TRITON_TOOLS_ROOT/fetch_models.sh"
  if [[ ! -f "$script" ]]; then
    print -u2 -- "Local fetch_models.sh not found at $script"
    return 1
  fi
  bash "$script" "$@"
}
