#!/bin/bash
LINE="$1"
RESULT_FILE="valid_results/$BASHPID.tmp"

# 提取 URL：从第一个 http 开始截取到行末
URL=$(echo "$LINE" | sed 's/.*\(https\?:\/\/\)/\1/')
if [ -z "$URL" ]; then
  exit 1
fi

# 尝试下载前 500KB 数据，超时 8 秒
CONTENT_TYPE=$(curl -sS -m 8 -r 0-500000 -o /dev/null -w "%{content_type}" -L "$URL" 2>/dev/null)

# 检查 Content-Type 是否为音视频流或二进制流
if [[ "$CONTENT_TYPE" =~ (video|audio|octet-stream|mpegurl|mp2t) ]]; then
  # 写入进程独立的临时文件
  echo "$LINE" > "$RESULT_FILE"
fi

