#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./build_jenny.sh Release
#   ./build_jenny.sh Debug
#
# Creates:
#   Artifacts/Jenny/
#   Artifacts/Jenny/Plugins/Jenny/
#
# And copies ONLY the explicitly listed files into those folders (missing files are skipped).

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${1:-Release}"

# Pick solution
if [[ -f "$SCRIPT_DIR/Jenny.sln" ]]; then
  SOLUTION="$SCRIPT_DIR/Jenny.sln"
else
  SOLUTION_CANDIDATES=("$SCRIPT_DIR"/*.sln)
  [[ -e "${SOLUTION_CANDIDATES[0]}" ]] || { echo "ERROR: No .sln found in $SCRIPT_DIR"; exit 1; }
  SOLUTION="${SOLUTION_CANDIDATES[0]}"
fi

ARTIFACTS_DIR="$SCRIPT_DIR/Artifacts"
DEST_MAIN="$ARTIFACTS_DIR/Jenny"
DEST_PLUGINS="$ARTIFACTS_DIR/Jenny/Plugins/Jenny"
TMP_PUBLISH_ROOT="$SCRIPT_DIR/.publishout"

NUGET_DIR="${NUGET_PACKAGES:-$HOME/.nuget/packages}"

# ---------------------------
# Only these files will remain in Artifacts
# ---------------------------
MAIN_FILES=(
  "DesperateDevs.Cli.Utils.dll"
  "DesperateDevs.Extensions.dll"
  "DesperateDevs.Reflection.dll"
  "DesperateDevs.Serialization.Cli.Utils.dll"
  "DesperateDevs.Serialization.dll"
  "Jenny.dll"
  "Jenny.Generator.Cli.dll"
  "Jenny.Generator.Cli.runtimeconfig.json"
  "Jenny.Generator.dll"
  "Sherlog.dll"
  "Sherlog.Formatters.dll"
  "TCPeasy.dll"
)

PLUGIN_FILES=(
  "DesperateDevs.Roslyn.dll"
  "Humanizer.dll"
  "Jenny.Plugins.dll"
  "Jenny.Plugins.Roslyn.dll"
  "Jenny.Plugins.Unity.dll"
  "Microsoft.Bcl.AsyncInterfaces.dll"
  "Microsoft.Build.Locator.dll"
  "Microsoft.CodeAnalysis.CSharp.dll"
  "Microsoft.CodeAnalysis.CSharp.Workspaces.dll"
  "Microsoft.CodeAnalysis.dll"
  "Microsoft.CodeAnalysis.Workspaces.dll"
  "Microsoft.CodeAnalysis.Workspaces.MSBuild.dll"
  "System.Composition.AttributedModel.dll"
  "System.Composition.Convention.dll"
  "System.Composition.Hosting.dll"
  "System.Composition.Runtime.dll"
  "System.Composition.TypedParts.dll"
  "System.IO.Pipelines.dll"
)

# ---------------------------
# Helpers
# ---------------------------
is_excluded_project() {
  local name="$1"
  case "$name" in
    *Tests*|*Test*|*Benchmarks*|*Benchmark*|*Fixture*)
      return 0 ;;
  esac
  return 1
}

publish_one() {
  local csproj="$1"
  local name="$2"
  local out_dir="$TMP_PUBLISH_ROOT/$name"

  rm -rf "$out_dir"
  mkdir -p "$out_dir"
  echo "Publishing: $name"
  dotnet publish "$csproj" -c "$CONFIG" -o "$out_dir" \
    -p:DebugSymbols=false -p:DebugType=None >/dev/null
}

# Find a file by exact name in:
#  1) temp publish outputs
#  2) repo tree (in case it lands in bin/)
#  3) NuGet cache
find_file_anywhere() {
  local filename="$1"
  local found=""

  # 1) publish outputs
  found="$(find "$TMP_PUBLISH_ROOT" -type f -name "$filename" 2>/dev/null | head -n 1 || true)"
  [[ -n "$found" ]] && { echo "$found"; return 0; }

  # 2) repo (bin/Release etc.)
  found="$(find "$SCRIPT_DIR" -type f -name "$filename" 2>/dev/null | head -n 1 || true)"
  [[ -n "$found" ]] && { echo "$found"; return 0; }

  # 3) NuGet cache
  found="$(find "$NUGET_DIR" -type f -name "$filename" 2>/dev/null | head -n 1 || true)"
  [[ -n "$found" ]] && { echo "$found"; return 0; }

  return 1
}

copy_if_found() {
  local filename="$1"
  local dest="$2"

  local src=""
  if src="$(find_file_anywhere "$filename")"; then
    cp -f "$src" "$dest/"
  fi
}

# ---------------------------
# Clean + prepare dirs
# ---------------------------
rm -rf "$ARTIFACTS_DIR" "$TMP_PUBLISH_ROOT"
mkdir -p "$DEST_MAIN" "$DEST_PLUGINS" "$TMP_PUBLISH_ROOT"

# ---------------------------
# Publish non-test projects from solution
# (Per-project publish avoids test-dependency leakage.)
# ---------------------------
PROJECT_PATHS=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  PROJECT_PATHS+=("$line")
done < <(dotnet sln "$SOLUTION" list | tail -n +3 | sed 's/^[[:space:]]*//')

[[ "${#PROJECT_PATHS[@]}" -gt 0 ]] || { echo "ERROR: Could not read projects from solution."; exit 1; }

for rel_path in "${PROJECT_PATHS[@]}"; do
  local_csproj=""
  if [[ -f "$rel_path" ]]; then
    local_csproj="$rel_path"
  elif [[ -f "$SCRIPT_DIR/$rel_path" ]]; then
    local_csproj="$SCRIPT_DIR/$rel_path"
  else
    continue
  fi

  proj_name="$(basename "$local_csproj" .csproj)"
  if is_excluded_project "$proj_name"; then
    continue
  fi

  publish_one "$local_csproj" "$proj_name"
done

# ---------------------------
# Copy ONLY the approved file lists
# ---------------------------
for f in "${MAIN_FILES[@]}"; do
  copy_if_found "$f" "$DEST_MAIN"
done

for f in "${PLUGIN_FILES[@]}"; do
  copy_if_found "$f" "$DEST_PLUGINS"
done

# Extra: handle the one name you wrote without ".dll" just in case
copy_if_found "DesperateDevs.Cli.Utils" "$DEST_MAIN" || true

# Cleanup temp
rm -rf "$TMP_PUBLISH_ROOT"

echo
echo "Done. Output:"
echo "  $DEST_MAIN"
echo "  $DEST_PLUGINS"
