#!/bin/bash

set +e

echo "========================================"
echo "IPTV Script Started at $(date)"
echo "========================================"

# 确保工作目录
cd "${GITHUB_WORKSPACE:-.}"

# 初始化文件
echo "[Init] Creating files..."
: > live_all_raw.txt
: > live_valid.txt
: > live_deduped.txt
: > failed_sources.txt
: > validation_report.txt
: > success_sources.txt

# 输出文件 - 使用绝对路径
GITHUB_OUTPUT_FILE="${GITHUB_WORKSPACE:-.}/iptv_outputs.txt"
: > "$GITHUB_OUTPUT_FILE"
echo "[Init] Output file: $GITHUB_OUTPUT_FILE"

# 优先级
declare -A SOURCE_PRIORITY=(["Guovin"]=10 ["fanmingming"]=20 ["YueChan"]=30 ["myIPTV"]=40 ["Default"]=99)

# 统计变量
declare -i total_sources=0
declare -i success_count=0
declare -i failed_count=0
declare -i total_fetched=0
declare -i valid_channels=0
declare -i invalid_channels=0

convert_m3u_to_txt() {
  awk 'BEGIN { channel="" } 
       /^#EXTINF/ { 
         n=split($0, a, ","); 
         channel=a[n]; 
         gsub(/^[[:space:]]+|[[:space:]]+$/, "", channel); 
         next 
       } 
       /^http/ { 
         if (channel != "") { 
           print channel "," $0; 
           channel="" 
         } else { 
           print $0 
         } 
       }'
}

fetch_and_merge() {
  local url="$1"
  local name="$2"
  local prio="${SOURCE_PRIORITY[$name]:-${SOURCE_PRIORITY[Default]}}"
  
  total_sources=$((total_sources + 1))
  echo "[$total_sources] Fetching: $name"
  
  local raw_content=""
  local attempt=0
  local max_attempts=3
  
  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    
    raw_content=$(curl -sL \
      --connect-timeout 15 \
      --max-time 30 \
      -k \
      --retry 2 \
      --retry-delay 1 \
      --retry-all-errors \
      -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
      -H "Accept: */*" \
      "$url" 2>&1)
    
    local curl_exit_code=$?
    
    if [ $curl_exit_code -eq 0 ] && [ -n "$raw_content" ]; then
      if [[ ! "$raw_content" =~ ^<.*>$ ]]; then
        echo "   OK - Attempt $attempt"
        
        if [[ "$raw_content" == *"EXTINF"* ]]; then
          echo "$raw_content" | convert_m3u_to_txt | awk -v p="$prio" '{print $0 "," p}' >> live_all_raw.txt
          local count=$(echo "$raw_content" | convert_m3u_to_txt | wc -l)
        else
          echo "$raw_content" | awk -v p="$prio" '{print $0 "," p}' >> live_all_raw.txt
          local count=$(echo "$raw_content" | wc -l)
        fi
        
        success_count=$((success_count + 1))
        total_fetched=$((total_fetched + count))
        echo "$name - OK - $count channels" >> success_sources.txt
        return 0
      fi
    fi
    
    echo "   Attempt $attempt failed"
    if [ $attempt -lt $max_attempts ]; then
      sleep 2
    fi
  done
  
  echo "   FAILED after $max_attempts attempts"
  echo "$name - $url - Exit $curl_exit_code" >> failed_sources.txt
  failed_count=$((failed_count + 1))
  return 1
}

