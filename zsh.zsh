# Source this file from zsh to load project aliases and shell functions.
# Keep all project-specific aliases and shell functions here.
typeset -g TRITON_TOOLS_ROOT="${${(%):-%x}:A:h}"

# Aliases
alias setup_repo='triton_setup_repo'
alias deploy='triton_deploy'
alias find_onnx_models='triton_find_onnx_models'
alias fetch_models='triton_fetch_models'
alias forward_triton='triton_forward'
alias test_simple_identity='triton_test_simple_identity'
alias test_simple='triton_test_simple'
alias test_simple_int8='triton_test_simple_int8'
alias test_simple_string='triton_test_simple_string'
alias test_simple_sequence='triton_test_simple_sequence'
alias test_simple_dyna_sequence='triton_test_simple_dyna_sequence'
alias test_densenet_onnx='triton_test_densenet_onnx'
alias test_inception_onnx='triton_test_inception_onnx'
alias test_cpu_models='triton_test_cpu_models'

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

triton_forward() {
  local port="${1:-8000}"
  print -r -- "Forwarding http://localhost:$port to Triton. Leave this command running."
  kubectl --namespace triton port-forward service/triton-triton "$port:8000"
}

_triton_test_error_help() {
  local model="$1"
  local base_url="${TRITON_HTTP_URL:-http://localhost:8000}"
  base_url="${base_url%/}"
  print -u2 -r -- "Request failed. Check that '$model' is listed in deploy/triton/values.yaml under loadModels and redeploy."
  print -u2 -r -- "Model readiness: curl -i '$base_url/v2/models/$model/ready'"
  print -u2 -r -- "For k3s or Lima connectivity, run 'forward_triton' in another terminal and retry."
}

_triton_print_response() {
  local response="$1"
  print -r -- "Received:"
  if (( $+commands[jq] )); then
    print -r -- "$response" | jq .
  else
    print -r -- "$response"
  fi
}

_triton_infer_json() {
  local model="$1"
  local shape="$2"
  local payload="$3"
  local base_url="${TRITON_HTTP_URL:-http://localhost:8000}"
  base_url="${base_url%/}"

  print -r -- "Sending model '$model' with shape $shape"
  local response
  response=$(curl --silent --show-error --fail-with-body \
    --connect-timeout 5 --max-time 120 \
    --header 'Content-Type: application/json' \
    --data-binary "$payload" \
    "$base_url/v2/models/$model/infer")
  local curl_status=$?
  if (( curl_status != 0 )); then
    [[ -n "$response" ]] && print -u2 -r -- "$response"
    _triton_test_error_help "$model"
    return $curl_status
  fi
  _triton_print_response "$response"
}

_triton_infer_zero_tensor() {
  local model="$1"
  local input_name="$2"
  local shape="$3"
  local element_count="$4"
  local output_name="$5"
  local payload_file
  payload_file=$(mktemp "${TMPDIR:-/tmp}/triton-request.XXXXXX") || return

  awk -v input_name="$input_name" -v shape="$shape" \
    -v element_count="$element_count" -v output_name="$output_name" '
    BEGIN {
      printf "{\"inputs\":[{\"name\":\"%s\",\"shape\":%s,\"datatype\":\"FP32\",\"data\":[", input_name, shape
      for (i = 0; i < element_count; i++) {
        if (i > 0) printf ","
        printf "0"
      }
      printf "]}],\"outputs\":[{\"name\":\"%s\",\"parameters\":{\"classification\":3}}]}", output_name
    }
  ' > "$payload_file"

  local base_url="${TRITON_HTTP_URL:-http://localhost:8000}"
  base_url="${base_url%/}"
  print -r -- "Sending model '$model' with shape $shape (zero-filled tensor)"
  local response
  response=$(curl --silent --show-error --fail-with-body \
    --connect-timeout 5 --max-time 120 \
    --header 'Content-Type: application/json' \
    --data-binary "@$payload_file" \
    "$base_url/v2/models/$model/infer")
  local curl_status=$?
  command rm -f "$payload_file"
  if (( curl_status != 0 )); then
    [[ -n "$response" ]] && print -u2 -r -- "$response"
    _triton_test_error_help "$model"
    return $curl_status
  fi
  _triton_print_response "$response"
}

triton_test_simple_identity() {
  _triton_infer_json simple_identity '[1,3]' \
    '{"inputs":[{"name":"INPUT0","shape":[1,3],"datatype":"BYTES","data":["hello","from","triton"]}]}'
}

triton_test_simple() {
  _triton_infer_json simple '[1,16]' \
    '{"inputs":[{"name":"INPUT0","shape":[1,16],"datatype":"INT32","data":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]},{"name":"INPUT1","shape":[1,16],"datatype":"INT32","data":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]}]}'
}

triton_test_simple_int8() {
  _triton_infer_json simple_int8 '[1,16]' \
    '{"inputs":[{"name":"INPUT0","shape":[1,16],"datatype":"INT8","data":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]},{"name":"INPUT1","shape":[1,16],"datatype":"INT8","data":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]}]}'
}

triton_test_simple_string() {
  _triton_infer_json simple_string '[1,16]' \
    '{"inputs":[{"name":"INPUT0","shape":[1,16],"datatype":"BYTES","data":["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p"]},{"name":"INPUT1","shape":[1,16],"datatype":"BYTES","data":["1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16"]}]}'
}

triton_test_simple_sequence() {
  _triton_infer_json simple_sequence '[1,1]' \
    '{"parameters":{"sequence_id":1001,"sequence_start":true,"sequence_end":true},"inputs":[{"name":"INPUT","shape":[1,1],"datatype":"INT32","data":[7]}]}'
}

triton_test_simple_dyna_sequence() {
  _triton_infer_json simple_dyna_sequence '[1,1]' \
    '{"parameters":{"sequence_id":1002,"sequence_start":true,"sequence_end":true},"inputs":[{"name":"INPUT","shape":[1,1],"datatype":"INT32","data":[7]}]}'
}

triton_test_densenet_onnx() {
  _triton_infer_zero_tensor densenet_onnx data_0 '[3,224,224]' 150528 fc6_1
}

triton_test_inception_onnx() {
  _triton_infer_zero_tensor inception_onnx 'input:0' '[299,299,3]' 268203 'InceptionV3/Predictions/Softmax:0'
}

triton_test_cpu_models() {
  local test_function
  local failed=0
  for test_function in \
    triton_test_simple_identity \
    triton_test_simple \
    triton_test_simple_int8 \
    triton_test_simple_string \
    triton_test_simple_sequence \
    triton_test_simple_dyna_sequence \
    triton_test_densenet_onnx \
    triton_test_inception_onnx; do
    print -r -- ""
    "$test_function" || failed=1
  done
  return $failed
}
