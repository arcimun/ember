# Whisper Model Benchmark

## Status: PENDING

Run the benchmark to populate this file:

```bash
# 1. Record sample audio files
mkdir -p /tmp/ember-benchmark
# Record short (3s), medium (15s), long (60s) in Russian and English

# 2. Run benchmark
bash scripts/benchmark-whisper.sh

# 3. Paste results here
```

## Expected comparison

| Metric | whisper-large-v3-turbo | whisper-large-v3 |
|--------|----------------------|------------------|
| Latency | ~700ms (expected) | ~1500ms (expected) |
| Accuracy | Good | Slightly better |
| Languages | All | All |

## Decision

**TBD** — run benchmark first, then decide whether the ~2x latency difference justifies any accuracy gain from the full model.

Current default: `whisper-large-v3-turbo` (chosen for speed in v1.0).
