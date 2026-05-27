<?php

/**
 * 极速版：诊断增强版
 * 解决“没有播放线路”问题
 */

// 取消脚本执行时间限制

/**
 * 极速版：使用 curl_multi 并发下载 + (可选) 并发验证
 * 
 * 配置说明：
 * $enableValidation = false; -> 跳过验证，极速合并（推荐，避免超时）
 * $enableValidation = true;  -> 启用验证，筛选有效链接（耗时较长）
 */

// ================= 配置区域 =================
$enableValidation = false; // 【开关】是否启用链接有效性检测
// ===========================================

set_time_limit(0); 
ignore_user_abort(true);

function mergeAndConvertUrlsToFile(array $urlList, string $targetFile): void {
    $startTime = microtime(true);
    
    // 1. 定义优质源关键词
    $priorityKeywords = ['Guovin', 'fanmingming', 'YueChan', 'tv.iill'];
    
    // 2. 排序：优质源排前面
    usort($urlList, function($a, $b) use ($priorityKeywords) {
        $aScore = $bScore = 0;
        foreach ($priorityKeywords as $kw) {
            if (stripos($a, $kw) !== false) $aScore++;
            if (stripos($b, $kw) !== false) $bScore++;
        }
        return $bScore - $aScore;
    });

    // ==========================================
    // 第一阶段：并发下载
    // ==========================================
    echo "阶段 1/3：并发下载源文件...\n";
    $contents = fetchUrlsConcurrent($urlList);

    // ==========================================
    // 第二阶段：解析并转换格式
    // ==========================================
    echo "\n阶段 2/3：解析并转换格式...\n";
    $allLines = [];
    
    foreach ($urlList as $url) {
        if (!isset($contents[$url])) {
            echo "  ❌ 下载失败: {$url}\n";
            continue;
        }
        
        if (empty($contents[$url])) {
            echo "  ⚠️ 内容为空: {$url}\n";
            continue;
        }

        $isPriority = false;
        foreach ($priorityKeywords as $kw) {
            if (stripos($url, $kw) !== false) { $isPriority = true; break; }
        }
        echo "  ✅ 解析: {$url} (长度: " . strlen($contents[$url]) . " 字节) " . ($isPriority ? "[优选]" : "") . "\n";

        $parsed = convertM3uToTxt($contents[$url]);
        echo "     -> 提取到 " . count($parsed) . " 条数据\n";
        
        foreach ($parsed as $line) {
            $allLines[] = $line;
        }
    }

    if (empty($allLines)) {
        echo "\n🚨 错误：没有提取到任何数据。请检查源地址是否失效。\n";
        return;
    }

    // ==========================================
    // 第三阶段：(跳过验证) 直接合并
    // ==========================================
    echo "\n阶段 3/3：合并数据...\n";
    $validLines = formatLinesWithoutValidation($allLines);

    // 写入文件
    $targetDir = dirname($targetFile);
    if (!is_dir($targetDir)) mkdir($targetDir, 0755, true);
    
    file_put_contents($targetFile, implode("\n", $validLines) . "\n");
    @chmod($targetFile, 0644);

    $endTime = microtime(true);
    $duration = round($endTime - $startTime, 2);
    
    echo "\n✅ 全部处理完成！\n";
    echo "总链接数: " . (count($validLines) - count(array_filter($validLines, function($v){ return strpos($v, '#genre#') !== false; }))) . " 条\n";
    echo "结果已保存至 {$targetFile}\n";
    echo "总耗时: {$duration} 秒\n";
}


function formatLinesWithoutValidation(array $lines): array {
    $finalLines = [];
    $groupedData = [];
    $groupOrder = [];

    foreach ($lines as $item) {
        if (is_string($item)) {
            // 处理分组头
            $groupName = trim(str_replace(',#genre#', '', $item));
            if (!empty($groupName)) {
                if (!isset($groupedData[$groupName])) {
                    $groupedData[$groupName] = [];
                    $groupOrder[$groupName] = true;
                }
            }
        } elseif (is_array($item)) {
            // 处理链接行
            $group = $item['group'] ?: '未分组';
            $lineStr = $item['name'] . ',' . $item['url'];

            if (!isset($groupedData[$group])) {
                $groupedData[$group] = [];
                if (!isset($groupOrder[$group])) {
                    $groupOrder[$group] = true;
                }
            }
            $groupedData[$group][] = $lineStr;
        }
    }

    foreach (array_keys($groupOrder) as $group) {
        $finalLines[] = $group . ',#genre#';
        if (isset($groupedData[$group])) {
            foreach ($groupedData[$group] as $line) {
                $finalLines[] = $line;
            }
        }
    }
    return $finalLines;
}


