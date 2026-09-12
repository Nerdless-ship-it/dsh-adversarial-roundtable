#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Nerdless-ship-it
# dsh-adversarial-roundtable 本地安装脚本（离线可用）
# 用法: bash install.sh [--profile <name>]   （默认 profile: web）
set -euo pipefail

PROFILE="web"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-web}"; shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PKG_NAME="dsh-adversarial-roundtable"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_HOME="$DSH_HOME/plugins/dsh-adversarial-roundtable"
STORE_DIR="$DSH_HOME/profiles/node_modules/dsh-adversarial-roundtable"
LEGACY_STORE_DIR="$DSH_HOME/profiles/node_modules/@dsh-local/roundtable"
PATCH_FILE="$DSH_HOME/cordis.patch.yml"
PATCH_BLOCK="# roundtable plugin:start
- insert:
    - id: roundtable
      name: '$PKG_NAME'
# roundtable plugin:end"

echo "==> dsh-adversarial-roundtable 本地安装（profile: ${PROFILE}）"

# 1. 源码落到长期目录（脚本已在长期目录运行时跳过，避免自毁）
if [[ "$SRC_DIR" == "$PLUGIN_HOME" ]]; then
  echo "✓ 脚本已在长期目录运行，跳过源码拷贝"
else
  mkdir -p "$DSH_HOME/plugins"
  rm -rf "$PLUGIN_HOME"
  cp -R "$SRC_DIR" "$PLUGIN_HOME"
  # 只装运行期文件：不把 devDependencies 的 node_modules 与 .git 带进 store
  rm -rf "$PLUGIN_HOME/node_modules" "$PLUGIN_HOME/.git"
  echo "✓ 源码已安装到 $PLUGIN_HOME"
fi

# 2. 语法检查
if command -v node >/dev/null 2>&1; then
  node --check "$PLUGIN_HOME/index.mjs"
  echo "✓ index.mjs 语法检查通过"
else
  echo "! 未找到 node，跳过语法检查"
fi

# 3. 装入 profile 共享 store（必须实体拷贝，非 symlink）
mkdir -p "$(dirname "$STORE_DIR")"
rm -rf "$STORE_DIR"
cp -R "$PLUGIN_HOME" "$STORE_DIR"
echo "✓ 已安装到 $STORE_DIR"

# 4. 写入补丁行（幂等）
if [[ -f "$PATCH_FILE" ]] && grep -q "roundtable plugin:start" "$PATCH_FILE"; then
  echo "✓ 补丁行已存在，跳过"
else
  printf '\n%s\n' "$PATCH_BLOCK" >> "$PATCH_FILE"
  echo "✓ 已写入 $PATCH_FILE"
fi

# 5. 组成校验（dsh 可用时）
# 注意：dump-config 只给需要引号的包名加引号（如 '@scope/name'），无 scope 的裸包名是
# `name: dsh-adversarial-roundtable`，因此这里按子串匹配，不要匹配带引号的形式。
if command -v dsh >/dev/null 2>&1; then
  DUMP="$(dsh --profile "$PROFILE" --dump-config 2>/dev/null || true)"
  if [[ "$DUMP" == *"$PKG_NAME"* ]]; then
    echo "✓ 组成校验通过（dump-config 含 ${PKG_NAME}）"
  else
    echo "! dump-config 未找到该包名，请检查 $PATCH_FILE 与 store 是否就位"
  fi
else
  echo "! 未找到 dsh 命令，跳过组成校验"
fi

# 6. 旧包名遗留提示（不自动删除，避免误删用户手动维护的副本）
if [[ -d "$LEGACY_STORE_DIR" ]]; then
  echo "! 检测到旧包名遗留目录：$LEGACY_STORE_DIR"
  echo "  补丁行已指向新包名，该目录不会被挂载；确认新版本正常后可手动删除。"
fi

echo ""
echo "安装完成。重启 DSH 生效：停掉当前 dsh web 进程后重新运行 dsh web"
echo "验证：新会话里调用 roundtable_models / roundtable 工具"
