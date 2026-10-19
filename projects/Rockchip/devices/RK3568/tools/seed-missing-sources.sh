#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# seed-missing-sources.sh — 批量预置「缺源码缓存」的包（调用 seed-any-pkg.sh）
#
#   ./seed-missing-sources.sh                  # 先审计再逐个预置
#   ./seed-missing-sources.sh /tmp/audit-missing.tsv
#
# 逐包日志：/tmp/seed-<pkg>.log    总日志：/tmp/seed-missing.log
# 环境变量：MIRROR_BASE / MIRROR_FALLBACK 透传给 seed-any-pkg.sh
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEED="$SCRIPT_DIR/seed-any-pkg.sh"
TSV="${1:-}"

if [ -z "$TSV" ]; then
  bash "$SCRIPT_DIR/audit-missing-sources.sh" > /dev/null || exit 1
  TSV=/tmp/audit-missing.tsv
fi
[ -s "$TSV" ] || { echo "没有需要预置的包（$TSV 为空）"; exit 0; }

echo "== 批量预置开始 $(date '+%F %T')  共 $(grep -c . "$TSV") 个包"
OK=0; FAILED=0; FAILED_LIST=""
while IFS=$'\t' read -r type pkg host url ver; do
  [ -z "${pkg:-}" ] && continue
  echo "---- [$pkg] ($type @ $host)"
  # </dev/null 防止子命令吃掉本循环的 stdin
  if bash "$SEED" "$pkg" </dev/null > "/tmp/seed-$pkg.log" 2>&1; then
    echo "     OK"; OK=$((OK+1))
  else
    echo "     FAIL  (tail /tmp/seed-$pkg.log)"
    tail -4 "/tmp/seed-$pkg.log" | sed 's/^/     | /'
    FAILED=$((FAILED+1)); FAILED_LIST="$FAILED_LIST $pkg"
  fi
done < "$TSV"

echo "== 结束 $(date '+%F %T')  成功=$OK 失败=$FAILED"
[ -n "$FAILED_LIST" ] && echo "   失败清单:$FAILED_LIST"
[ "$FAILED" = 0 ] && echo "== 可继续构建：tools/resume-build.sh"
