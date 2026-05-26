#!/bin/bash

echo "Starting IPTV Script..."

# 初始化文件
> live_all_raw.txt
> live_valid.txt
> live_deduped.txt
> failed_sources.txt
> validation_report.txt
> success_sources.txt

# 优先级
declare -A SOURCE_PRIORITY=(["Guovin"]=10 ["fanmingming"]=20 ["YueChan"]=30 ["myIPTV"]=40 ["Default"]=99)

# 统计
declare -i total_sources=0 success_count=0 failed_count=0 total_fetched=0 valid_channels=0 invalid_channels=0

convert_m3u_to_txt() {
  awk 'BEGIN { channel="" } /^#EXTINF/ { n=split($0, a, ","); channel=a[n]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", channel); next } /^http/ { if (channel != "") { print channel "," $0; channel="" } else { print $0 } }'
}

fetch_and_merge() {
  local url="$1" name="$2" prio="${SOURCE_PRIORITY[$name]:-${SOURCE_PRIORITY[Default]}}"
  total_sources=$((total_sources + 1))
  echo "[$total_sources] Fetching: $name"
  
  local raw="" attempt=0
  while [ $attempt -lt 3 ]; do
    attempt=$((attempt + 1))
    
    raw=$(curl -sL --connect-timeout 15 --max-time 30 -k --retry 2 --retry-delay 1 --retry-all-errors -H "User-Agent: Mozilla/5.0" "$url" 2>&1) || true
    
    if [ $? -eq 0 ] && [ -n "$raw" ] && [[ ! "$raw" =~ ^<.*>$ ]]; then
      if [[ "$raw" == *"EXTINF"* ]]; then
        echo "$raw" | convert_m3u_to_txt | awk -v p="$prio" '{print $0 "," p}' >> live_all_raw.txt
        local c=$(echo "$raw" | convert_m3u_to_txt | wc -l)
      else
        echo "$raw" | awk -v p="$prio" '{print $0 "," p}' >> live_all_raw.txt
        local c=$(echo "$raw" | wc -l)
      fi
      success_count=$((success_count + 1))
      total_fetched=$((total_fetched + c))
      echo "$name - OK - $c channels" >> success_sources.txt
      return 0
    fi
    sleep 2
  done
  
  echo "$name - FAILED" >> failed_sources.txt
  failed_count=$((failed_count + 1))
  return 1
}

# 执行抓取
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

# 输出统计
echo "success_count=$success_count" >> $GITHUB_OUTPUT
echo "failed_count=$failed_count" >> $GITHUB_OUTPUT
echo "total_raw_channels=$total_fetched" >> $GITHUB_OUTPUT
echo "valid_channels=$valid_channels" >> $GITHUB_OUTPUT
echo "invalid_channels=$invalid_channels" >> $GITHUB_OUTPUT

# 去重
if [ -s live_all_raw.txt ]; then
  sort -t',' -k3,3n live_all_raw.txt | awk -F',' '!seen[$1]++' > live_deduped.txt
fi

# 验证
if [ -s live_deduped.txt ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    url="${line##*,}"
    if [[ ! "$url" =~ ^https?:// ]]; then
      echo "$line" >> live_valid.txt
      valid_channels=$((valid_channels + 1))
    else
      status=$(curl -I -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 -k "$url" 2>/dev/null) || true
      if [[ "$status" =~ ^[23][0-9]{2}$ ]]; then
        echo "$line" >> live_valid.txt
        valid_channels=$((valid_channels + 1))
      else
        invalid_channels=$((invalid_channels + 1))
      fi
    fi
  done < live_deduped.txt
fi

# 更新统计到输出
echo "valid_channels=$valid_channels" >> $GITHUB_OUTPUT
echo "invalid_channels=$invalid_channels" >> $GITHUB_OUTPUT

# 分类
cp live_valid.txt live.txt || true
grep -iE "CCTV|央视" live_valid.txt > CCTV.txt || touch CCTV.txt
grep -iE "卫视|湖南|浙江|江苏|东方|北京|广东|深圳" live_valid.txt > Satellite.txt || touch Satellite.txt
grep -viE "CCTV|央视|卫视|湖南|浙江|江苏|东方|北京|广东|深圳" live_valid.txt > Regional.txt || touch Regional.txt

echo "Script Finished."
