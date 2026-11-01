# OCR Model Benchmark — Scientific Article (12 pages, scanned @200dpi)

Date: 2026-11-01 · Machine: Apple Silicon, 17.2GB RAM, Metal · Helper: pinned f3586e66
Input: `41598_2026_Article_49129.pdf` (Nature SciRep, 12 pages, text layer stripped)
Mode: document, Metal, balanced · Context 8192 · Greedy + presence/freq 0.5

## Summary

| Model | Disk | Peak RSS | 12 pages | Per page | Out tokens | Precision | Verdict |
|---|---|---|---|---|---|---|---|
| GLM-OCR (Q8) | 1.4 GB | 2.15 GB | ~5 min | ~23s | 1,175 | 91% | Fast, terse |
| PaddleOCR-VL 1.6 | 1.8 GB | 2.22 GB | ~2 min | ~9s | 5,113 | 89% | **Fastest, good** |
| Qwen3-VL 2B (Q4) | 1.9 GB | 3.75 GB | ~7 min | ~36s | 9,269 | 99% | **Most complete** |
| dots.ocr (Q8) | 3.1 GB | 3.77 GB | ~18 min | ~91s | 1,075 | 86% | Slow, hallucinates |
| DeepSeek-OCR 2 (Q4) | 2.4 GB | 4.43 GB | ~4 min | ~21s | 1,390 | 80% | Mid, projector CPU |

Precision = output words (4+ chars) found in native reference. Recall is low
(13–16%) for all: models summarize rather than transcribe verbatim.

## 8GB Mac verdict

- GLM / Paddle (~2.2GB peak): safe on 8GB.
- Qwen (3.75GB peak): OK on 8GB with headroom; best quality.
- dots (3.77GB + 18min): not worth it; also hallucinates table content.
- DeepSeek (4.43GB): heaviest; projector forced to CPU per publisher note.
- Idle reaper (60s) + dispatch memory-pressure source release the helper;
  only one model resident at a time by design.

## Known issues found during benchmarking

1. **Truncation loops**: Qwen p3/p4 hit 4096 tokens on footnote repetition
   ("NR = no demographic..." x50). Mitigated with presence/freq 0.5;
   full Xiaomi-style repetition retry is future work.
2. **dots hallucinates**: invented table rows ("Third, the performance..."),
   emitted `<|endofassistant|>` litter, skipped the title.
3. **All models under-transcribe**: 12 pages → 1–9K tokens vs 6K-word
   reference. Document prompt favors structure over verbatim. Acceptable
   for Markdown use; not a replacement for text-layer extraction.
4. **Short-prompt models** (GLM/Paddle/dots/DeepSeek) ignore the long
   Markdown instruction; they use terse triggers + chat template instead.

## Raw outputs

`build/ocr-bench/<model>/p{1..12}.md` + `summary.json` per model.
Reproduce: `./scripts/benchmark-ocr-models.sh [model-id...]`
