#!/bin/zsh
#
# Groq verbose_json 驗證工具（一次性 spike，不屬於 App）
#
# 目的是在動 App 程式碼之前，先量到四件事：
#   1. json 與 verbose_json 的 .text 是否逐字元相同
#   2. 長音檔的實際大小與往返耗時（現行 90 秒 timeout 夠不夠）
#   3. segment 橫跨句子的比例（切句演算法要多聰明）
#   4. 長音檔到底需不需要切塊
#
# 用法：
#   export GROQ_API_KEY=...
#   ./scripts/spike-groq-verbose.sh s1 <音檔>      # 兩種 format 比對
#   ./scripts/spike-groq-verbose.sh probe <音檔>   # 單次 verbose 量測
#   ./scripts/spike-groq-verbose.sh convert <輸入> <輸出.m4a>
#
# 產物全部落在 build/spike/（已在 .gitignore）。金鑰只從環境變數讀，不寫入任何檔案。

set -euo pipefail

ROOT="${0:A:h:h}"
OUT="$ROOT/build/spike"
ENDPOINT="https://api.groq.com/openai/v1/audio/transcriptions"
MODEL="whisper-large-v3"
LANGUAGE="zh"
# 與 LanguagePolicy.swift 的 traditionalChinese.transcriptionPrompt 保持一致，
# 否則量到的 avg_logprob 不能代表正式路徑。
PROMPT="繁體中文口述，使用台灣繁體中文字形與自然標點。可能包含英文、macOS、ChatGPT、API、法律及專有名詞。"

die() { print -u2 "錯誤：$1"; exit 1; }

require_key() {
  [[ -n "${GROQ_API_KEY:-}" ]] || die "GROQ_API_KEY 未設定。請先 export GROQ_API_KEY=..."
}

require_tools() {
  for tool in curl jq ffprobe; do
    command -v "$tool" >/dev/null || die "缺少 $tool"
  done
}

# 送出一次轉錄請求。
#   $1 音檔  $2 plain|verbose  $3 產物前綴
# 產出 <前綴>.json 與 <前綴>.headers，並回報耗時。
transcribe() {
  local audio="$1" format="$2" prefix="$3"
  local -a args=(
    -sS -X POST "$ENDPOINT"
    -H "Authorization: Bearer $GROQ_API_KEY"
    -F "file=@$audio"
    -F "model=$MODEL"
    -F "language=$LANGUAGE"
    -F "temperature=0"
    -F "prompt=$PROMPT"
  )

  if [[ "$format" == "verbose" ]]; then
    args+=(-F "response_format=verbose_json")
    args+=(-F "timestamp_granularities[]=segment")
    args+=(-F "timestamp_granularities[]=word")
  else
    args+=(-F "response_format=json")
  fi

  local elapsed
  elapsed=$(curl "${args[@]}" -D "$prefix.headers" -o "$prefix.json" -w '%{time_total}')

  local status
  status=$(head -1 "$prefix.headers" | awk '{print $2}')
  if [[ "$status" != "200" ]]; then
    print -u2 "  HTTP $status —— 回應內容："
    jq . "$prefix.json" 2>/dev/null || cat "$prefix.json"
    die "請求失敗（$format）"
  fi

  print "$elapsed"
}

# 印出剩餘額度，讓消耗看得見。
show_quota() {
  local headers="$1"
  print "  剩餘額度："
  grep -i '^x-ratelimit-remaining\|^x-ratelimit-limit\|^retry-after' "$headers" \
    | sed 's/^/    /' || print "    （回應未帶 rate limit headers）"
}

audio_seconds() {
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" | cut -d. -f1
}

human_size() {
  local bytes
  bytes=$(stat -f%z "$1")
  printf "%d bytes（%.1f MB）" "$bytes" "$((bytes))e-6"
}

# ---------------------------------------------------------------- convert

