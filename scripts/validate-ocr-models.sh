#!/bin/zsh
# Validates installed OCR models against the pinned matrix without downloading.
# Usage:
#   ./scripts/validate-ocr-models.sh [--model <id>] [--publish-pr <number>]
# Never downloads weights; only tests already-installed verified layouts.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

model=""
publish_pr=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --publish-pr) publish_pr="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

head_sha="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain=v1)" ]]; then
  echo "Refusing: working tree is dirty. Commit first so evidence pins to an exact SHA." >&2
  exit 1
fi
remote_url="$(git config --get remote.origin.url)"
if [[ "$remote_url" != *"MachineX41/Orange-App"* ]]; then
  echo "Refusing: unexpected origin ($remote_url)." >&2
  exit 1
fi

# Pinned runtime revision must match the built helper.
expected_rev="f3586e66bc916d672773d4a6505513ba91a3595c"
helper="${ORANGE_OCR_HELPER:-$root/build/Orange.app/Contents/Helpers/OrangeOCRHelper}"
if [[ ! -x "$helper" ]]; then
  # Fall back to the raw runtime build (bundle packaging happens in build-app.sh).
  helper="$root/build/ocr-runtime/OrangeOCRHelper"
fi
if [[ ! -x "$helper" ]]; then
  echo "No helper at $helper; run scripts/build-ocr-runtime.sh first." >&2
  exit 1
fi
caps="$("$helper" --capabilities)"
if ! echo "$caps" | grep -q "$expected_rev"; then
  echo "Helper revision mismatch. Expected $expected_rev, got: $caps" >&2
  exit 1
fi

outdir="$root/build/ocr-validation/$head_sha"
mkdir -p "$outdir"

if [[ -n "$model" ]]; then
  filter="OCRDownloadedModelTests/test"
else
  filter="OCRDownloadedModelTests"
fi

log="$outdir/swift-test-$([[ -n "$model" ]] && echo "$model" || echo all).log"
export ORANGE_OCR_MODEL_TESTS=1
export ORANGE_OCR_HELPER="$helper"

# Swift test selection: run the opt-in suite; skips stay SKIP, never PASS.
if [[ -n "$model" ]]; then
  case "$model" in
    glm-ocr) tests="testGLMCPURecognition|testGLMMetalRecognition|testWarmPDFReusesGLM|testSwitchGLMToAppleReleasesHelper|testCancelGLMInference|testGLMMultiPageMemoryBound" ;;
    paddleocr-vl-1.6) tests="testPaddleCPURecognition|testPaddleMetalRecognition" ;;
    qwen3-vl-2b) tests="testQwenCPURecognition|testQwenMetalRecognition" ;;
    dots-ocr) tests="testDotsCPURecognition|testDotsMetalRecognition" ;;
    deepseek-ocr-2) tests="testDeepSeekCPURecognition|testDeepSeekMetalCPUProjectorRecognition" ;;
    *) echo "Unknown model: $model" >&2; exit 2 ;;
  esac
  swift test --filter "OCRDownloadedModelTests.($tests)" 2>&1 | tee "$log" || true
else
  swift test --filter "OCRDownloadedModelTests" 2>&1 | tee "$log" || true
fi

# Parse XCTest result lines (Swift 6.4 --xunit-output no longer emits XCTest XML).
python3 - "$log" "$outdir" <<'EOF'
import sys, re, json, pathlib
log, outdir = sys.argv[1], pathlib.Path(sys.argv[2])
expected = ["testGLMCPURecognition","testGLMMetalRecognition","testPaddleCPURecognition","testPaddleMetalRecognition","testQwenCPURecognition","testQwenMetalRecognition","testDotsCPURecognition","testDotsMetalRecognition","testDeepSeekCPURecognition","testDeepSeekMetalCPUProjectorRecognition","testWarmPDFReusesGLM","testSwitchGLMToAppleReleasesHelper","testCancelGLMInference","testGLMMultiPageMemoryBound"]
text = open(log).read()
found = {}
for name in expected:
    # "Test Case '-[... testName]' passed/failed/skipped"
    m = re.findall(r"Test Case '-\[\S+ " + name + r"\]' (passed|failed|skipped)", text)
    if m:
        last = m[-1]
        found[name] = "PASS" if last == "passed" else ("FAIL" if last == "failed" else "SKIP")
missing = [n for n in expected if n not in found]
report = {"expected": expected, "found": found, "missing": missing}
(outdir / "matrix.json").write_text(json.dumps(report, indent=2))
# Paddle CPU is a documented unsupported config (vision encoder hangs on CPU
# backend, upstream llama.cpp); its SKIP is accepted, not pending.
accepted_skips = {"testPaddleCPURecognition"}
fails = [n for n, s in found.items() if s == "FAIL"] + missing
if fails:
    print("MATRIX INCOMPLETE:", ", ".join(fails))
    sys.exit(1)
skips = [n for n in expected if found.get(n) == "SKIP" and n not in accepted_skips]
if skips:
    print("MATRIX PENDING (skipped):", ", ".join(skips))
    sys.exit(1)
print("MATRIX SUCCESS: all cases passed (1 accepted CPU-unsupported skip)")
EOF
status=$?
if [[ $status -ne 0 ]]; then exit $status; fi

if [[ -n "$publish_pr" ]]; then
  summary="$(python3 -c "import json; r=json.load(open('$outdir/matrix.json')); print('; '.join(f\"{k}={v}\" for k,v in r['found'].items()))")"
  gh api "repos/MachineX41/Orange-App/statuses/$head_sha" \
    -f state=success -f context=ocr-hardware-validation \
    -f description="OCR hardware matrix passed" \
    -f target_url="https://github.com/MachineX41/Orange-App/pull/$publish_pr" >/dev/null
  gh pr comment "$publish_pr" --repo MachineX41/Orange-App --body "ocr-hardware-validation success @ $head_sha

$summary" >/dev/null
fi

echo "Validation record: $outdir"
