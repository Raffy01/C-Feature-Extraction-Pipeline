# C Feature Extraction Pipeline

This repository provides a set of Bash scripts to automate static and dynamic feature extraction from C source files, aggregate the results into a CSV file, and (optionally) run the extraction in parallel across multiple directories. It is designed for projects that require per‐source‐file feature collection (e.g., performance modeling, code analytics, machine learning).

---

## Repository Structure

```
.
├── data.tar.gz
├── input.tar.gz
├── extract_file.sh
├── parallel_run_dir_strict.sh
├── f11.bin
├── f11.py
├── unpack_directories.sh
├── LICENSE
└── README.md
```

- **extract_file.sh**  
  Processes a single C file (or, when called on a directory, all `.c` files under `<dir>/p*/C`), compiles with GCC to generate various dumps (cgraph, gimple, loops, CFG, etc.), extracts static features (`f1`–`f13`), measures execution time (`f14`) with `perf`, collects dynamic metrics (`F15`–`F27`), and appends one line per file to a central CSV (`features.csv`).

- **parallel_run_dir_strict.sh**  
  Iterates over subdirectories of `./data/` (each expected to be named `pXXXX`), and for each C file under `./data/<pXXXX>/C/*.c`, spawns `extract_file.sh` as a background job (up to `MAXJOBS=8` concurrent processes). Ensures one directory’s jobs finish before moving to the next.

---

## Prerequisites
> **IMPORTANT** : Some virtual machines do not allow(or even do not have) user to access hardware data.  
> Therefore, virtual machines is **NOT** recommended in this project.
0. **Linux Kernel** (6.11.0) No backward compatibility checked
1. **Bash** (version >= 4.0)  
2. **GCC** (version >= 7.0) with support for the following dump options:
   - `-fdump-ipa-cgraph`
   - `-fdump-tree-loop`
   - `-fdump-tree-gimple`
   - `-fdump-rtl-expand`
   - `-fdump-tree-cfg-graph`
3. **perf** (for measuring `task-clock`, instructions, cache misses, etc.)  
4. **strace** (for counting read/write system calls)  
5. **f11.bin** (a helper binary to compute feature `f11` from the CFG `.dot` file)  
   - You must place or build `f11.bin` in the same directory as `extract_file.sh`. It should read `<base>.fdump.cfg.dot` and output a single integer.  
6. **awk**, **grep**, **sed**, **sort**, **wc**, **flock** (standard GNU utilities)  
7. **timeout** (usually available in `coreutils`)  
8. **python** (version >= 13.0) If needed.

> **Note:** The scripts assume that each C project follows a directory layout like:
> ```
> data/
> ├── p00001/
> │   └── C/
> │       ├── example1.c
> │       └── example2.c
> ├── p00002/
> │   └── C/
> │       └── foo.c
> └── p00003/
>     └── C/
>         └── bar.c
> ```
> and that, if an input file is needed at runtime, it lives in:
> ```
> input/
> ├── p00001/
> │    ├── input.txt
> │    └── output.txt
> ├── p00002/
> │    ├── input.txt
> │    └── output.txt
> └── p00003/
>      ├── input.txt
>      └── output.txt
---
## Unpacking Archives
This repository has two archive files, `data.tar.gz` and `input.tar.gz`. Decompression must be guaranteed to follow the above-described directory structure. Or use given 'unpack_directories.sh'
1. Using script:
Execute following sequance
   ```bash
    chmod +x unpack_directories.sh
   ./unpack_directories.sh

2. Manually
- `data.tar.gz`:
  ```bash
  tar -xzvf data.tar.gz

- `input.tar.gz`:
  ```bash
  tar -xzvf data.tar.gz

**Note:** Must follow given directory structure
## Feature Definitions

When `extract_file.sh` runs on a C source file `<base>.c`, it generates these features (columns) in the CSV, in order:

1. `FILE` – Basename of the C file (e.g., `example.c`).
2. `f1` – Count of semicolon‐terminated statements in GIMPLE (rough measure of statement count).
3. `f2` – Count of assignments or comparisons (`=` with arithmetic; or `cmp`) in GIMPLE.
4. `f3` – Count of memory operations (`mem`) in the RTL‐expand dump.
5. `f4` – Number of basic blocks in the CFG (`<bb N>` markers).
6. `f5` – Count of control‐flow statements (`if (` or `switch`) in GIMPLE.
7. `f6` – Cyclomatic complexity estimate: `E – N + 2P`, where:
    - `E` = number of edges (`->`) in the CFG DOT file  
    - `N` = number of labels in the DOT file  
    - `P` = number of subgraph clusters (each `cluster_…`)  
