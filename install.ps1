# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Nerdless-ship-it
# dsh-adversarial-roundtable 本地安装脚本（Windows / PowerShell 5.1 与 7+ 均可，离线可用）
#
# ⚠ 本文件必须以 UTF-8 **带 BOM** 保存，不要"清理"这个 BOM：
#   Windows PowerShell 5.1 读取无 BOM 的 .ps1 时会按系统 ANSI 代码页解码
#   （英文 Windows 为 1252），本文件里的中文会变成乱码并可能直接触发语法错误。
#   CI 里的 windows job 会在非中文 locale 下实跑本脚本，用来守住这个前提。
#
# 用法: pwsh -File install.ps1 [-Profile web]
#       powershell -ExecutionPolicy Bypass -File install.ps1 [-Profile web]
[CmdletBinding()]
param(
  [string]$Profile = 'web'
)

$ErrorActionPreference = 'Stop'

$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }
$PkgName = 'dsh-adversarial-roundtable'
$SrcDir = $PSScriptRoot
$PluginHome = Join-Path $DshHome "plugins\$PkgName"
$StoreDir = Join-Path $DshHome "profiles\node_modules\$PkgName"
$LegacyStoreDir = Join-Path $DshHome 'profiles\node_modules\@dsh-local\roundtable'
$PatchFile = Join-Path $DshHome 'cordis.patch.yml'

$PatchBlock = @"
# roundtable plugin:start
- insert:
    - id: roundtable
      name: '$PkgName'
# roundtable plugin:end
"@

# 只装运行期文件：devDependencies 的 node_modules、.git、CI 配置不进 store
$ExcludeNames = @('node_modules', '.git', '.github')

function Copy-PluginTree {
  param([string]$From, [string]$To)
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  Get-ChildItem -LiteralPath $From -Force |
    Where-Object { $ExcludeNames -notcontains $_.Name } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $To -Recurse -Force }
}

Write-Host "==> $PkgName 本地安装（profile: $Profile）"

# 1. 源码落到长期目录（脚本已在长期目录运行时跳过，避免自毁）
$srcFull = [System.IO.Path]::GetFullPath($SrcDir).TrimEnd('\')
$dstFull = [System.IO.Path]::GetFullPath($PluginHome).TrimEnd('\')
if ($srcFull -eq $dstFull) {
  Write-Host '✓ 脚本已在长期目录运行，跳过源码拷贝'
} else {
  New-Item -ItemType Directory -Force -Path (Join-Path $DshHome 'plugins') | Out-Null
  if (Test-Path -LiteralPath $PluginHome) { Remove-Item -LiteralPath $PluginHome -Recurse -Force }
  Copy-PluginTree -From $SrcDir -To $PluginHome
  Write-Host "✓ 源码已安装到 $PluginHome"
}

# 2. 语法检查
if (Get-Command node -ErrorAction SilentlyContinue) {
  & node --check (Join-Path $PluginHome 'index.mjs')
  if ($LASTEXITCODE -ne 0) { throw 'index.mjs 语法检查失败' }
  Write-Host '✓ index.mjs 语法检查通过'
} else {
  Write-Host '! 未找到 node，跳过语法检查'
}

# 3. 装入 profile 共享 store（必须实体拷贝，非 symlink）
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StoreDir) | Out-Null
if (Test-Path -LiteralPath $StoreDir) { Remove-Item -LiteralPath $StoreDir -Recurse -Force }
Copy-PluginTree -From $PluginHome -To $StoreDir
Write-Host "✓ 已安装到 $StoreDir"

# 4. 写入补丁行（幂等；显式 UTF-8 无 BOM，避免污染含中文的 patch 文件）
$hasPatch = (Test-Path -LiteralPath $PatchFile) -and
            (Select-String -LiteralPath $PatchFile -SimpleMatch 'roundtable plugin:start' -Quiet)
if ($hasPatch) {
  Write-Host '✓ 补丁行已存在，跳过'
} else {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::AppendAllText($PatchFile, "`n$PatchBlock`n", $utf8NoBom)
  Write-Host "✓ 已写入 $PatchFile"
}

# 5. 组成校验（dsh 可用时）
# 注意：dump-config 只给需要引号的包名加引号（如 '@scope/name'），无 scope 的裸包名是
# `name: dsh-adversarial-roundtable`，因此这里按子串匹配，不要匹配带引号的形式。
if (Get-Command dsh -ErrorAction SilentlyContinue) {
  $dump = & dsh --profile $Profile --dump-config 2>$null | Out-String
  if ($dump -match [regex]::Escape($PkgName)) {
    Write-Host "✓ 组成校验通过（dump-config 含 $PkgName）"
  } else {
    Write-Host "! dump-config 未找到该包名，请检查 $PatchFile 与 store 是否就位"
  }
} else {
  Write-Host '! 未找到 dsh 命令，跳过组成校验'
}

# 6. 旧包名遗留提示（不自动删除，避免误删用户手动维护的副本）
if (Test-Path -LiteralPath $LegacyStoreDir) {
  Write-Host "! 检测到旧包名遗留目录：$LegacyStoreDir"
  Write-Host '  补丁行已指向新包名，该目录不会被挂载；确认新版本正常后可手动删除。'
}

Write-Host ''
Write-Host '安装完成。重启 DSH 生效：停掉当前 dsh web 进程后重新运行 dsh web'
Write-Host '验证：新会话里调用 roundtable_models / roundtable 工具'
