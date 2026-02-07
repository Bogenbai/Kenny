#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${1:-Release}"

ARTIFACTS_DIR="$SCRIPT_DIR/Artifacts"
DEST_MAIN="$ARTIFACTS_DIR/Jenny"
DEST_PLUGINS="$ARTIFACTS_DIR/Jenny/Plugins/Jenny"
TMP_PUBLISH_ROOT="$SCRIPT_DIR/.publishout"

NUGET_DIR="${NUGET_PACKAGES:-$HOME/.nuget/packages}"

# ---------------------------
# Only these files will remain in Artifacts (missing = skipped)
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

# Projects to publish by *project name* (script will auto-find <Name>.csproj)
PROJECT_NAMES_TO_PUBLISH=(
  "Jenny.Generator.Cli"
  "Jenny.Generator"
  "Jenny"
  "Jenny.Plugins"
  "Jenny.Plugins.Unity"
  "Jenny.Plugins.Roslyn"
  "DesperateDevs.Roslyn"
)

# ---------------------------
# Helpers
# ---------------------------
require_unity_refs() {
  local ue="$SCRIPT_DIR/unity/Unity-2021.3.0f1/UnityEditor.dll"
  local ug="$SCRIPT_DIR/unity/Unity-2021.3.0f1/UnityEngine.dll"
  if [[ ! -f "$ue" || ! -f "$ug" ]]; then
    echo "ERROR: Unity reference DLLs not found:" >&2
    echo "  $ue" >&2
    echo "  $ug" >&2
    echo "Make sure they are committed (or Git LFS is enabled in CI checkout)." >&2
    exit 1
  fi
}

publish_csproj() {
  local csproj="$1"
  local name="$2"
  local out_dir="$TMP_PUBLISH_ROOT/$name"

  rm -rf "$out_dir"
  mkdir -p "$out_dir"

  echo "Publishing: $name"
  dotnet publish "$csproj" -c "$CONFIG" -o "$out_dir" \
    -p:DebugSymbols=false -p:DebugType=None
}

# Find csproj by exact file name "<ProjectName>.csproj"
find_csproj_by_name() {
  local proj_name="$1"
  local filename="$proj_name.csproj"
  local found=""
  found="$(find "$SCRIPT_DIR" -type f -name "$filename" 2>/dev/null | head -n 1 || true)"
  [[ -n "$found" ]] && { echo "$found"; return 0; }
  return 1
}

# Find a file by exact name in:
#  1) temp publish outputs (preferred)
#  2) NuGet cache (fallback)
find_file_anywhere() {
  local filename="$1"
  local found=""

  found="$(find "$TMP_PUBLISH_ROOT" -type f -name "$filename" 2>/dev/null | head -n 1 || true)"
  [[ -n "$found" ]] && { echo "$found"; return 0; }

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

# Fail fast if we're about to build Unity projects but Unity refs aren't present
if printf '%s\n' "${PROJECT_NAMES_TO_PUBLISH[@]}" | grep -qE '^Jenny\.Plugins\.Unity$|^Jenny\.Generator\.Unity\.Editor$'; then
  require_unity_refs
fi

# ---------------------------
# Publish allowlisted projects (auto-discovered paths)
# ---------------------------
for name in "${PROJECT_NAMES_TO_PUBLISH[@]}"; do
  csproj=""
  if csproj="$(find_csproj_by_name "$name")"; then
    publish_csproj "$csproj" "$name"
  else
    echo "WARN: csproj not found for project name '$name' (expected file '$name.csproj'), skipping" >&2
  fi
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

rm -rf "$TMP_PUBLISH_ROOT"

echo
echo "Done. Output:"
echo "  $DEST_MAIN"
echo "  $DEST_PLUGINS"
