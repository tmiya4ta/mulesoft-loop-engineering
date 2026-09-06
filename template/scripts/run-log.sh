#!/usr/bin/env bash
# 配布・完了・レビューを 1 行ずつ記録する。指標と予算の唯一の元データ。
# 使い方: run-log.sh dispatch T-014 sonnet | run-log.sh done T-014 passed 132 | run-log.sh review request-changes 3
set -u
mkdir -p knowledge
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
case "${1:-}" in
  dispatch) printf '{"ts":"%s","event":"dispatch","task":"%s","model":"%s"}\n' "$ts" "${2:-}" "${3:-}" ;;
  done)     printf '{"ts":"%s","event":"done","task":"%s","result":"%s","seconds":%s}\n' "$ts" "${2:-}" "${3:-}" "${4:-0}" ;;
  review)   printf '{"ts":"%s","event":"review","verdict":"%s","findings":%s}\n' "$ts" "${2:-}" "${3:-0}" ;;
  *) echo "usage: run-log.sh dispatch|done|review ..." >&2; exit 2 ;;
esac >> knowledge/run-log.jsonl
