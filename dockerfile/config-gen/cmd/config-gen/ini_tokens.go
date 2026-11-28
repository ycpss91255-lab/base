package main

import (
	"io"
	"os"
	"strings"

	"github.com/ycpss91255-lab/base/dockerfile/config-gen/internal/diag"
)

func init() {
	Register("ini", iniCmd)
}

// iniSpace is bash's [:space:], the set `_ini_tokenize` trims.
const iniSpace = " \t\n\v\f\r"

// iniCmd is `config-gen ini tokens <file>`: it prints the records the shell's
// `_ini_tokenize` collected from the INI file, in one write: a
// `section\t<name>` line per distinct section in first-appearance order,
// then an `entry\t<section>\t<key>\t<value>` line per key=value line in
// file order (base#1758). Comment and blank lines are skipped, key and
// value are trimmed, and a key=value before the first header is dropped. A
// file that cannot be read prints nothing and exits 0, as `[[ -f ]] ||
// return 0` does. Any argv but `tokens <file>` exits 2 with one
// `config_gen_usage_invalid` frame and nothing on stdout.
func iniCmd(args []string, stdout, stderr io.Writer) error {
	if len(args) != 2 || args[0] != "tokens" {
		return reported(fail(stderr, exitUsage, diag.Frame{
			Event: "config_gen_usage_invalid",
			Text:  "usage: ini tokens <file>",
		}), nil)
	}
	src, err := os.ReadFile(args[1])
	if err != nil {
		return nil
	}
	_, err = io.WriteString(stdout, iniTokens(string(src)))
	return err
}

// iniTokens is the tokenizer: section lines first, entry lines after.
func iniTokens(src string) string {
	var sections, entries strings.Builder
	seen := map[string]bool{}
	current := ""
	for _, line := range strings.Split(src, "\n") {
		line = strings.Trim(line, iniSpace)
		if line == "" || line[0] == '#' {
			continue
		}
		if len(line) > 2 && line[0] == '[' && line[len(line)-1] == ']' {
			current = line[1 : len(line)-1]
			if !seen[current] {
				seen[current] = true
				sections.WriteString("section\t" + current + "\n")
			}
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if current == "" || !ok {
			continue
		}
		entries.WriteString("entry\t" + current + "\t" + strings.Trim(k, iniSpace) + "\t" + strings.Trim(v, iniSpace) + "\n")
	}
	return sections.String() + entries.String()
}
