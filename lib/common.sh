# shellcheck shell=bash
# Shared helpers for the solps-grids scripts.
# Keep this compatible with bash 3.2, the /bin/bash shipped with macOS.

SG_PROG=${0##*/}

# Settings that may come from local.env (see local.env.example)
SG_CONFIG_VARS="DEVICE DG_KIT DIVGEO_SRC GRID_WORKDIR MACPORTS_PREFIX"

sg_info() { printf '%s: %s\n' "$SG_PROG" "$*"; }
sg_warn() { printf '%s: warning: %s\n' "$SG_PROG" "$*" >&2; }
sg_die()  { printf '%s: error: %s\n' "$SG_PROG" "$*" >&2; exit 1; }

# Read $SG_ROOT/local.env. Settings that are already non-empty in the
# environment win, so the precedence is:
#   command-line option > environment > local.env > built-in default
sg_load_config() {
  local f=$SG_ROOT/local.env v saved=
  [ -f "$f" ] || return 0
  for v in $SG_CONFIG_VARS; do
    [ -n "${!v}" ] && saved="$saved $v=$(printf '%q' "${!v}")"
  done
  . "$f" || sg_die "cannot read $f"
  [ -z "$saved" ] || eval "$saved"
}

# sg_check_name KIND VALUE [MAXLEN]
# DivGeo and lns split file names on whitespace, so be strict.
sg_check_name() {
  case $2 in
    ''|.*|*[!A-Za-z0-9._-]*)
      sg_die "invalid $1 name '$2': use only letters, digits, '.', '_' and '-'" ;;
  esac
  if [ -n "$3" ] && [ ${#2} -gt "$3" ]; then
    sg_die "$1 name '$2' is longer than $3 characters"
  fi
}

sg_require_device() {
  [ -n "$DEVICE" ] ||
    sg_die "no device given: use -d DEVICE, or set DEVICE in the environment or in local.env"
  # B2.5 reads DEVICE into a character*12 variable (b2agfs.F)
  sg_check_name device "$DEVICE" 12
}

# The DivGeo git ref (tag, branch or commit) this repository is designed with
sg_divgeo_version() {
  [ -f "$SG_ROOT/DIVGEO_VERSION" ] || return 0
  awk '!/^[[:space:]]*#/ && NF { print $1; exit }' "$SG_ROOT/DIVGEO_VERSION"
}

# Physical absolute path of an existing file (symlinked directories resolved)
sg_phys_path() {
  local d
  d=$(cd -P "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$d" "$(basename "$1")"
}

# Replace the contents of FILE by TMP, keeping FILE's permissions and
# modification time (Triang and our own checks compare timestamps).
sg_replace_keep_mtime() {
  touch -r "$1" "$2" && cat "$2" > "$1" && touch -r "$2" "$1" && rm -f "$2"
}

# ---------------------------------------------------------------------------
# Compute side (SOLPS-ITER environment)

sg_require_solps() {
  [ -n "$SOLPSTOP" ] && [ -d "$SOLPSTOP" ] ||
    sg_die "SOLPSTOP is not set: run 'source <SOLPS-ITER>/setup.csh' in this shell first"
  [ -n "$DG" ] || DG=$SOLPSTOP/modules/DivGeo
  export DG
}

# sg_workdir CASE [EXPLICIT_DIR]: the Carre work directory of a case
sg_workdir() {
  if [ -n "$2" ]; then
    case $2 in /*) printf '%s\n' "$2" ;; *) printf '%s/%s\n' "$PWD" "$2" ;; esac
    return
  fi
  local root=$GRID_WORKDIR
  [ -n "$root" ] || root=${SOLPSWORK:-$SOLPSTOP/runs}/grids
  printf '%s/%s/%s\n' "$root" "$DEVICE" "$1"
}

# $DG/device/$DEVICE, where lns, Carre and Triang keep device files
# ($DEVICE/$USER for central installations, as in scripts/lns)
sg_dg_device_dir() {
  if [ "$SOLPS_CENTRAL" = yes ]; then
    printf '%s/device/%s/%s\n' "$DG" "$DEVICE" "$USER"
  else
    printf '%s/device/%s\n' "$DG" "$DEVICE"
  fi
}

# Warn if the DivGeo of this SOLPS installation differs from DIVGEO_VERSION:
# the variables written to .dgo files come from dg.dgc and must match Uinp.
sg_check_solps_divgeo_version() {
  local want want_c have_c
  want=$(sg_divgeo_version)
  [ -n "$want" ] || return 0
  if ! git -C "$DG" rev-parse --git-dir >/dev/null 2>&1; then
    sg_warn "cannot check the DivGeo version: $DG is not a git checkout"
    return 0
  fi
  if ! want_c=$(git -C "$DG" rev-parse -q --verify "$want^{commit}" 2>/dev/null); then
    sg_warn "DivGeo version '$want' (DIVGEO_VERSION) is unknown in $DG; try 'git -C \$DG fetch --tags'"
    return 0
  fi
  have_c=$(git -C "$DG" rev-parse HEAD)
  [ "$want_c" = "$have_c" ] ||
    sg_warn "SOLPS uses DivGeo $(git -C "$DG" describe --tags --always), but this repository expects $want (DIVGEO_VERSION)"
}