8. `f7` – Sum of all loop counts reported in the CFG dump (`“loops found”` lines).
9. `f8` – Maximum loop‐nesting depth (parsed from lines containing `depth N, outer M` in the CFG dump).
10. `f9` – Count of function calls (`call `) in the RTL‐expand dump.
11. `f10` – Ratio of external library calls to all calls (computed by comparing calls in GIMPLE vs. defined functions).
12. `f11` – Output of `./f11.bin <base>.fdump.cfg.dot` (user‐provided helper; typically a custom metric).
13. `f12` – Average in‐degree + out‐degree in the CFG graph (computed over the DOT file).
14. `f13` – Sum of all “Partition <size>” values in the RTL‐expand dump (e.g., stack‐frame sizes).
15. `f14` – Execution time (in `task‐clock` units) measured by `perf stat`, with a 1-second timeout.  
    − If compilation or runtime fails, `f14 = -1`.
16. `F15` – Dynamic count of **instructions** (from `perf stat –e instructions`).  
17. `F16` – Dynamic count of **branch-instructions**.  
18. `F17` – Dynamic count of **branch-misses**.  
19. `F18` – Dynamic count of **cache-references**.  
20. `F19` – Dynamic count of **cache-misses**.  
21. `F20` – Dynamic count of **mem-loads**.  
22. `F21` – Dynamic count of **mem-stores**.  
23. `F22` – Dynamic count of **dtlb_load_misses.walk_completed**.  
24. `F23` – Total number of **read**‐family syscalls (read, readv, pread64, preadv) as traced by `strace`.  
25. `F24` – Total number of **write**‐family syscalls (write, writev, pwrite64, pwritev) as traced by `strace`.  
26. `F25` – Count of **page-faults** (from `perf stat`).  
27. `F26` – Count of **minor-faults**.  
28. `F27` – Count of **major-faults**.

The final CSV header (first line) is **not** generated automatically; if you want a header, create it as:
```csv
FILE,f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13,f14,F15,F16,F17,F18,F19,F20,F21,F22,F23,F24,F25,F26,F27
```
Then run the extraction scripts to append one row per file.

---

## Installation & Setup

1. **Clone or copy** this repository to your local machine.

2. **Ensure all dependencies** are installed:
   ```bash
   sudo apt update
   sudo apt install -y build-essential bash coreutils perf strace flock
   sudp apt install python3
   ```

3. **Place (or build) `f11.bin`** in the same directory as `extract_file.sh`. This file was made in Python and compiled into a binary file through `nuitka`. If you use an older version of the Linux kernel, a glibc error may occur. In this case, you must recompile the enclosed f11.py file or run it through python3. If error occur, follow these instructions.
- Via building
   ```bash
   sudo apt install python3
   sudo apt install python3-pydot
   sudo apt install python3-networkx
   sudo apt install python3-pip
   python3 -m pip install nuitka
   python3 -m nuitka --standalone --onefile f11.py
   ```
  When installing nuitka, this error may occur.
  ```bash
    error: externally-managed-environment
  ```
  This error is caused by Pip trying to install the package in an actual OS environment rather than a virtual environment. To solve, you have two solution.
  1. Use `--break-system-packages` option  
  you can force it to install using the '--break-system-packages' option
  ```bash
  python3 -m pip install --break-system-packages nuitka
  ```
  2. Build virtual environment  
  Virtual environments allow you to install packages without affecting your system. Follow the steps below to set up your virtual environment using 'venv' and install Nuitka.  
     1. **Create virtual environment**:
      ```bash
      sudo apt install python3.12-venv
      python3 -m venv myenv
      ```
     2. **Activate venv**:
      ```bash
      source myenv/bin/activate
      ```
     3. **Install nuitka**:
      ```bash
      pip install nuitka
      ```
     4. **Compile**:
       ```bash
       python3 -m nuitka --standalone --onefile f11.py
       ```
     5. After all, you can deactivate venv via :
      ```bash
      deactivate
      ```
 - Via manipulating `extract_file.sh`  
   At `extract_file.sh`, line **76**
   ```bash
   f11=$(./f11.bin "$DOT" 2>/dev/null || true)
   ```
   Replace this line as
   ```bash
   f11=$(python3 ./f11.py "$DOT" 2>/dev/null || true)
   ```
4. **Set executable permissions**:
   ```bash
   chmod +x extract_file.sh
   chmod +x parallel_run_dir_strict.sh
   ```
5. **Set perf permission**:
   ```bash
   sudo echo 0 > /proc/sys/kernel/perf_event_paranoid
   ```

---

## Usage

### 1. Single‐File Extraction

To extract features from one C file:
```bash
./extract_file.sh /path/to/data/p00001/C/example.c
```
- **Output**: Appends a line to `../features/features.csv` (relative to `example.c`) with that file’s features.  
- **Log**: Prints progress to `stderr`, e.g.,  
  ```
  ▶ Processing example.c …
  ✅ Done. Single file processed: /path/to/data/p00001/C/example.c
  ```

### 2. Directory‐Wide Extraction

If you point `extract_file.sh` at a directory, it will find all C files under `$(dir)/p*/C/*.c`:
```bash
./extract_file.sh /path/to/data
```
- **Behavior**:  
  - It expects subdirectories named `p00001`, `p00002`, … each containing a `C/` folder with `.c` files.  
  - Each `.c` file is processed in series.  
  - At the end:  
    ```
    ✅ Done. All files processed under /path/to/data
    ```

