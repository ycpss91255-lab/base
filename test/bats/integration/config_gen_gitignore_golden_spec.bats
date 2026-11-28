#!/usr/bin/env bats
#
# config_gen_gitignore_golden_spec.bats -- the s82 corpus of the shell
# gitignore helpers against testdata/golden/s82 (base#2064, slice S82a of
# base#1818 / base#1754 under base#1395).
#
# why: Before any Go code replaces the gitignore parsing, today's shell
# behaviour is pinned as goldens. The shell function is the oracle: this
# spec re-runs it on every input in a scratch directory and fails on any
# byte difference from the stored golden. One golden per input:
#
#   rc=<exit code>
#   mode=<octal mode of the target file after the call, or absent>
#   --- file
#   <exact bytes of the target file after the call>
#   --- stdout
#   <stdout of the call>
#   --- stderr
#   <one event per line: SEVERITY body key=value ...>
#
# The scratch directory path is written as TMP. Names carry the s82_
# prefix, since corpus basenames are unique across slices. A JSON event
# line is projected by _project_stream to `SEVERITY body key=value ...`
# without timestamp, code.* and thread.id, which change on every run
# (base#2086).

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  S="${BATS_TEST_TMPDIR}"
}

# Golden names with no corpus input: the case calls the function on a path
# that does not exist, or reuses another case's input (s82_sync_mode).
_S82_INPUTLESS=(s82_prune_absent s82_sync_absent s82_sync_mode
  s82_pathspec_log s82_pathspec_coverage s82_pathspec_env
  s82_pathspec_deploy s82_pathspec_empty s82_logging_create
  s82_logging_empty_absent)

