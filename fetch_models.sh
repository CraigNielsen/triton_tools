#!/usr/bin/env bash
# Adapted from Triton Inference Server's docs/examples/fetch_models.sh (v2.72.0).
# Copyright (c) 2018-2025, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# * Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the distribution.
# * Neither the name of NVIDIA CORPORATION nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

set -eo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
models_dir="$repo_root/deploy_models"

log() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[[ -d "$models_dir" ]] || fail "Model repository missing at $models_dir; run setup_repo first"
command -v pyenv >/dev/null 2>&1 || fail "pyenv is required; install tritonenv manually"
command -v curl >/dev/null 2>&1 || fail "curl is required for downloads"

requested_models=("$@")
if (( ${#requested_models[@]} == 0 )); then
  requested_models=(inception_onnx densenet_onnx)
fi
for model in "${requested_models[@]}"; do
  case "$model" in
    inception_onnx|densenet_onnx) ;;
    *) fail "Unknown model '$model'; choose inception_onnx or densenet_onnx" ;;
  esac
done

# pyenv-virtualenv must initialize in this Bash process for activate to work.
eval "$(pyenv init - --no-rehash bash)"
eval "$(pyenv virtualenv-init -)"
pyenv activate tritonenv || fail "Could not activate pyenv environment tritonenv"
log "Using pyenv environment: tritonenv ($(command -v python))"

temporary_paths=()
trap 'for temporary_path in "${temporary_paths[@]}"; do rm -rf "$temporary_path"; done' EXIT

fetch_inception() {
  local destination="$models_dir/inception_onnx/1/model.onnx"
  if [[ -s "$destination" ]]; then
    log "Already present, skipping inception_onnx: $destination"
    return
  fi
  python -c 'import tensorflow, tf2onnx, onnx' \
    || fail "Install tensorflow, tf2onnx, and onnx in tritonenv before fetching inception_onnx"

  local scratch_dir output
  scratch_dir="$(mktemp -d)"
  temporary_paths+=("$scratch_dir")
  output="$(mktemp "$models_dir/inception_onnx/1/.model.onnx.XXXXXX")"
  temporary_paths+=("$output")
  log "Fetching inception_onnx and saving to: $destination"
  curl --fail --location --silent --show-error --retry 3 \
    --output "$scratch_dir/inception.tar.gz" \
    'https://storage.googleapis.com/download.tensorflow.org/models/inception_v3_2016_08_28_frozen.pb.tar.gz' \
    || fail "Could not download inception_onnx source"
  tar -xzf "$scratch_dir/inception.tar.gz" -C "$scratch_dir"
  python -m tf2onnx.convert \
    --graphdef "$scratch_dir/inception_v3_2016_08_28_frozen.pb" \
    --output "$output" \
    --inputs input:0 \
    --outputs InceptionV3/Predictions/Softmax:0
  [[ -s "$output" ]] || fail "Inception conversion did not produce a model"
  mv "$output" "$destination"
  rm -rf "$scratch_dir"
  log "Saved inception_onnx: $destination"
}

fetch_densenet() {
  local destination="$models_dir/densenet_onnx/1/model.onnx"
  if [[ -s "$destination" ]]; then
    log "Already present, skipping densenet_onnx: $destination"
    return
  fi
  local output
  output="$(mktemp "$models_dir/densenet_onnx/1/.model.onnx.XXXXXX")"
  temporary_paths+=("$output")
  log "Fetching densenet_onnx and saving to: $destination"
  curl --fail --location --silent --show-error --retry 3 \
    --output "$output" \
    'https://github.com/onnx/models/raw/main/validated/vision/classification/densenet-121/model/densenet-7.onnx' \
    || fail "Could not download densenet_onnx"
  [[ -s "$output" ]] || fail "DenseNet download was empty"
  mv "$output" "$destination"
  log "Saved densenet_onnx: $destination"
}

for model in "${requested_models[@]}"; do
  case "$model" in
    inception_onnx)
      mkdir -p "$models_dir/inception_onnx/1"
      fetch_inception
      ;;
    densenet_onnx)
      mkdir -p "$models_dir/densenet_onnx/1"
      fetch_densenet
      ;;
  esac
done
