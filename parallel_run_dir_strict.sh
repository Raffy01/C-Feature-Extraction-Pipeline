#!/usr/bin/env bash
set -euo pipefail

MAXJOBS=8
DATA_ROOT="./data"

# 디렉토리를 순서대로 하나씩 처리
for dir in "${DATA_ROOT}"/*/; do
    # dir 경로가 실제 디렉토리인지 확인
    [[ -d "$dir" ]] || continue

    # 해당 디렉토리 내 *.c 파일을 하나씩 순차 처리
    for cfile in "$dir"/C/*.c; do
        [[ -f "$cfile" ]] || continue  # .c 파일이 없으면 넘어감

        # 백그라운드 job 수가 MAXJOBS 이상이면 대기
        while [ "$(jobs -rp | wc -l)" -ge "$MAXJOBS" ]; do
            sleep 1
        done

        # 여기서 분석(또는 컴파일) 스크립트를 백그라운드로 실행
        ./extract_file.sh "$cfile" &
    done

    # 하나의 디렉토리를 모두 백그라운드로 띄웠으면,
    # 현재 디렉토리 안의 모든 백그라운드 job이 끝날 때까지 기다리며
    # 다음 디렉토리로 넘어가지 않도록 할 수도 있다.
    wait 
done

# 마지막으로 남은 백그라운드 job이 모두 끝날 때까지 대기
wait