### 3. Parallel Extraction Across Projects

To process multiple “pXXXX” subdirectories in parallel, use:
```bash
./parallel_run_dir_strict.sh
```
- **Assumptions**:  
  - Expects `DATA_ROOT="./data"` to contain subdirs like `p00001/`, `p00002/`, …  
  - Within each `pXXXX/`, there is a `C/` folder with `.c` files.  
- **How it works**:
  1. Iterates over each `data/pXXXX/` in lex order.
  2. For each `.c` under `data/pXXXX/C/`, spawns:
     ```bash
     ./extract_file.sh "data/pXXXX/C/foo.c" &
     ```
     up to `MAXJOBS=8` concurrent jobs.
  3. Waits for all jobs in the current `pXXXX/` directory to finish (via `wait`) before moving to the next.
  4. At the end, waits for any remaining background jobs before exiting.

---

## Directory Layout Example

```
.
├── data/
│   ├── p00001/
│   │   ├── C/
│   │   │   ├── foo.c
│   │   │   └── bar.c
│   ├── p00002/
│   │   ├── C/
│   └── p00003/
├── input/
│   ├── p00001/ 
│   │   ├── input.txt
│   │   └── output.txt
│   └── p00002/
│
├── features.csv
├── extract_file.sh
├── f11.bin
└── parallel_run_dir_strict.sh
```

- **`data/p000XX/C/*.c`**: Source files to analyze.  
- **`input/p000XX/input.txt`**: (Optional) stdin for each binary when measuring execution time. If absent, the program runs with no stdin.  
- **`features.csv`**: Aggregated CSV (created or pre‐initialized with header) where each row is appended by `extract_file.sh`.

---

## Example Workflow

1. **Prepare the CSV header** (only once, not necessary):
   ```bash
   echo "FILE,f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13,f14,F15,F16,F17,F18,F19,F20,F21,F22,F23,F24,F25,F26,F27"      > ./features.csv
   ```

2. **Place all C projects** under `data/`:
   ```
   data/
   ├── p00001/...
   ├── p00002/...
   └── p00003/...
   ```

3. **Run in parallel**:
   ```bash
   ./parallel_run_dir_strict.sh
   ```
   – This will fill `features.csv` with one row per `.c` file across all `pxxxx`.

4. **Inspect `features.csv`** with any spreadsheet or analysis tool.

---

## Troubleshooting
- **Intended matters**  
  ‣ Workload failed error happens when gcc fails to compile source. This doesn't affect future execution.  
  ‣ So does Segmantition Fault during perf, strace.

- **Systemwise Error**  
  ‣ Some virtual machines prohibit access to hardware instruction counts. In this case, you should check
    virtual machine setting to make sure you can access to them. If not available, you are unable to get
    dynamic features(`f15` ~ `f22`). 

- **“command not found: perf”**  
  ‣ Install: `sudo apt install linux-tools-common linux-tools-$(uname -r)`

- **“f11.bin: No such file or directory”**  
  ‣ Build or copy `f11.bin` into the same folder as `extract_file.sh`.  

- **Permission errors when writing to `features.csv`**  
  ‣ Ensure you have write permission in current directory.  
  ‣ `flock` is used for atomic writes; ensure `coreutils` is installed.

- **Long runtimes or timeouts**  
  ‣ The script uses `timeout 1s` for both `perf stat` and `strace`. If a target binary takes longer, it will report `f14 = -1`. Adjust the `timeout` settings inside `extract_file.sh` if needed.

- **Missing “Partition …” lines in `expand` dump**  
  ‣ If `f13` is always zero, check that `-fdump-rtl-expand` is generating “Partition <size>” lines. Different GCC versions may change dump format slightly.

---

## Customization

- **Adjust Concurrency**  
  In `parallel_run_dir_strict.sh`, set `MAXJOBS=<N>` to control how many simultaneous invocations of `extract_file.sh` you allow.

- **Change Data Root**  
  Modify `DATA_ROOT="./data"` at the top of `parallel_run_dir_strict.sh` to point to a different base folder.

- **Add/Remove Perf Events**  
  In `extract_file.sh`, the `EVENTS=(…)` array lists dynamic events (`instructions`, `cache-misses`, etc.). You can add or remove events by editing that array. Just be sure to adjust subsequent `F15`–`F27` assignments accordingly.

- **Alter Feature Computation**  
  - Static features (`f1`–`f13`) are computed via `grep`, `awk`, and `sed`. You can modify or add new feature extraction logic inside the `process_one_file()` function.  
  - The helper binary `f11.bin` must output exactly one number per invocation; modify its logic as needed for a new metric.

---

## License

This Dataset is released under the CDLA 2.0 License. See [LICENSE](https://cdla.dev/permissive-2-0/) for details.  
Other codes are written by Wooyong Eom, CSE, Soongsil Univ.
---

_Last Updated: June 6, 2025_
