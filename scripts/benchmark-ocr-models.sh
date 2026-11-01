#!/bin/zsh
# 5-model article benchmark: 12 scanned pages each, time + peak RSS + output.
# Usage: ./scripts/benchmark-ocr-models.sh [model-id...]
# Writes build/ocr-bench/<model>/<page>.md + summary.json
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

HELPER="${ORANGE_OCR_HELPER:-$root/build/ocr-runtime/OrangeOCRHelper}"
MODELS_ROOT="${ORANGE_OCR_MODEL_ROOT:-$HOME/Library/Application Support/Orange/Models}"
OUT="$root/build/ocr-bench"
mkdir -p "$OUT"

models=("$@")
if [[ ${#models[@]} -eq 0 ]]; then
  models=(glm-ocr qwen3-vl-2b)
fi

declare -A REVS=(
  [glm-ocr]="65a42de1148dbed2297e922b5dbc7d9b70c36578"
  [qwen3-vl-2b]="52d6c8ffea26cc873ac5ad116f8631268d7eb503"
)
declare -A MODEL_FILE=(
  [glm-ocr]="GLM-OCR-Q8_0.gguf"
  [qwen3-vl-2b]="Qwen3VL-2B-Instruct-Q4_K_M.gguf"
)
declare -A PROJ_FILE=(
  [glm-ocr]="mmproj-GLM-OCR-Q8_0.gguf"
  [qwen3-vl-2b]="mmproj-Qwen3VL-2B-Instruct-F16.gguf"
)

for model in "${models[@]}"; do
  dir="$MODELS_ROOT/$model/${REVS[$model]}"
  if [[ ! -f "$dir/${MODEL_FILE[$model]}" ]]; then
    echo "SKIP $model: not installed"
    continue
  fi
  mdir="$OUT/$model"
  mkdir -p "$mdir"
  echo "=== $model ==="
  # Build NDJSON input: load + 12 recognizes
  input=$(mktemp)
  echo "{\"type\":\"load\",\"protocolVersion\":1,\"requestID\":\"load\",\"modelID\":\"$model\",\"modelPath\":\"$dir/${MODEL_FILE[$model]}\",\"projectorPath\":\"$dir/${PROJ_FILE[$model]}\",\"compute\":\"metal\",\"quality\":\"balanced\",\"contextTokens\":8192,\"maxOutputTokens\":4096,\"threads\":4}" > "$input"
  for p in $(seq 1 12); do
    echo "{\"type\":\"recognize\",\"protocolVersion\":1,\"requestID\":\"p$p\",\"imagePath\":\"/tmp/article-p$p.png\",\"mode\":\"document\"}" >> "$input"
  done
  # RAM sampler in background
  peak_kb=0
  (
    sleep 5
    for i in $(seq 1 240); do
      for pid in $(pgrep -x OrangeOCRHelper 2>/dev/null); do
        rss=$(ps -o rss= -p $pid 2>/dev/null | tr -d ' ')
        echo "$rss" >> "$mdir/rss.log"
      done
      sleep 5
    done
  ) &
  sampler=$!
  start=$(date +%s)
  # Close stdin after input: helper exits on EOF, no sleep needed.
  # head -13 would SIGPIPE the helper; use timeout + full read instead.
  timeout 1600 "$HELPER" 2>"$mdir/stderr.log" < "$input" > "$mdir/raw.jsonl" || true
  end=$(date +%s)
  kill $sampler 2>/dev/null || true
  # Split pages + summary
  python3 - "$mdir" "$model" $((end - start)) <<'EOF'
import json, sys, pathlib
mdir, model, wall = pathlib.Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
pages = []
for line in open(mdir / "raw.jsonl"):
    line = line.strip()
    if not line: continue
    o = json.loads(line)
    if o.get("type") == "result":
        rid = o.get("requestID", "?")
        (mdir / f"{rid}.md").write_text(o.get("text", ""))
        pages.append({"page": rid, "in": o.get("inputTokens"), "out": o.get("outputTokens"),
                      "trunc": o.get("truncated"), "secs": round(o.get("durationSeconds", 0), 1),
                      "compute": o.get("actualCompute")})
rss_vals = []
try:
    rss_vals = [int(x) for x in open(mdir / "rss.log").read().split() if x.strip().isdigit()]
except FileNotFoundError:
    pass
peak_gb = round(max(rss_vals) / 1e6, 2) if rss_vals else 0
total_out = sum(p["out"] or 0 for p in pages)
summary = {"model": model, "wall_secs": wall, "pages_done": len(pages),
           "total_output_tokens": total_out, "peak_rss_gb": peak_gb,
           "truncated_pages": [p["page"] for p in pages if p["trunc"]],
           "pages": pages}
(mdir / "summary.json").write_text(json.dumps(summary, indent=1))
print(f"{model}: {len(pages)}/12 pages, wall {wall}s, peak {peak_gb}GB, out-tokens {total_out}")
EOF
  pkill -9 -x OrangeOCRHelper 2>/dev/null || true
  sleep 2
done
echo "DONE: $OUT"
