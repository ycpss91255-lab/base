package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ycpss91255-lab/base/dockerfile/config-gen/internal/testcorpus"
)

// `config-gen ini tokens <file>` prints exactly the bytes the shell's
// `_ini_tokenize` printed for the same file, with exit 0 and nothing on
// stderr. The want bytes are the goldens captured from the shell into
// golden/s25, one `<stem>.tokens.golden` per corpus/s25 fixture; the
// s25_layer_* and s25_blockers_* fixtures belong to later slices
// (base#1758).
func TestIniTokensPrintsTheShellGolden(t *testing.T) {
	for _, src := range testcorpus.Glob(t, "corpus/s25/s25_[^lb]*.ini") {
		stem := strings.TrimSuffix(filepath.Base(src), ".ini")
		t.Run(stem, func(t *testing.T) {
			golden := testcorpus.Glob(t, "golden/s25/"+stem+".tokens.golden")[0]
			want, err := os.ReadFile(golden)
			if err != nil {
				t.Fatalf("read %s: %v", golden, err)
			}
			rc, stdout, stderr := cli(t, "ini", "tokens", src)
			if rc != 0 {
				t.Fatalf("config-gen ini tokens exited %d, want 0 (stderr %q)", rc, stderr)
			}
			if !bytes.Equal(stdout, want) {
				t.Fatalf("config-gen ini tokens stdout = %q, want the shell golden %q", stdout, want)
			}
			if len(stderr) != 0 {
				t.Fatalf("config-gen ini tokens stderr = %q, want empty", stderr)
			}
		})
	}
}

// Worked literals from the issue (base#1758), independent of the goldens:
// comment lines, indented comment lines and blank lines are skipped, and a
// key=value before the first header is dropped.
func TestIniTokensWorkedLiterals(t *testing.T) {
	for _, tc := range []struct {
		stem string
		want string
	}{
		{"s25_comments", "section\timage\nsection\tbuild\nentry\timage\tbase\texample:tag\nentry\tbuild\ttarget_arch\tx86_64\n"},
		{"s25_keys_before_header", "section\timage\nentry\timage\tbase\tubuntu\n"},
	} {
		t.Run(tc.stem, func(t *testing.T) {
			src := testcorpus.Glob(t, "corpus/s25/"+tc.stem+".ini")[0]
			rc, stdout, stderr := cli(t, "ini", "tokens", src)
			if rc != 0 {
				t.Fatalf("config-gen ini tokens exited %d, want 0 (stderr %q)", rc, stderr)
			}
			if string(stdout) != tc.want {
				t.Fatalf("config-gen ini tokens stdout = %q, want %q", stdout, tc.want)
			}
		})
	}
}

// A file that does not exist prints nothing and exits 0, as
// `_ini_tokenize`'s `[[ -f ]] || return 0` does (base#1758).
func TestIniTokensMissingFileIsEmptySuccess(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "absent.ini")
	rc, stdout, stderr := cli(t, "ini", "tokens", missing)
	if rc != 0 {
		t.Fatalf("config-gen ini tokens exited %d, want 0 (stderr %q)", rc, stderr)
	}
	if len(stdout) != 0 {
		t.Fatalf("config-gen ini tokens stdout = %q, want empty", stdout)
	}
	if len(stderr) != 0 {
		t.Fatalf("config-gen ini tokens stderr = %q, want empty", stderr)
	}
}

// No subcommand, a subcommand other than `tokens`, or an argument count
// other than exactly one file exits 2 with nothing on stdout and exactly
// one `config_gen_usage_invalid` frame, as `tables` does (base#1758).
func TestIniWrongArgvIsOneUsageFrame(t *testing.T) {
	src := testcorpus.Glob(t, "corpus/s25/s25_comments.ini")[0]
	for _, tc := range []struct {
		name string
		args []string
	}{
		{"no_subcommand", []string{"ini"}},
		{"other_subcommand", []string{"ini", "dump", src}},
		{"no_file", []string{"ini", "tokens"}},
		{"extra_file", []string{"ini", "tokens", src, src}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rc, stdout, stderr := cli(t, tc.args...)
			if rc != 2 {
				t.Fatalf("config-gen %q exited %d, want 2 (stderr %q)", tc.args, rc, stderr)
			}
			if len(stdout) != 0 {
				t.Fatalf("config-gen %q stdout = %q, want empty", tc.args, stdout)
			}
			refusal(t, stderr, "config_gen_usage_invalid", "")
		})
	}
}
