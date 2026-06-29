#!/usr/bin/env bash
set -euo pipefail

# Repair missing IDEAL-condition DGA iteration trials without rerunning completed trials.
# Default: 15 workers.
# It detects missing episode IDs from raw output folders, creates per-iteration repair scenario files,
# and writes repair outputs back under runs/sensitivity_dga_iterations so the normal combine step can include them.

REPO_ROOT="/home/jlott/dcta_benchmark_sim"
cd "$REPO_ROOT"

NUM_CORES="${1:-15}"
SCENARIO_FILE="final_trial_500.csv"
GRID_SIZE=19
MAX_TRIALS_TOTAL=300
OUT_ROOT="runs/sensitivity_dga_iterations"
SCRIPT_ROOT="benchmark_sim/tests/dga_iteration_ideal_repair_generated"
PARTITION_DIR="$SCRIPT_ROOT/scenario_partitions"
WORKER_DIR="$SCRIPT_ROOT/workers"
LOG_DIR="$SCRIPT_ROOT/logs"
WRAPPER_DIR="benchmark_sim/algorithms/dga_iter_wrappers"
REPAIR_LABEL="repair_ideal_missing"

ITERATIONS=(1 2 5 10 25 50)

mkdir -p "$SCRIPT_ROOT" "$PARTITION_DIR" "$WORKER_DIR" "$LOG_DIR" "$WRAPPER_DIR"
touch benchmark_sim/algorithms/dga_iter_wrappers/__init__.py

cat <<INFO
============================================================
[SETUP] DGA ideal iteration missing-trial repair
[INFO] repo root: $REPO_ROOT
[INFO] workers: $NUM_CORES
[INFO] scenario file: $SCENARIO_FILE
[INFO] expected paired trials per ideal iteration condition: $MAX_TRIALS_TOTAL
[INFO] output root: $OUT_ROOT
[INFO] repair label: $REPAIR_LABEL
============================================================
INFO

# Create/refresh wrappers.
for ITER in "${ITERATIONS[@]}"; do
  WRAPPER_FILE="$WRAPPER_DIR/DGA_iter_${ITER}.py"
  cat > "$WRAPPER_FILE" <<PYEOF
from benchmark_sim.algorithms.DGA import DGAAllocator as BaseDGAAllocator

class DGAIter${ITER}Allocator(BaseDGAAllocator):
    name = "DGA_iter_${ITER}"
    DGA_ITERATIONS_PER_TRIGGER = ${ITER}
PYEOF
done

# Clear only generated repair worker scripts/logs/partitions, not simulation outputs.
rm -f "$WORKER_DIR"/worker_*.sh
rm -f "$LOG_DIR"/worker_*.log
rm -f "$PARTITION_DIR"/iter_*_part_*.csv
rm -f "$SCRIPT_ROOT"/repair_manifest.tsv

# Detect missing episode IDs and create partitions separately for each iteration count.
python3 - <<PY
import csv
import os
from pathlib import Path

repo = Path("$REPO_ROOT")
scenario_file = repo / "$SCENARIO_FILE"
out_root = repo / "$OUT_ROOT"
partition_dir = repo / "$PARTITION_DIR"
script_root = repo / "$SCRIPT_ROOT"
num_parts = int("$NUM_CORES")
max_trials = int("$MAX_TRIALS_TOTAL")
iterations = [int(x) for x in "${ITERATIONS[*]}".split()]

partition_dir.mkdir(parents=True, exist_ok=True)

raw_lines = scenario_file.read_text().splitlines(True)
comment_lines = [ln for ln in raw_lines if ln.lstrip().startswith("#")]
data_lines = [ln for ln in raw_lines if not ln.lstrip().startswith("#") and ln.strip()]
if not data_lines:
    raise SystemExit(f"No CSV data rows found in {scenario_file}")

reader = csv.DictReader(data_lines)
fieldnames = reader.fieldnames
if not fieldnames:
    raise SystemExit(f"Could not read header from {scenario_file}")
rows = list(reader)[:max_trials]
if "episode" not in fieldnames:
    raise SystemExit("Scenario file must contain episode for safe missing-trial repair.")

expected_by_id = {str(r["episode"]): r for r in rows}
expected_ids = list(expected_by_id.keys())