cmd_convert() {
  [[ $# -eq 2 ]] || die "用法：convert <輸入> <輸出.m4a>"
  require_tools
  mkdir -p "$OUT"
  # 與 App 的錄音設定完全一致：AAC 32 kbps / 16 kHz / 單聲道。
  ffmpeg -y -loglevel error -i "$1" -c:a aac -b:a 32k -ar 16000 -ac 1 "$2"
  print "已轉檔：$2"
  print "  長度：$(audio_seconds "$2") 秒"
  print "  大小：$(human_size "$2")"
}

# ---------------------------------------------------------------- S1

cmd_s1() {
  [[ $# -eq 1 ]] || die "用法：s1 <音檔>"
  require_key; require_tools
  local audio="$1"
  [[ -f "$audio" ]] || die "找不到音檔：$audio"
  mkdir -p "$OUT"

  print "S1：比對 json 與 verbose_json 的 .text"
  print "  音檔：$audio"
  print "  長度：$(audio_seconds "$audio") 秒"
  print "  大小：$(human_size "$audio")"
  print ""

  local t_plain t_verbose
  print "  [1/2] response_format=json"
  t_plain=$(transcribe "$audio" plain "$OUT/s1-plain")
  print "        耗時 ${t_plain}s"

  print "  [2/2] response_format=verbose_json + segment + word"
  t_verbose=$(transcribe "$audio" verbose "$OUT/s1-verbose")
  print "        耗時 ${t_verbose}s"
  print ""

  jq -r '.text' "$OUT/s1-plain.json"   > "$OUT/s1-plain.txt"
  jq -r '.text' "$OUT/s1-verbose.json" > "$OUT/s1-verbose.txt"

  print "  ── 結果 ──"
  if cmp -s "$OUT/s1-plain.txt" "$OUT/s1-verbose.txt"; then
    print "  ✅ .text 逐字元相同"
    print "     → Phase 2 可以寫嚴格的不變性測試"
  else
    print "  ⚠️  .text 不同，差異如下："
    diff "$OUT/s1-plain.txt" "$OUT/s1-verbose.txt" | sed 's/^/     /' || true
    print "     → Phase 2 的不變性測試要針對這個差異設計，不能假裝沒事"
  fi
  print ""
  print "  json 的 text："
  sed 's/^/    /' "$OUT/s1-plain.txt"
  print ""
  show_quota "$OUT/s1-verbose.headers"
}

# ---------------------------------------------------------------- probe

cmd_probe() {
  [[ $# -eq 1 ]] || die "用法：probe <音檔>"
  require_key; require_tools
  local audio="$1"
  [[ -f "$audio" ]] || die "找不到音檔：$audio"
  mkdir -p "$OUT"

  local seconds
  seconds=$(audio_seconds "$audio")
  print "probe：verbose_json 單次量測"
  print "  音檔：$audio"
  print "  長度：${seconds} 秒"
  print "  大小：$(human_size "$audio")"
  print ""

  local elapsed
  elapsed=$(transcribe "$audio" verbose "$OUT/probe")
  print "  往返耗時：${elapsed}s"
  # 介面 A 現行 timeout 是 90 秒；介面 B 傳長音檔可能不夠。
  if (( $(print "$elapsed > 90" | bc -l) )); then
    print "  ⚠️  超過現行 90 秒 timeout，介面 B 必須調高"
  else
    print "  ✅ 未超過現行 90 秒 timeout"
  fi
  print ""

  jq '{
    segments: (.segments | length),
    words: (.words | length),
    duration: .duration,
    language: .language,
    avg_logprob: {
      min: ([.segments[].avg_logprob] | min),
      max: ([.segments[].avg_logprob] | max),
      mean: ([.segments[].avg_logprob] | add / length)
    },
    no_speech_prob_max: ([.segments[].no_speech_prob] | max),
    segment_seconds: {
      min: ([.segments[] | .end - .start] | min),
      max: ([.segments[] | .end - .start] | max),
      mean: ([.segments[] | .end - .start] | add / length)
    },
    segments_containing_sentence_end: [.segments[] | select(.text | test("[。！？]"))] | length,
    segments_ending_at_sentence_end: [.segments[] | select(.text | test("[。！？]\\s*$"))] | length
  }' "$OUT/probe.json" | sed 's/^/  /'

  print ""
  print "  ── 切句難度 ──"
  print "  「含句號但不以句號結尾」的 segment = 橫跨句子，需要重新切句。"
  jq -r '
    ([.segments[] | select((.text | test("[。！？]")) and (.text | test("[。！？]\\s*$") | not))] | length) as $straddle
    | (.segments | length) as $total
    | "  橫跨句子的 segment：\($straddle) / \($total)"
  ' "$OUT/probe.json"

  print ""
  print "  ── word timestamp 覆蓋率 ──"
  jq -r '
    if (.words | length) == 0 then "  ⚠️  沒有 word timestamp"
    else
      ((.words | map(.word) | join("")) | length) as $w
      | (.text | gsub("\\s"; "") | length) as $t
      | "  words 拼接長度 \($w) vs text 長度 \($t)"
    end
  ' "$OUT/probe.json"

  print ""
  show_quota "$OUT/probe.headers"
  print ""
  print "  完整回應：$OUT/probe.json"
}

# ---------------------------------------------------------------- main

[[ $# -ge 1 ]] || {
  print "用法：$0 {s1|probe|convert} ..."
  exit 1
}

case "$1" in
  s1)      shift; cmd_s1 "$@" ;;
  probe)   shift; cmd_probe "$@" ;;
  convert) shift; cmd_convert "$@" ;;
  *)       die "未知的子指令：$1" ;;
esac
