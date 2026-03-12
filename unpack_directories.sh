#!/usr/bin/env bash
set -euo pipefail

# 1) data.tar.gz 풀기
if [ -f "data.tar.gz" ]; then
  echo "📂 Unpacking data.tar.gz → ./data/"
  tar -xzvf ./data.tar.gz
else
  echo "⚠️  data.tar.gz 파일을 찾을 수 없습니다. 건너뜁니다."
fi

# 2) input.tar.gz 풀기
if [ -f "input.tar.gz" ]; then
  echo "📂 Unpacking input.tar.gz → ./input/"
  tar -xzvf ./input.tar.gz
else
  echo "⚠️  input.tar.gz 파일을 찾을 수 없습니다. 건너뜁니다."
fi