# _partition_violations -- print one line per corpus input with no golden
# and per golden with neither an input nor a listed inputless name.
_partition_violations() {
  local _f _stem _n _ok
  for _f in "${TESTDATA}"/corpus/s82/*.gitignore; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .gitignore)"
    [[ -f "${TESTDATA}/golden/s82/${_stem}.golden" ]] \
      || printf 'corpus input with no golden: %s\n' "${_stem}"
  done
  for _f in "${TESTDATA}"/golden/s82/*.golden; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .golden)"
    _ok=0
    [[ -f "${TESTDATA}/corpus/s82/${_stem}.gitignore" ]] && _ok=1
    for _n in "${_S82_INPUTLESS[@]}"; do
      [[ "${_n}" == "${_stem}" ]] && _ok=1
    done
    (( _ok == 1 )) || printf 'golden with no corpus input: %s\n' "${_stem}"
  done
  return 0
}

# _write_actual <name> <rc> -- snapshot rc, target mode, target file,
# stdout and stderr of the last run into ${S}/actual/<name>.golden, with the
# work dir path replaced by TMP. Shared by _run_case and _run_sync_case.
_write_actual() {
  local _name="${1}" _rc="${2}"
  local _tgt="${S}/w/.gitignore" _m
  if [[ -e "${_tgt}" ]]; then
    _m="$(stat -c %a -- "${_tgt}")"
  else
    _m=absent
  fi
  {
    printf 'rc=%d\nmode=%s\n--- file\n' "${_rc}" "${_m}"
    if [[ -e "${_tgt}" ]]; then cat -- "${_tgt}"; fi
    printf -- '--- stdout\n'
    _project_stream "${S}/stdout"
    printf -- '--- stderr\n'
    _project_stream "${S}/stderr"
  } > "${S}/actual/${_name}.golden"
}

# _project_stream <file> -- print <file> with the work dir path replaced by
# TMP. A JSON event line is reduced to `SEVERITY body key=value ...` (the
# attributes, sorted by key), so timestamp, code.* and thread.id, which
# change on every run, never reach the golden (base#2086). Any other line
# is copied as is.
_project_stream() {
  local _line
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    if [[ "${_line}" == '{'* ]]; then
      jq -r '[.severity_text, .body]
        + [ .attributes // {} | to_entries | sort_by(.key)[]
            | select(.key | test("^(code\\.|thread\\.id$)") | not)
            | "\(.key)=\(.value)" ] | join(" ")' <<< "${_line}"
    else
      printf '%s\n' "${_line}"
    fi
  done < "${1}" | sed "s|${S}/w|TMP|g"
}

# _run_case <name> <target-mode|-> <override-retired:yes|no> <input|->
# -- run _prune_retired_entries in ${S}/w and write the actual golden to
# ${S}/actual/<name>.golden. <input> is a corpus file copied to the target
# (given <target-mode> when not `-`); `-` calls the function on a missing
# path. <override-retired> yes replaces _retired_gitignore_entries with
# `old1` and `old2`; no keeps the production function.
_run_case() {
  local _name="${1}" _mode="${2}" _override="${3}" _input="${4}"
  local _tgt="${S}/w/.gitignore" _rc=0
  rm -rf -- "${S}/w"
  mkdir -p "${S}/w" "${S}/actual"
  if [[ "${_input}" != - ]]; then
    cp -- "${TESTDATA}/corpus/s82/${_input}" "${_tgt}"
    [[ "${_mode}" == - ]] || chmod "${_mode}" "${_tgt}"
  fi
  (
    # shellcheck source=dist/script/docker/lib/gitignore.sh
    source /source/dist/script/docker/lib/gitignore.sh
    if [[ "${_override}" == yes ]]; then
      _retired_gitignore_entries() { printf 'old1\nold2\n'; }
    fi
    _prune_retired_entries "${_tgt}"
  ) > "${S}/stdout" 2> "${S}/stderr" || _rc=$?
  _write_actual "${_name}" "${_rc}"
}

# _run_sync_case <name> <input|-> [target-mode|-] -- run
# _sync_managed_entries with _canonical_gitignore_entries in ${S}/w and
# write the actual golden to ${S}/actual/<name>.golden, same format as
# _run_case. <input> is a corpus file copied to the target (chmod to
# <target-mode> when not `-`, default `-`); `-` calls the function on a
# missing path (base#2213, base#2215).
_run_sync_case() {
  local _name="${1}" _input="${2}" _mode="${3:--}"
  local _tgt="${S}/w/.gitignore" _rc=0
  rm -rf -- "${S}/w"
  mkdir -p "${S}/w" "${S}/actual"
  if [[ "${_input}" != - ]]; then
    cp -- "${TESTDATA}/corpus/s82/${_input}" "${_tgt}"
    [[ "${_mode}" == - ]] || chmod "${_mode}" "${_tgt}"
  fi
  (
    # shellcheck source=dist/script/docker/lib/gitignore.sh
    source /source/dist/script/docker/lib/gitignore.sh
    _sync_managed_entries "${_tgt}" _canonical_gitignore_entries
  ) > "${S}/stdout" 2> "${S}/stderr" || _rc=$?
  _write_actual "${_name}" "${_rc}"
}

# _run_pathspec_case <name> <entry> -- run _canonical_entry_pathspec on
# <entry> and write the actual golden to ${S}/actual/<name>.golden, same
# format as _run_case. No target file is involved, so mode=absent and the
# file section is empty (base#2083).
_run_pathspec_case() {
  local _name="${1}" _entry="${2}" _rc=0
  rm -rf -- "${S}/w"
  mkdir -p "${S}/w" "${S}/actual"
  (
    # shellcheck source=dist/script/docker/lib/gitignore.sh
    source /source/dist/script/docker/lib/gitignore.sh
    _canonical_entry_pathspec "${_entry}"
  ) > "${S}/stdout" 2> "${S}/stderr" || _rc=$?
  _write_actual "${_name}" "${_rc}"
}

# _run_logging_case <name> <input|-> <global> <per_svc> -- run
# _sync_logging_gitignore in ${S}/w and write the actual golden to
# ${S}/actual/<name>.golden, same format as _run_case. _collect_logging is
# replaced by a stub that hands back <global> (lines `local_path=<v>`) and
# <per_svc> (lines `<svc>:local_path=<v>`), the two outputs the function
# reads, so no setup.toml is involved. <input> is a corpus file copied to
# the target; `-` calls the function with no .gitignore (base#2084).
_run_logging_case() {
  local _name="${1}" _input="${2}" _glob="${3}" _svc="${4}"
  local _tgt="${S}/w/.gitignore" _rc=0
  rm -rf -- "${S}/w"
  mkdir -p "${S}/w" "${S}/actual"
  if [[ "${_input}" != - ]]; then
    cp -- "${TESTDATA}/corpus/s82/${_input}" "${_tgt}"
  fi
  (
    # shellcheck source=dist/script/docker/lib/gitignore.sh
    source /source/dist/script/docker/lib/gitignore.sh
    _collect_logging() {
      local -n _o_glob="${2}" _o_svc="${3}"
      _o_glob="${_glob}"
      _o_svc="${_svc}"
    }
    _sync_logging_gitignore "${S}/w"
  ) > "${S}/stdout" 2> "${S}/stderr" || _rc=$?
  _write_actual "${_name}" "${_rc}"
}

# _assert_golden <name> -- the stored golden exists and equals the actual
# one byte for byte. cmp, never $(...), which drops trailing LFs.
_assert_golden() {
  local _gold="${TESTDATA}/golden/s82/${1}.golden"
  [[ -f "${_gold}" ]] || fail "no golden for ${1}: ${_gold}"
  cmp -- "${_gold}" "${S}/actual/${1}.golden" \
    || fail "$(diff -u "${_gold}" "${S}/actual/${1}.golden")"
}

# why: a fixture with no golden would be read against nothing, and a stale
# golden would stand for a case no longer run.
@test "s82 corpus: every input has a golden and every golden an input" {
  run _partition_violations
  assert_success
  assert_output ""
}

# why: the managed half is the lines below the marker; the entry above it
# is the user's own and stays, both retired entries below go, the missing
# final newline is added, and the file keeps mode 640 (base#1356).
@test "s82 prune: retired entries go below the marker only" {
  _run_case s82_prune_below 640 yes s82_prune_below.gitignore
  _assert_golden s82_prune_below
}

# why: with no marker nothing is claimed as managed, so nothing is pruned.
@test "s82 prune: a file with no marker is unchanged" {
  _run_case s82_prune_no_marker - yes s82_prune_no_marker.gitignore
  _assert_golden s82_prune_no_marker
}

# why: an absent target is a no-op: rc 0 and no file is created.
@test "s82 prune: an absent target is a no-op and creates no file" {
  _run_case s82_prune_absent - yes -
  _assert_golden s82_prune_absent
}

# why: the production retired list is empty today, so a marker alone prunes
# nothing; this case keeps the production function.
@test "s82 prune: the empty production retired list leaves the file unchanged" {
  _run_case s82_prune_empty_list - no s82_prune_empty_list.gitignore
  _assert_golden s82_prune_empty_list
}

# why: first sync of a file whose last line has no newline: the newline is
# added, then the marker and all 18 canonical entries follow (base#2213).
@test "s82 sync: a first sync terminates the last line and adds marker and entries" {
  _run_sync_case s82_sync_no_newline s82_sync_no_newline.gitignore
  _assert_golden s82_sync_no_newline
}

# why: an absent target is created holding the marker and all 18 entries
# (base#2213).
@test "s82 sync: an absent target is created with marker and entries" {
  _run_sync_case s82_sync_absent -
  _assert_golden s82_sync_absent
}

# why: a file already ending in a lone blank line gets the marker right
# after it, with no extra blank line (base#2213).
@test "s82 sync: a lone trailing newline gets the marker with no extra blank line" {
  _run_sync_case s82_sync_lone_newline s82_sync_lone_newline.gitignore
  _assert_golden s82_sync_lone_newline
}

# why: a file that already has the marker gets only the missing canonical
# entry (compose.yaml) appended at the end; every other line stays
# (base#2215).
@test "s82 sync: an existing marker gets only the missing entry appended" {
  _run_sync_case s82_sync_missing_one s82_sync_missing_one.gitignore
  _assert_golden s82_sync_missing_one
}

# why: a file with the marker and all 18 entries is left byte for byte
# (base#2215).
@test "s82 sync: a complete file is left unchanged" {
  _run_sync_case s82_sync_complete s82_sync_complete.gitignore
  _assert_golden s82_sync_complete
}

# why: the missing entry is appended in place, so the file keeps mode 640
# (base#2215).
@test "s82 sync: an in-place append keeps the file mode" {
  _run_sync_case s82_sync_mode s82_sync_missing_one.gitignore 640
  _assert_golden s82_sync_mode
}

# why: a trailing slash marks a directory in a pattern and means nothing in
# a pathspec, so it is dropped (base#2083).
@test "s82 pathspec: a trailing slash is dropped from log/" {
  _run_pathspec_case s82_pathspec_log "log/"
  _assert_golden s82_pathspec_log
}

@test "s82 pathspec: a trailing slash is dropped from coverage/" {
  _run_pathspec_case s82_pathspec_coverage "coverage/"
  _assert_golden s82_pathspec_coverage
}

# why: an entry with no slash passes through unchanged (base#2083).
@test "s82 pathspec: a plain file entry is unchanged" {
  _run_pathspec_case s82_pathspec_env ".env"
  _assert_golden s82_pathspec_env
}

# why: a leading slash anchors a pattern and has no settled pathspec
# translation, so it is refused with rc 1 and no output (base#2083).
@test "s82 pathspec: a leading slash is refused" {
  _run_pathspec_case s82_pathspec_deploy "/deploy/"
  _assert_golden s82_pathspec_deploy
}

# why: an empty entry names nothing, so it is refused with rc 1 (base#2083).
@test "s82 pathspec: an empty entry is refused" {
  _run_pathspec_case s82_pathspec_empty ""
  _assert_golden s82_pathspec_empty
}

# why: the lines between the begin and end markers are template-owned and
# are rewritten to the desired entry; the stale /old/ goes and the lines
# outside the block stay (base#2084).
@test "s82 logging: the managed block is rewritten to the desired entry" {
  _run_logging_case s82_logging_rewrite s82_logging_rewrite.gitignore \
    "local_path=log/a/" ""
  _assert_golden s82_logging_rewrite
}

# why: only relative paths are entries; a leading ./ and trailing / are
# normalised, duplicates collapse, and absolute and ~ paths are skipped. An
# absent file is created holding the block (base#2084).
@test "s82 logging: an absent file is created with the normalised entries" {
  _run_logging_case s82_logging_create - \
    $'local_path=log/a/\nlocal_path=./log/a\nlocal_path=/abs\nlocal_path=~/x' \
    "svc:local_path=log/b"
  _assert_golden s82_logging_create
}

# why: a block left with no entries is removed, both markers with it
# (base#2084).
@test "s82 logging: an emptied block loses both markers" {
  _run_logging_case s82_logging_empty_block s82_logging_empty_block.gitignore \
    "" ""
  _assert_golden s82_logging_empty_block
}

# why: no block and nothing desired leaves the file byte for byte
# (base#2084).
@test "s82 logging: no block and no entries leaves the file unchanged" {
  _run_logging_case s82_logging_empty_no_block \
    s82_logging_empty_no_block.gitignore "" ""
  _assert_golden s82_logging_empty_no_block
}

# why: an absent file with nothing desired stays absent (base#2084).
@test "s82 logging: an absent file with no entries stays absent" {
  _run_logging_case s82_logging_empty_absent - "" ""
  _assert_golden s82_logging_empty_absent
}

# why: a legacy unbounded block is migrated to begin/end markers; the stale
# /stale/ below it is left outside the block and named in an orphans WARN,
# while the non-/dir/ line `user` is not named (base#2086).
@test "s82 logging: a legacy block is migrated and a stale dir is reported" {
  _run_logging_case s82_logging_legacy_orphan s82_logging_legacy_orphan.gitignore \
    "local_path=log/a/" ""
  _assert_golden s82_logging_legacy_orphan
}

# why: a second orphan shape: a /deploy/ line below the legacy block is
# reported the same way (base#2086).
@test "s82 logging: a legacy block with a deploy dir below reports it" {
  _run_logging_case s82_logging_legacy_deploy s82_logging_legacy_deploy.gitignore \
    "local_path=log/a/" ""
  _assert_golden s82_logging_legacy_deploy
}

# why: nothing below the legacy block means the migration INFO only, no
# orphans WARN (base#2086).
@test "s82 logging: a legacy block with nothing below emits no orphans" {
  _run_logging_case s82_logging_legacy_clean s82_logging_legacy_clean.gitignore \
    "local_path=log/a/" ""
  _assert_golden s82_logging_legacy_clean
}
