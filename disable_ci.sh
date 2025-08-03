#!/bin/bash
set -euo pipefail

# 文件路径
src=".github/workflows/test.yml"
dst="${src}.disabled"

# 确保在 git 仓库根目录运行
if [ ! -d .git ]; then
  echo "错误：当前目录不是一个 git 仓库（.git 目录不存在）"
  exit 1
fi

# 重命名 workflow 文件
if [ -f "$src" ]; then
  if [ -f "$dst" ]; then
    echo "注意：目标已存在，跳过重命名（$dst 已存在）"
  else
    mv "$src" "$dst"
    echo "已重命名 $src -> $dst"
  fi
else
  echo "警告：源文件不存在，跳过重命名：$src"
fi

# 提交并推送
git add -A
git diff --staged --quiet || {
  git commit -m "临时禁用 GitHub Actions 流水线"
  git push
  echo "提交并推送完成"
  exit 0
}

echo "没有更改要提交"

# chmod +x disable_ci.sh
# ./disable_ci.sh