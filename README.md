gcc 14.2.0
cuda 13.2.75
llama version b9192 
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

llama-server \ 
	--model qwen3.6-27b-q5_k_m.gguf \
	--host 0.0.0.0 \
	--port 8080 \
	--n-gpu-layers 999 \
	--ctx-size 200000 \
	--parallel 1 \
	--flash-attn on \
	--cache-type-k q8_0 \
	--cache-type-v q8_0 \
	--spec-type draft-mtp \
	--spec-draft-n-max 6 \
	--spec-draft-p-min 0.7 \
	--cache-ram 16384 \
	--threads 8 \
	--threads-batch 16 \
	--temp 0.3 \
	--top-p 0.9 \
	--min-p 0.05 \
	--jinja \
	--metrics \
	--kv-unified
	
	
llama-server 
    --model qwen3.6-35b-a3b-ud-q5_k_m.gguf \
	--metrics \
	--cache-ram 16384 \
	--parallel 1 \
	--threads 8 \
	--spec-draft-p-min 0.75 \
	--ctx-size 200000 \
	--port 8080 \
	--host 0.0.0.0 \
	--min-p 0.05 \
	--n-gpu-layers 999 \
	--kv-unified \
	--cache-type-k q8_0 \
	--cache-type-v q8_0 \
	--top-p 0.9 \
	--spec-type draft-mtp \
	--temp 0.2 \
	--jinja \
	--threads-batch 16 \
	--spec-draft-n-max 6 \
	--flash-attn on
