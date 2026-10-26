#!/bin/bash
# Regenerates tests/fixtures/manifest.json from the fixture dbt project (dbt-core 1.10 + dbt-duckdb).
# Internal dbt/dbt_duckdb macros are dropped (hundreds of KB nobody tests); everything else is as dbt wrote it.
set -euo pipefail
cd "$(dirname "$0")/../tests/fixtures/project"
DBT=(uvx --quiet --from 'dbt-core==1.10.*' --with 'dbt-duckdb==1.10.*' dbt)
export DBT_PROFILES_DIR="$PWD"
"${DBT[@]}" deps --no-use-colors
"${DBT[@]}" parse --no-use-colors
python3 - <<'PY'
import json
m = json.load(open("target/manifest.json"))
m["macros"] = {k: v for k, v in m["macros"].items() if v["package_name"] in ("demo", "pkg_a")}
json.dump(m, open("../manifest.json", "w"), indent=1, sort_keys=True)
print("macros kept:", len(m["macros"]), "nodes:", len(m["nodes"]))
PY
rm -rf build target dbt_packages package-lock.yml logs .user.yml
