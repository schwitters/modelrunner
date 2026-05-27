#!/bin/bash

# 1. Change into the project directory
cd /srv/projects/llama.cpp || { echo "Directory not found!"; exit 1; }

echo "Fetching the latest updates from GitHub..."
# Fetch all new branches and tags
git fetch origin --tags

# 2. Find the latest release tag (sorted by creation date)
LATEST_TAG=$(git tag --sort=-creatordate | head -n 1)

if [ -z "$LATEST_TAG" ]; then
    echo "No tags found. Make sure this is a git repository."
    exit 1
fi

echo "Latest release found: $LATEST_TAG"

# 3. Check out the latest release
# The "-f" (force) discards any local, uncommitted changes to the code
git checkout -f "$LATEST_TAG"

# 4. Set variables for the build
VARIANT="rtx-5090"
BUILD_DIR="build-${VARIANT}"

echo "Starting build for $LATEST_TAG with variant $VARIANT..."
export PATH=/usr/local/cuda/bin:$PATH
export CUDACXX=/usr/local/cuda/bin/nvcc
# 5. CMake configuration
# We use the same command but cleanly overwrite the CMake configuration
# -DCMAKE_EXECUTABLE_SUFFIX="-${VARIANT}" \
cmake -B "$BUILD_DIR" -G Ninja \
  -DGGML_CUDA=ON \
  -DGGML_CUDA_FA=ON \
  -DGGML_CUDA_FA_ALL_QUANTS=ON \
  -DGGML_CUDA_WMM_ALL=ON \
  -DGGML_AVX_VNNI=ON \
  -DGGML_AVX2=ON \
  -DGGML_FMA=ON \
  -DGGML_NATIVE=ON \
  -DGGML_CUDA_COMPRESSION_MODE=speed \
  -DCMAKE_CUDA_ARCHITECTURES=120

# 6. Compile the build
cmake --build "$BUILD_DIR" --config Release -j $(nproc)

echo "✅ Build of $LATEST_TAG complete! Binaries are in $BUILD_DIR/bin/"