echo "[Fetch] Starting source fetching..."
fetch_and_merge "https://raw.githubusercontent.com/Guovin/iptv-api/gd/output/ipv6/result.m3u" "Guovin-IPv6"
fetch_and_merge "https://raw.githubusercontent.com/Guovin/iptv-api/gd/output/ipv4/result.m3u" "Guovin-IPv4"
fetch_and_merge "https://live.fanmingming.cn/tv/m3u/ipv6.m3u" "fanmingming"
fetch_and_merge "https://raw.githubusercontent.com/jn950/live/main/tv/pllive.txt" "jn950"
fetch_and_merge "https://raw.githubusercontent.com/YueChan/Live/main/GNTV.m3u" "YueChan-GNTV"
fetch_and_merge "https://raw.githubusercontent.com/YueChan/Live/main/Global.m3u" "YueChan-Global"
fetch_and_merge "https://raw.githubusercontent.com/YueChan/Live/main/Hunan.txt" "YueChan-Hunan"
fetch_and_merge "https://raw.githubusercontent.com/YueChan/Live/main/IPTV.m3u" "YueChan-IPTV"
fetch_and_merge "https://raw.githubusercontent.com/YueChan/Live/main/Radio.m3u" "YueChan-Radio"
fetch_and_merge "https://tv.iill.top/m3u/Gather" "YanG-1989"
fetch_and_merge "https://live.zbds.org/tv/iptv6.m3u" "vbskycn-IPv6"
fetch_and_merge "https://live.zbds.org/tv/iptv4.m3u" "vbskycn-IPv4"
fetch_and_merge "https://raw.githubusercontent.com/Kimentanm/aptv/master/m3u/iptv.m3u" "Kimentanm"
fetch_and_merge "https://raw.githubusercontent.com/BurningC4/Chinese-IPTV/master/TV-IPV4.m3u" "BurningC4"
fetch_and_merge "https://raw.githubusercontent.com/zwc456baby/iptv_alive/refs/heads/master/live.m3u" "zwc456baby"
fetch_and_merge "https://raw.githubusercontent.com/hujingguang/ChinaIPTV/main/cnTV_AutoUpdate.m3u8" "ChinaIPTV"
fetch_and_merge "https://raw.githubusercontent.com/suxuang/myIPTV/refs/heads/main/ipv4.m3u" "myIPTV-IPv4"
fetch_and_merge "https://raw.githubusercontent.com/suxuang/myIPTV/refs/heads/main/ipv6.m3u" "myIPTV-IPv6"
fetch_and_merge "http://tttttt.tttttttttt.top/jk.txt" "传说引导页"
fetch_and_merge "https://m3u.ibert.me/fmml_ipv6.m3u" "iptv-sources"
fetch_and_merge "https://raw.githubusercontent.com/joevess/IPTV/main/m3u/iptv.m3u" "joevess"
fetch_and_merge "https://raw.githubusercontent.com/Ftindy/IPTV-URL/main/IPV6.m3u" "Ftindy"
fetch_and_merge "https://aktv.space/live.m3u" "AKTV"

echo "[Fetch] Summary: $success_count OK, $failed_count Failed"

# 写入统计数据
{
  echo "success_count=$success_count"
  echo "failed_count=$failed_count"
  echo "total_raw_channels=$total_fetched"
} >> "$GITHUB_OUTPUT_FILE"

# 去重
echo "[Dedupe] Starting deduplication..."
if [ -s live_all_raw.txt ]; then
  sort -t',' -k3,3n live_all_raw.txt | awk -F',' '!seen[$1]++' > live_deduped.txt
  echo "[Dedupe] Done."
else
  echo "[Dedupe] No data to deduplicate."
  : > live_deduped.txt
fi

# 验证
echo "[Valid] Starting validation..."
if [ -s live_deduped.txt ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    
    url="${line##*,}"
    
    if [[ ! "$url" =~ ^https?:// ]]; then
      echo "$line" >> live_valid.txt
      valid_channels=$((valid_channels + 1))
      continue
    fi
    
    status=$(curl -I -s -o /dev/null -w "%{http_code}" \
      --connect-timeout 3 \
      --max-time 5 \
      -k \
      "$url" 2>/dev/null)
    
    if [[ "$status" =~ ^[23][0-9]{2}$ ]]; then
      echo "$line" >> live_valid.txt
      valid_channels=$((valid_channels + 1))
    else
      echo "[$status] $url" >> validation_report.txt
      invalid_channels=$((invalid_channels + 1))
    fi
  done < live_deduped.txt
  echo "[Valid] Result: $valid_channels Valid, $invalid_channels Invalid"
else
  echo "[Valid] No data to validate."
  : > live_valid.txt
fi

# 更新最终统计
{
  echo "valid_channels=$valid_channels"
  echo "invalid_channels=$invalid_channels"
} >> "$GITHUB_OUTPUT_FILE"

# 分类
echo "[Category] Categorizing channels..."
cp live_valid.txt live.txt 2>/dev/null || : > live.txt
grep -iE "CCTV|央视" live_valid.txt > CCTV.txt 2>/dev/null || : > CCTV.txt
grep -iE "卫视|湖南|浙江|江苏|东方|北京|广东|深圳" live_valid.txt > Satellite.txt 2>/dev/null || : > Satellite.txt
grep -viE "CCTV|央视|卫视|湖南|浙江|江苏|东方|北京|广东|深圳" live_valid.txt > Regional.txt 2>/dev/null || : > Regional.txt

echo "========================================"
echo "Script Finished Successfully"
echo "========================================"
exit 0
