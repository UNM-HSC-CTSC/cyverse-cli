#!/bin/bash
# Local tests for batch-runner, run the way the DE runs a batch step: inputs
# pre-downloaded into a mounted /de-app-work, the image's ENTRYPOINT replaced by
# `bash -c "<command> > logs/step-0.stdout.log 2> logs/step-0.stderr.log"`.
#
#   ./test.sh harbor.example.org/batch/cloudshell-batch:24.04
set -uo pipefail

IMAGE="${1:?usage: $0 <image>}"
ROOT="$(mktemp -d)"
trap 'docker run --rm -v "$ROOT":/r --entrypoint rm "$IMAGE" -rf /r/cases; rm -rf "$ROOT"' EXIT
fails=0

# new_case <name>: fresh working directory with a logs/ dir, like init-working-dir
new_case() { W="$ROOT/cases/$1"; mkdir -p "$W/logs"; }

# run_case <args...>: run batch-runner as the DE would; sets $rc
run_case() {
  docker run --rm -v "$W":/de-app-work -w /de-app-work --entrypoint bash \
    -e HTTP_PROXY -e HTTPS_PROXY -e NO_PROXY -e http_proxy -e https_proxy -e no_proxy \
    "$IMAGE" \
    -c "batch-runner $* > logs/step-0.stdout.log 2> logs/step-0.stderr.log"
  rc=$?
}

check() {  # check <description> <condition...>
  local desc="$1"; shift
  if "$@"; then echo "  ok   $desc"; else echo "  FAIL $desc"; fails=$((fails + 1)); fi
}

show_logs() {
  echo "  --- stdout"; sed 's/^/  | /' "$W/logs/step-0.stdout.log"
  echo "  --- stderr"; sed 's/^/  | /' "$W/logs/step-0.stderr.log"
}

# -----------------------------------------------------------------------------
echo "== full: apt + conda env from environment.yaml, src/ folder, outputs"
new_case full
mkdir -p "$W/src"
cat > "$W/environment.yaml" <<'EOF'
name: analysis
channels: [conda-forge]
dependencies: [python=3.12, numpy]
EOF
cat > "$W/src/main.py" <<'EOF'
import numpy, sys
print("numpy", numpy.__version__, "python", sys.version.split()[0])
open("result.txt", "w").write(str(numpy.arange(10).sum()) + "\n")
EOF
cat > "$W/init.sh" <<'EOF'
set -e
apt-get update -qq && apt-get install -y -qq jq > /dev/null
conda env create -q -f inputs/environment.yaml
conda activate analysis
export MY_SETTING=from-init
exit 0   # an explicit exit must not skip run.sh
EOF
cat > "$W/run.sh" <<'EOF'
set -e
echo "env=$CONDA_DEFAULT_ENV setting=$MY_SETTING python=$(which python) pwd=$PWD"
jq --version
python inputs/src/main.py
EOF
run_case --init init.sh --run run.sh environment.yaml src
check "exit 0" [ "$rc" -eq 0 ]
check "inputs moved into inputs/" [ -f "$W/inputs/environment.yaml" -a -d "$W/inputs/src" -a -f "$W/inputs/run.sh" ]
check "nothing left at top level but inputs, logs, result" \
  [ "$(cd "$W" && ls | sort | tr '\n' ' ')" = "inputs logs result.txt " ]
check "output written to workdir" grep -qx 45 "$W/result.txt"
check "conda activation carried into run.sh" grep -q 'env=analysis setting=from-init python=/opt/conda/envs/analysis/bin/python pwd=/de-app-work' "$W/logs/step-0.stdout.log"
[ "$rc" -eq 0 ] || show_logs

# -----------------------------------------------------------------------------
echo "== init fails: run.sh must not start, init's exit code is returned"
new_case init-fails
echo 'echo initializing; exit 3' > "$W/init.sh"
echo 'touch ran' > "$W/run.sh"
run_case --init init.sh --run run.sh
check "exit 3" [ "$rc" -eq 3 ]
check "run.sh did not run" [ ! -e "$W/ran" ]
check "failure explained in stderr" grep -q 'init script failed (exit 3)' "$W/logs/step-0.stderr.log"

# -----------------------------------------------------------------------------
echo "== run fails: its exit code is returned"
new_case run-fails
echo 'echo working; false' > "$W/run.sh"
run_case --run run.sh
check "exit 1" [ "$rc" -eq 1 ]
check "failure explained in stderr" grep -q 'run script failed (exit 1)' "$W/logs/step-0.stderr.log"

# -----------------------------------------------------------------------------
echo "== no init, blank optional --init flag, multi-file inputs via --input"
new_case blank-init
echo a > "$W/a.csv"; echo b > "$W/b.csv"
echo 'cat inputs/a.csv inputs/b.csv > combined.csv' > "$W/run.sh"
run_case --run run.sh --input a.csv --input b.csv --init
check "exit 0" [ "$rc" -eq 0 ]
check "combined output" [ "$(cat "$W/combined.csv" 2>/dev/null | tr -d '\n')" = ab ]

# -----------------------------------------------------------------------------
echo "== missing run script"
new_case no-run
run_case --init init.sh
check "exit 2" [ "$rc" -eq 2 ]

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails check(s) failed"; exit 1; fi