manifest_path = script_root / "repair_manifest.tsv"
with manifest_path.open("w", newline="") as mf:
    mf.write("iteration\texpected\tpresent\tmissing\tmissing_episode_ids\n")

    for iteration in iterations:
        ideal_dir = out_root / f"iter_{iteration}" / "ideal"
        present = set()
        if ideal_dir.exists():
            for csv_path in ideal_dir.rglob("system_performance.csv"):
                # Ignore any previously generated combined folder, if present.
                if "combined" in csv_path.parts:
                    continue
                try:
                    with csv_path.open(newline="") as f:
                        r = csv.DictReader(f)
                        if not r.fieldnames:
                            continue
                        id_col = "episode" if "episode" in r.fieldnames else ("trial_id" if "trial_id" in r.fieldnames else None)
                        if id_col is None:
                            continue
                        for row in r:
                            eid = row.get(id_col, "")
                            if eid != "":
                                present.add(str(eid))
                except Exception as exc:
                    print(f"[WARN] could not read {csv_path}: {exc}")

        missing_ids = [tid for tid in expected_ids if tid not in present]
        missing_rows = [expected_by_id[tid] for tid in missing_ids]
        print(f"[MISSING] iter={iteration} expected={len(expected_ids)} present={len(present)} missing={len(missing_rows)}")
        if missing_ids:
            print(f"[MISSING_IDS] iter={iteration} {','.join(missing_ids)}")
        mf.write(f"{iteration}\t{len(expected_ids)}\t{len(present)}\t{len(missing_rows)}\t{','.join(missing_ids)}\n")

        parts = [[] for _ in range(num_parts)]
        for idx, row in enumerate(missing_rows):
            parts[idx % num_parts].append(row)

        for part_idx, part_rows in enumerate(parts):
            out_path = partition_dir / f"iter_{iteration}_part_{part_idx}.csv"
            with out_path.open("w", newline="") as out:
                for ln in comment_lines:
                    out.write(ln)
                writer = csv.DictWriter(out, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(part_rows)
            if part_rows:
                eids = ",".join(str(r["episode"]) for r in part_rows)
                print(f"[PARTITION] iter={iteration} part={part_idx} trials={len(part_rows)} episodes={eids}")

print(f"[MANIFEST] {manifest_path}")
PY

# Create one worker per core. Each worker handles its part for each iteration.
for PART in $(seq 0 $((NUM_CORES - 1))); do
  WORKER_SCRIPT="$WORKER_DIR/worker_${PART}.sh"

  cat > "$WORKER_SCRIPT" <<EOF2
#!/usr/bin/env bash
set -euo pipefail
cd "$REPO_ROOT"

PART="$PART"
GRID_SIZE="$GRID_SIZE"
OUT_ROOT="$OUT_ROOT"
REPAIR_LABEL="$REPAIR_LABEL"

echo "[START] repair worker=\$PART at \$(date -Is)"
EOF2

  for ITER in "${ITERATIONS[@]}"; do
    PART_SCENARIO="$PARTITION_DIR/iter_${ITER}_part_${PART}.csv"
    OUT_DIR="$OUT_ROOT/iter_${ITER}/ideal/$REPAIR_LABEL/part_${PART}"
    ALG_PATH="benchmark_sim.algorithms.dga_iter_wrappers.DGA_iter_${ITER}:DGAIter${ITER}Allocator"

    cat >> "$WORKER_SCRIPT" <<EOF2

PART_SCENARIO="$PART_SCENARIO"
ROW_COUNT=\$(python3 - <<PY2
import csv
p = "\$PART_SCENARIO"
with open(p, newline="") as f:
    rows = [r for r in csv.DictReader(line for line in f if not line.lstrip().startswith("#"))]
print(len(rows))
PY2
)

if [[ "\$ROW_COUNT" -eq 0 ]]; then
  echo "[SKIP] worker=\$PART iter=$ITER no missing ideal trials assigned"
else
  echo "============================================================"
  echo "[RUN] worker=\$PART iter=$ITER comm=ideal repair=$REPAIR_LABEL trials=\$ROW_COUNT"
  echo "[SCENARIO] \$PART_SCENARIO"
  echo "[OUT_DIR] $OUT_DIR"
  echo "[TIME] \$(date -Is)"
  mkdir -p "$OUT_DIR"

  if [[ -f "$OUT_DIR/_COMPLETE.txt" ]]; then
    echo "[SKIP] already complete: $OUT_DIR"
  else
    python3 -m benchmark_sim.run_trials \\
      --scenario-file "\$PART_SCENARIO" \\
      --algorithm "$ALG_PATH" \\
      --comm-model ideal \\
      --comm-level 0 \\
      --grid-size "\$GRID_SIZE" \\
      --max-trials 999999 \\
      --out-dir "$OUT_DIR" \\
      > "$OUT_DIR/run.log" 2>&1

    echo "Completed repair iter=$ITER worker=\$PART at \$(date -Is)" > "$OUT_DIR/_COMPLETE.txt"
    echo "[DONE] worker=\$PART iter=$ITER at \$(date -Is)"
  fi
fi
EOF2
  done

  cat >> "$WORKER_SCRIPT" <<'EOF2'

echo "[FINISHED] repair worker=$PART at $(date -Is)"
EOF2
done

echo "[LAUNCH] Starting $NUM_CORES repair workers..."
for PART in $(seq 0 $((NUM_CORES - 1))); do
  nohup bash "$WORKER_DIR/worker_${PART}.sh" > "$LOG_DIR/worker_${PART}.log" 2>&1 &
  echo "[LAUNCHED] repair worker_$PART pid=$!"
done

cat <<INFO

============================================================
[RUNNING] DGA ideal missing-trial repair started.

Monitor logs:
  tail -f $LOG_DIR/worker_*.log

Check finished:
  grep FINISHED $LOG_DIR/worker_*.log

Check failures:
  grep -R "Traceback\|ERROR\|failed" $LOG_DIR $OUT_ROOT/iter_*/ideal/$REPAIR_LABEL/part_*/run.log 2>/dev/null || true

Missing-trial manifest:
  cat $SCRIPT_ROOT/repair_manifest.tsv

Repair outputs are under:
  $OUT_ROOT/iter_<ITER>/ideal/$REPAIR_LABEL/part_<PART>
============================================================
INFO
