#!/bin/bash

# ==========================
# 1. M3U 转 TXT 及格式清洗
# ==========================
INPUT_FILE="$1"
OUTPUT_FILE="$2"

awk '
/^#EXTINF/ {
    n = split($0, a, ",")
    channel_name = a[n]
    gsub(/^[ \t]+|[ \t]+$/, "", channel_name)
    getline
    url = $0
    gsub(/^[ \t]+|[ \t]+$/, "", url)
    if (url ~ /^http/ && channel_name != "") {
        print channel_name "," url
    }
    next
}
/^#EXTM3U/ { next }
/^#/ { next }
{
    line = $0
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line ~ /^http/) {
        print "Unknown," line
    } else if (line ~ /,/) {
        print line
    } else if (line ~ /[ \t]/) {
        sub(/[ \t]+/, ",", line)
        print line
    }
}
' "$INPUT_FILE" > "$OUTPUT_FILE"

# ==========================
# 2. 频道有效性验证
# ==========================
LINE="$3"
RESULT_FILE="$4"

URL=$(echo "$LINE" | sed 's/.*\(https\?:\/\/\)/\1/')
if [ -z "$URL" ]; then
  exit 1
fi

CONTENT_TYPE=$(curl -sS -m 8 -r 0-500000 -o /dev/null -w "%{content_type}" -L "$URL" 2>/dev/null)

if [[ "$CONTENT_TYPE" =~ (video|audio|octet-stream|mpegurl|mp2t) ]]; then
  echo "$LINE" > "$RESULT_FILE"
fi
