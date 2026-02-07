#!/usr/bin/env bash
# build_jenny.sh
#
# Builds/publishes Jenny solution projects and gathers runtime files into:
#
# Artifacts/
#   Jenny/
#     <main dlls + runtime files>
#     Plugins/
#       Jenny/
#         <plugin dlls + runtime files>
#
# Key points:
# - Publishes projects one-by-one (so test projects + their deps never leak in).
# - Copies runtime metadata (.deps.json/.runtimeconfig.json) and native libs.
# - Ensures Roslyn dependency chain is present AND version-consistent (prevents CodeAnalysis/Workspaces mismatch).
#
# Usage:
#   ./build_jenny.sh Release
#   ./build_jenny.sh Debug
#
# Optional env vars:
#   ROSLYN_NUGET_VERSION=4.1.0   # pin Roslyn family version (recommended 4.1.0 based on your log)
#   NUGET_PACKAGES=...           # custom NuGet cache directory

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${1:-Release}"

# ---------------------------
# Locate solution
# ---------------------------
if [[ -f "$SCRIPT_DIR/Jenny.sln" ]]; then
  SOLUTION="$SCRIPT_DIR/Jenny.sln"
else
  SOLUTION_CANDIDATES=("$SCRIPT_DIR"/*.sln)
  [[ -e "${SOLUTION_CANDIDATES[0]}" ]] || { echo "ERROR: No .sln found in $SCRIPT_DIR"; exit 1; }
  SOLUTION="${SOLUTION_CANDIDATES[0]}"
fi

# ---------------------------
# Output layout (NO "DLLs" folders)
# ---------------------------
ARTIFACTS_DIR="$SCRIPT_DIR/Artifacts"
OUT_ROOT="$ARTIFACTS_DIR/Jenny"
DEST_MAIN="$OUT_ROOT"
DEST_PLUGINS="$OUT_ROOT/Plugins/Jenny"

TMP_PUBLISH_ROOT="$SCRIPT_DIR/.publishout"

export DEST_MAIN DEST_PLUGINS
export NUGET_PACKAGES="${NUGET_PACKAGES:-$HOME/.nuget/packages}"

# ---------------------------
# Clean
# ---------------------------
rm -rf "$ARTIFACTS_DIR" "$TMP_PUBLISH_ROOT"
mkdir -p "$DEST_MAIN" "$DEST_PLUGINS" "$TMP_PUBLISH_ROOT"

# ---------------------------
# Filters / routing
# ---------------------------
is_excluded_project() {
  local name="$1"
  case "$name" in
    *Tests*|*Test*|*Benchmarks*|*Benchmark*|*Fixture*)
      return 0 ;;
  esac
  return 1
}

# Route project output into Plugins/Jenny if name matches
is_plugin_project() {
  local name="$1"
  case "$name" in
    *Jenny.Plugins*|*".Plugins."*|*Plugins.Unity*)
      return 0 ;;
  esac
  return 1
}

# Identify CLI project name (adjust if needed)
is_cli_project() {
  local name="$1"
  [[ "$name" == "Jenny.Generator.Cli" ]]
}

# ---------------------------
# Copy publish output helper
# ---------------------------
copy_publish_output() {
  local src="$1"
  local dest="$2"
  local no_overwrite="${3:-0}"

  mkdir -p "$dest"
  shopt -s nullglob

  # runtime-relevant files for framework-dependent .NET apps/libs
  local files=(
    "$src"/*.dll
    "$src"/*.deps.json
    "$src"/*.runtimeconfig.json
    "$src"/*.dylib
    "$src"/*.so
    "$src"/*.a
    "$src"/*.pdb
  )

  # Native assets in runtimes/
  if [[ -d "$src/runtimes" ]]; then
    if [[ "$no_overwrite" == "1" && -d "$dest/runtimes" ]]; then
      :
    else
      rm -rf "$dest/runtimes"
      cp -R "$src/runtimes" "$dest/"
    fi
  fi

  local copied=0
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    local base
    base="$(basename "$f")"

    # don’t ship obvious test/benchmark artifacts even if they slip in
    if is_excluded_project "$base"; then
      continue
    fi

    if [[ "$no_overwrite" == "1" && -f "$dest/$base" ]]; then
      continue
    fi

    cp -f "$f" "$dest/"
    ((copied++)) || true
  done

  shopt -u nullglob
  echo "$copied"
}

# ---------------------------
# Roslyn: enforce a single consistent "family" version
# ---------------------------
ensure_roslyn_family() {
  local nuget_dir="${NUGET_PACKAGES:-$HOME/.nuget/packages}"

  # Your runtime log showed Workspaces/Features 4.1.0.0, so default to 4.1.0
  local v="${ROSLYN_NUGET_VERSION:-4.1.0}"

  echo
  echo "Ensuring Roslyn family DLLs from NuGet version: $v"

  copy_pkg_file() {
    local pkg="$1"
    local dll="$2"
    local src

    # prefer netstandard2.0
    src="$nuget_dir/$pkg/$v/lib/netstandard2.0/$dll"
    if [[ ! -f "$src" ]]; then
      src="$(find "$nuget_dir/$pkg/$v" -type f -name "$dll" 2>/dev/null | head -n 1 || true)"
    fi

    if [[ -n "$src" && -f "$src" ]]; then
      cp -f "$src" "$DEST_MAIN/"
      cp -f "$src" "$DEST_PLUGINS/"
      return 0
    fi

    echo "WARN: missing $dll in $pkg/$v"
    return 1
  }

  # Core
  copy_pkg_file "microsoft.codeanalysis.common" "Microsoft.CodeAnalysis.dll" || true
  copy_pkg_file "microsoft.codeanalysis.csharp" "Microsoft.CodeAnalysis.CSharp.dll" || true

  # Workspaces / Features (must match same version family)
  copy_pkg_file "microsoft.codeanalysis.workspaces.common" "Microsoft.CodeAnalysis.Workspaces.dll" || true
  copy_pkg_file "microsoft.codeanalysis.csharp.workspaces" "Microsoft.CodeAnalysis.CSharp.Workspaces.dll" || true
  copy_pkg_file "microsoft.codeanalysis.features" "Microsoft.CodeAnalysis.Features.dll" || true
  copy_pkg_file "microsoft.codeanalysis.csharp.features" "Microsoft.CodeAnalysis.CSharp.Features.dll" || true
  copy_pkg_file "microsoft.codeanalysis.visualbasic.workspaces" "Microsoft.CodeAnalysis.VisualBasic.Workspaces.dll" || true
  copy_pkg_file "microsoft.codeanalysis.visualbasic.features" "Microsoft.CodeAnalysis.VisualBasic.Features.dll" || true

  # MSBuild Workspace layer (used by MSBuildWorkspace.Create)
  copy_pkg_file "microsoft.codeanalysis.workspaces.msbuild" "Microsoft.CodeAnalysis.Workspaces.MSBuild.dll" || true

  # Common deps (version can vary; we copy whatever is available)
  for dep in "System.Collections.Immutable.dll" "System.Reflection.Metadata.dll"; do
    local f
    f="$(find "$nuget_dir" -type f -name "$dep" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$f" && -f "$f" ]]; then
      cp -f "$f" "$DEST_MAIN/"
      cp -f "$f" "$DEST_PLUGINS/"
    else
      echo "WARN: could not find $dep in NuGet cache"
    fi
  done
}

# ---------------------------
# Ensure Jenny.Plugins.Roslyn exists (if you restored it)
# ---------------------------
ensure_jenny_plugins_roslyn_present() {
  if [[ -f "$DEST_PLUGINS/Jenny.Plugins.Roslyn.dll" || -f "$DEST_MAIN/Jenny.Plugins.Roslyn.dll" ]]; then
    return 0
  fi

  echo
  echo "Ensuring Jenny.Plugins.Roslyn.dll ..."

  local found
  found="$(find "$SCRIPT_DIR" -type f -name "Jenny.Plugins.Roslyn.dll" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$found" ]]; then
    echo "WARN: Jenny.Plugins.Roslyn.dll not found under repo. (If you removed it intentionally, disable Roslyn providers.)"
    return 0
  fi

  # Prefer placing it in plugin folder; also copy to main for probing
  cp -f "$found" "$DEST_PLUGINS/"
  cp -f "$found" "$DEST_MAIN/"
  echo "Copied: $found"
}

# ---------------------------
# Read solution projects (bash 3 compatible)
# ---------------------------
PROJECT_PATHS=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  PROJECT_PATHS+=("$line")
done < <(dotnet sln "$SOLUTION" list | tail -n +3 | sed 's/^[[:space:]]*//')

[[ "${#PROJECT_PATHS[@]}" -gt 0 ]] || { echo "ERROR: Could not read projects from solution."; exit 1; }

# Resolve csproj paths and names
CSPROJS=()
NAMES=()
for rel_path in "${PROJECT_PATHS[@]}"; do
  if [[ -f "$rel_path" ]]; then
    CSPROJ="$rel_path"
  elif [[ -f "$SCRIPT_DIR/$rel_path" ]]; then
    CSPROJ="$SCRIPT_DIR/$rel_path"
  else
    echo "WARN: Project path not found: $rel_path (skipping)"
    continue
  fi
  name="$(basename "$CSPROJ" .csproj)"
  CSPROJS+=("$CSPROJ")
  NAMES+=("$name")
done

publish_one() {
  local csproj="$1"
  local name="$2"
  local out_dir="$TMP_PUBLISH_ROOT/$name"
  rm -rf "$out_dir"
  mkdir -p "$out_dir"
  echo "Publishing: $name"
  dotnet publish "$csproj" -c "$CONFIG" -o "$out_dir" \
    -p:DebugSymbols=false -p:DebugType=None
}

publish_count=0
skip_count=0
copied_main=0
copied_plugins=0

# ---------------------------
# 1) Publish + copy CLI first into main (so runtimeconfig/deps always present)
# ---------------------------
for i in "${!CSPROJS[@]}"; do
  name="${NAMES[$i]}"
  csproj="${CSPROJS[$i]}"

  if is_excluded_project "$name"; then
    ((skip_count++)) || true
    continue
  fi

  if is_cli_project "$name"; then
    publish_one "$csproj" "$name"
    out_dir="$TMP_PUBLISH_ROOT/$name"

    n="$(copy_publish_output "$out_dir" "$DEST_MAIN" 0)"
    copied_main=$((copied_main + n))
    ((publish_count++)) || true
  fi
done

# ---------------------------
# 2) Publish + copy all other non-test projects
#    - plugin projects -> Plugins/Jenny
#    - others -> main (no overwrite to preserve CLI bits)
# ---------------------------
for i in "${!CSPROJS[@]}"; do
  name="${NAMES[$i]}"
  csproj="${CSPROJS[$i]}"

  if is_excluded_project "$name"; then
    continue
  fi
  if is_cli_project "$name"; then
    continue
  fi

  publish_one "$csproj" "$name"
  out_dir="$TMP_PUBLISH_ROOT/$name"

  if is_plugin_project "$name"; then
    n="$(copy_publish_output "$out_dir" "$DEST_PLUGINS" 0)"
    copied_plugins=$((copied_plugins + n))
  else
    n="$(copy_publish_output "$out_dir" "$DEST_MAIN" 1)"
    copied_main=$((copied_main + n))
  fi

  ((publish_count++)) || true
done

# ---------------------------
# Final "fixups" (run last so they win)
# ---------------------------
ensure_jenny_plugins_roslyn_present
ensure_roslyn_family

# Cleanup temp publish outputs
rm -rf "$TMP_PUBLISH_ROOT"

echo
echo "Published projects : $publish_count"
echo "Skipped projects   : $skip_count (tests/benchmarks/fixtures)"
echo "Copied files:"
echo "  Main   -> $DEST_MAIN (files: $copied_main)"
echo "  Plugin -> $DEST_PLUGINS (files: $copied_plugins)"
echo
echo "Done → $ARTIFACTS_DIR"
