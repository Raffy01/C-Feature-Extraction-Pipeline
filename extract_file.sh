#!/usr/bin/env bash
set -euo pipefail

########################################
# 1) 한 파일만 처리하는 함수 정의
########################################
process_one_file() {
  local SRC="$1"        # 예: "/path/to/data/p00001/C/example.c"
  local DIR_BASE="$2"   # 예: "/path/to/data" (원본 데이터 루트)
  local CSV_OUT="$3"    # 예: "features.csv"

  FILE=$(basename "$SRC")           # ex) "example.c"
  BASE="${FILE%.c}"                 # ex) "example"
  foldername=$(basename "$(dirname "$(dirname "$SRC")")") 
    # ex) /path/to/data/p00001/C → dirname: /path/to/data/p00001 → basename: p00001

  echo "▶ Processing $FILE …" >&2   # stderr로 출력해 진행 상황 확인

  {
    # ==== 덤프·컴파일·피처 추출 로직 ====
    BIN="${BASE}.o"
    CGRAPH="${BASE}.fdump.ipa.cgraph"
    LOOPS="${BASE}.fdump.loop"
    GIMPLE="${BASE}.fdump.gimple"
    EXPAND="${BASE}.fdump.expand"
    CFG="${BASE}.fdump.cfg"
    DOT="${BASE}.fdump.cfg.dot"
    EXE="${BASE}.exe"

    # (1) GCC로 덤프 생성
    gcc -O2 \
      -fdump-ipa-cgraph="$CGRAPH" \
      -fdump-tree-loop="$LOOPS" \
      -fdump-tree-gimple="$GIMPLE" \
      -fdump-rtl-expand="$EXPAND" \
      -fdump-tree-cfg-graph="$CFG" \
      -c "$SRC" -o "$BIN" 2>/dev/null

    # --- Static features f1–f13 ---
    f1=$(grep -c -E ';$'       "$GIMPLE" 2>/dev/null || true)
    f2=$(grep -E '[^=]=.*[-+*]|cmp' "$GIMPLE" 2>/dev/null | wc -l)
    f3=$(grep -c 'mem'         "$EXPAND" 2>/dev/null || true)
    f4=$(grep -c '<bb [0-9]\+>' "$CFG"    2>/dev/null || true)
    f5=$(grep -c -E '^[[:space:]]*if[[:space:]]*\(|switch' "$GIMPLE" 2>/dev/null || true)

    E=$(grep -c '->'      "$DOT" 2>/dev/null || true)
    N=$(grep -c 'label =' "$DOT" 2>/dev/null || true)
    P=$(grep -c '^\s*subgraph cluster_' "$DOT" 2>/dev/null || true)
    f6=$((E - N + 2*P))
    f7=$(awk '/loops found/ {sum+=$2} END{print sum+0}' "$CFG" 2>/dev/null || true)

    maxd=$(grep 'depth [0-9]\+, outer [0-9]\+' "$CFG" 2>/dev/null \
      | grep -oE 'depth [0-9]+' \
      | grep -oE '[0-9]+' \
      | sort -n \
      | tail -1)
    f8=${maxd:-0}

    f9=$(grep -c 'call ' "$EXPAND" 2>/dev/null || true)

    # f10: 외부 라이브러리 호출 비율
    mapfile -t defined_funcs < <(
      grep -E '^(char|int|void|float|double|long|short|unsigned|signed)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' "$GIMPLE" 2>/dev/null \
      | sed -E 's/^(char|int|void|float|double|long|short|unsigned|signed)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
      | sort -u
    )
    mapfile -t all_calls < <(
      grep -E '[=[:space:]][[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([^;]+\);' "$GIMPLE" 2>/dev/null \
      | sed -E 's/.*\b([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(.*/\1/'
    )
    external_count=$(printf '%s\n' "${all_calls[@]}" \
                     | grep -Fvx -f <(printf '%s\n' "${defined_funcs[@]}") \
                     | wc -l)
    f10=$(awk -v tot="$f9" -v lib="$external_count" 'BEGIN{ if(tot>0) printf "%.4f", lib/tot; else print 0 }')

    f11=$(timeout 15s ./f11.bin "$DOT" 2>/dev/null || true)

    # f12: 평균 in-degree + out-degree
    mapfile -t indeg < <(
      grep -oE -- '-> [^ ]+' "$DOT" 2>/dev/null \
      | cut -d' ' -f2 | sort | uniq -c | awk '{print $1}'
    )
    mapfile -t outdeg < <(
      grep -oE -- '[^ ]+ ->' "$DOT" 2>/dev/null \
      | cut -d' ' -f1 | sort | uniq -c | awk '{print $1}'
    )
    average(){
      awk '{s+=$1; c++} END{ if(c>0) printf "%.2f", s/c; else print "0.00"}'
    }
    avg_i=$(printf '%s\n' "${indeg[@]}" | average)
    avg_o=$(printf '%s\n' "${outdeg[@]}" | average)
    f12=$(awk -v a="$avg_i" -v b="$avg_o" 'BEGIN{ printf "%.2f", a+b }')

    size_sum=0
    while read -r L; do
      [[ $L =~ size[[:space:]]+([0-9]+) ]] && size_sum=$((size_sum + BASH_REMATCH[1]))
    done < <(grep -E '^Partition' "$EXPAND" 2>/dev/null)
    f13=$size_sum

    # --- Static 실행 시간 f14 ---
    local INFILE=""
    if ! gcc -O2 "$SRC" -o "$EXE" 2>/dev/null; then
      f14=-1
    else
      INFILE="./input/${foldername}/input.txt"
      if [ -r "$INFILE" ]; then
        perf_out=$( { timeout 1s perf stat -x, -e task-clock -r1 ./"$EXE" < "$INFILE" 2>&1 >/dev/null || echo -1; } \
                   | head -n1 | cut -d, -f1 )
      else
        perf_out=$( { timeout 1s perf stat -x, -e task-clock -r1 ./"$EXE" 2>&1 >/dev/null || echo -1; } \
                   | head -n1 | cut -d, -f1 )
      fi
      if [[ "$perf_out" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        f14="$perf_out"
      else
        f14=-1
      fi
    fi

    # --- 동적 perf 메트릭 F15~F27 ---
    PERF_OUT="${BASE}_perf.txt"
    EVENTS=(
      instructions
      branch-instructions
      branch-misses
      cache-references
      cache-misses
      mem-loads
      mem-stores
      dtlb_load_misses.walk_completed
      page-faults
      minor-faults
      major-faults
    )
    EVENT_STR=$(IFS=,; echo "${EVENTS[*]}")
    if [ -r "$INFILE" ]; then
      timeout 1s perf stat -e "$EVENT_STR" -o "$PERF_OUT" ./"$EXE" < "$INFILE" 2>&1 >/dev/null
    else
      timeout 1s perf stat -e "$EVENT_STR" -o "$PERF_OUT" ./"$EXE" 2>&1 >/dev/null
    fi

    extract_sum() {
      local pat=$1 core atom
      core=$(grep -E "cpu_core/${pat}" "$PERF_OUT" | head -1 \
              | awk '{v=$1; gsub(/,/, "", v); print (v=="<not"?"0":v)}')
      atom=$(grep -E "cpu_atom/${pat}" "$PERF_OUT" | head -1 \
              | awk '{v=$1; gsub(/,/, "", v); print (v=="<not"?"0":v)}')
      echo $(( core + atom ))
    }
    extract_sw() {
      grep -E "$1" "$PERF_OUT" | head -1 \
        | awk '{v=$1; gsub(/,/, "", v); print (v+0)}'
    }

    F15=$(extract_sum "instructions")
    F16=$(extract_sum "branch-instructions")
    F17=$(extract_sum "branch-misses")
    F18=$(extract_sum "cache-references")
    F19=$(extract_sum "cache-misses")
    F20=$(extract_sum "mem-loads")
    F21=$(extract_sum "mem-stores")
    F22=$(extract_sum "dtlb_load_misses.walk_completed")
    STRACE_OUT="${BASE}_strace.txt"
    if [[ -r "$INFILE" ]]; then
	timeout 1s\
  	strace -f \
        -e trace=read,write,readv,writev,pread64,pwrite64,preadv,pwritev \
        -o "$STRACE_OUT" \
        -- "./$EXE"  \
        < "$INFILE" \
        >/dev/null 2>&1
    else
	timeout 1s\
  	strace -f \
        -e trace=read,write,readv,writev,pread64,pwrite64,preadv,pwritev \
        -o "$STRACE_OUT" \
        -- "./$EXE"  \
	>/dev/null 2>&1
    fi
    # read계열( read, readv, pread64, preadv )
    read_cnt=$(grep -E -c 'read\('   "$STRACE_OUT" || true)
    readv_cnt=$(grep -E -c 'readv\('  "$STRACE_OUT" || true)
    pread64_cnt=$(grep -E -c 'pread64\('  "$STRACE_OUT" || true)
    preadv_cnt=$(grep -E -c 'preadv\(' "$STRACE_OUT" || true)
    read_total=$(( read_cnt + readv_cnt + pread64_cnt + preadv_cnt ))
    # write계열( write, writev, pwrite64, pwritev )
    write_cnt=$(grep -E -c 'write\('   "$STRACE_OUT" || true)
    writev_cnt=$(grep -E -c 'writev\('  "$STRACE_OUT" || true)
    pwrite64_cnt=$(grep -E -c 'pwrite64\('  "$STRACE_OUT" || true)
    pwritev_cnt=$(grep -E -c 'pwritev\(' "$STRACE_OUT" || true)
    write_total=$(( write_cnt + writev_cnt + pwrite64_cnt + pwritev_cnt ))
    F23=$read_total
    F24=$write_total


    F25=$(extract_sw "page-faults")
    F26=$(extract_sw "minor-faults")
    F27=$(extract_sw "major-faults")

    # --- 결과 CSV에 한 줄 추가 (여기서 flock 등으로 동시 쓰기 방지 필요) ---
    (
      flock 200
      echo "$FILE,$f1,$f2,$f3,$f4,$f5,$f6,$f7,$f8,$f9,$f10,$f11,$f12,$f13,$f14,$F15,$F16,$F17,$F18,$F19,$F20,$F21,$F22,$F23,$F24,$F25,$F26,$F27" \
        >> "$CSV_OUT"
    ) 200>"${CSV_OUT}.lock"

    # 중간 파일 정리
    rm -f "$BIN" "$CGRAPH" "$LOOPS" "$GIMPLE" "$STRACE_OUT"\
          "$EXPAND" "$CFG" "$DOT" "$PERF_OUT" "$EXE" 
  } || {
    echo "⚠️ Skipped $FILE due to error." >&2
  }
}

########################################
# 2) 메인 로직: 인자를 보고 분기
########################################
if [ $# -ne 1 ]; then
  echo "Usage: $0 <directory-containing-.c-files 또는 single-.c-file>" >&2
  exit 1
fi

INPUT="$1"
CSV_OUT="./features.csv"

# (A) 인자로 .c 파일이 들어온 경우
if [[ -f "$INPUT" && "${INPUT##*.}" == "c" ]]; then
  # ROOTDIR은 “/data/p000XX” 형태. 필요시 추가 로직에 쓰일 수 있습니다.
  ROOTDIR="$(dirname "$(dirname "$INPUT")")"
  process_one_file "$INPUT" "$ROOTDIR" "$CSV_OUT"
  echo "✅ Done. Single file processed: $INPUT"
  exit 0
fi

# (B) 인자로 디렉터리가 들어온 경우
if [[ -d "$INPUT" ]]; then
  BASEDIR="$INPUT"
  # 예: find "$BASEDIR"/p*/C -type f -name '*.c'
  find "$BASEDIR"/p*/C -type f -name '*.c' | while read -r SRC; do
    process_one_file "$SRC" "$BASEDIR" "$CSV_OUT"
  done
  echo "✅ Done. All files processed under $BASEDIR"
  exit 0
fi

# 그 외
echo "Error: '$INPUT' 는 .c 파일도 아니고 디렉터리도 아닙니다." >&2
exit 1