function fetchUrlsConcurrent(array $urls): array {
    $results = [];
    $handles = [];
    $mh = curl_multi_init();

    foreach ($urls as $i => $url) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_CONNECTTIMEOUT => 5, // 连接超时改为 5 秒
            CURLOPT_USERAGENT      => 'IPTV-Merger/1.0',
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_SSL_VERIFYHOST => false,
        ]);
        curl_multi_add_handle($mh, $ch);
        $handles[$i] = $ch;
    }

    $active = null;
    do {
        $mrc = curl_multi_exec($mh, $active);
    } while ($mrc == CURLM_CALL_MULTI_PERFORM);

    while ($active && $mrc == CURLM_OK) {
        if (curl_multi_select($mh) == -1) {
            usleep(100);
        }
        do {
            $mrc = curl_multi_exec($mh, $active);
        } while ($mrc == CURLM_CALL_MULTI_PERFORM);
    }

    foreach ($urls as $i => $url) {
        $content = curl_multi_getcontent($handles[$i]);
        $httpCode = curl_getinfo($handles[$i], CURLINFO_HTTP_CODE);
        
        if ($content !== false && $httpCode >= 200 && $httpCode < 400) {
            $results[$url] = $content;
        } else {
            $results[$url] = null;
        }
        curl_multi_remove_handle($mh, $handles[$i]);
        curl_close($handles[$i]);
    }
    curl_multi_close($mh);
    
    return $results;
}


function convertM3uToTxt(string $content): array {
    $items = [];
    $lines = explode("\n", $content);
    $currentChannelName = '';
    $currentGroup = '';
    $txtLastGroup = '';

    foreach ($lines as $line) {
        $line = trim($line);
        if (empty($line)) continue;

        // 1. TXT 分组头
        if (strpos($line, '#genre#') !== false) {
            $parts = explode(',', $line, 2);
            $txtLastGroup = trim($parts[0]);
            $items[] = $line; 
            continue;
        }

        // 2. M3U 信息头
        if (stripos($line, '#EXTINF') === 0) {
            $currentGroup = '';
            if (preg_match('/group-title="([^"]+)"/', $line, $matches)) {
                $currentGroup = $matches[1];
            }
            $lastCommaPos = strrpos($line, ',');
            if ($lastCommaPos !== false) {
                $currentChannelName = trim(substr($line, $lastCommaPos + 1));
            }
            continue;
        }

        // 3. 链接行判断逻辑 (放宽条件)
        // 只要包含 http, https, rtmp, rtp, mms 等常见协议头，或者纯 m3u8 结尾
        $isStreamLink = false;
        if (preg_match('/^(http|https|rtmp|rtp|mms|igmp):\/\//i', $line)) {
            $isStreamLink = true;
        }
        
        // 如果是 M3U 模式 (有名字)
        if (!empty($currentChannelName)) {
            if ($isStreamLink) {
                $items[] = [
                    'name'  => $currentChannelName,
                    'url'   => $line,
                    'group' => $currentGroup
                ];
            }
            $currentChannelName = '';
            $currentGroup = '';
        } 
        // 如果是 TXT 模式 (名字,链接)
        elseif (strpos($line, ',') !== false) {
            $parts = explode(',', $line, 2);
            $name = trim($parts[0]);
            $url = trim($parts[1]);
            // 检查 URL 部分是否有效
            if (preg_match('/^(http|https|rtmp|rtp|mms|igmp):\/\//i', $url)) {
                $items[] = [
                    'name'  => $name,
                    'url'   => $url,
                    'group' => $txtLastGroup
                ];
            }
        }
    }
    return $items;
}


// ================= 执行 =================

// 建议您测试一下这些源是否有效，或者换一个您确定可用的源测试
$urlsToMerge = [
    "https://raw.githubusercontent.com/gjx0753/live/main/live.txt",
    "http://iptv.4666888.xyz/FYTV.m3u",
    "https://gjx.serv00.net/tvbox/live.txt"
];

$destinationFile = './live.txt'; 
mergeAndConvertUrlsToFile($urlsToMerge, $destinationFile);

?>
