# s43_arg_user_helper.bash -- shared helpers for the s43 arg_user
# (migration 7) golden specs (base#2348, S43n-1 of base#2074).
#
# why: the shell `apply_migrations` (dist/script/docker/lib/dockerfile_migrate.sh)
# with `_MIGRATIONS=( arg_user )` is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_arg_user_<case>.Dockerfile has
# three goldens under testdata/golden/s43/:
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .files       `migrated_files` stdout
#   .events      one projected event per line (see _project_events)
# Warning events go to stderr, so the run is captured with 2>&1.
# Each spec loads this file with `load` after setting up its own bats env.

LIB="${LIB:-/source/dist/script/docker/lib}"
TESTDATA="${TESTDATA:-/source/dockerfile/config-gen/testdata}"
CORPUS="${CORPUS:-${TESTDATA}/corpus/s43}"
GOLDEN="${GOLDEN:-${TESTDATA}/golden/s43}"

# _project_events <raw-json-lines-file> -- same projection as
# config_gen_s43_harness_golden_spec.bats.
_project_events() {
  jq -r '[.body, .attributes.display]
    + [ ("matched", "available", "names", "rewritten") as $k
        | select(.attributes[$k] != null)
        | "\($k)=\(.attributes[$k])" ]
    | join("\t")' "$1"
}

# _regen_case <case> -- run apply_migrations (arg_user only) on
# s43_arg_user_<case>.Dockerfile and leave out.{dockerfile,files,events}
# in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_arg_user_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
  [[ -f "${CORPUS}/${_name}.Dockerfile" ]] || {
    echo "fixture missing: ${_name}.Dockerfile" >&2
    return 1
  }
  mkdir -p "${_d}"
  cp -- "${CORPUS}/${_name}.Dockerfile" "${_d}/Dockerfile"
  (
    cd "${_d}" || exit 1
    LOG_FORMAT=json bash -c '
      source "$1/_lib.sh"; source "$1/dockerfile_migrate.sh"
      _MIGRATIONS=( arg_user )
      apply_migrations Dockerfile > raw.events 2>&1
      migrated_files > out.files
    ' _ "${LIB}"
  ) || return 1
  _project_events "${_d}/raw.events" > "${_d}/out.events"
  cp -- "${_d}/Dockerfile" "${_d}/out.dockerfile"
}

# _check_case <case> -- regenerate and compare each output with its golden.
_check_case() {
  local _name="s43_arg_user_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
  for _e in dockerfile files events; do
    [[ -f "${GOLDEN}/${_name}.${_e}" ]] || {
      echo "golden missing: ${_name}.${_e}" >&2
      _bad=1
    }
  done
  (( _bad == 0 )) || return 1
  _regen_case "$1" || return 1
  for _e in dockerfile files events; do
    cmp -- "${_d}/out.${_e}" "${GOLDEN}/${_name}.${_e}" || _bad=1
  done
  (( _bad == 0 ))
}

# _check_partition <case>... -- each listed case has exactly one fixture and
# exactly three goldens (s43_arg_user_<case>.* under the golden dir).
_check_partition() {
  local _c _e _f _n _bad=0
  for _c in "$@"; do
    [[ -f "${CORPUS}/s43_arg_user_${_c}.Dockerfile" ]] || {
      echo "fixture missing: s43_arg_user_${_c}.Dockerfile" >&2
      _bad=1
    }
    for _e in dockerfile files events; do
      [[ -f "${GOLDEN}/s43_arg_user_${_c}.${_e}" ]] || {
        echo "golden missing: s43_arg_user_${_c}.${_e}" >&2
        _bad=1
      }
    done
    _n=0
    for _f in "${GOLDEN}/s43_arg_user_${_c}".*; do
      [[ -e "${_f}" ]] || continue
      _n=$((_n + 1))
      case "${_f##*.}" in
        dockerfile | files | events) ;;
        *) echo "unexpected golden extension: ${_f}" >&2; _bad=1 ;;
      esac
    done
    (( _n == 3 )) || {
      echo "s43_arg_user_${_c}: expected 3 goldens, found ${_n}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
