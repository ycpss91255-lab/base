// Package load reads the setup.toml layers of a merge and refuses the
// ones that are not fit to merge (base#1854).
package load

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"syscall"

	"github.com/ycpss91255-lab/base/dockerfile/config-gen/internal/schema"
)

// Layer is one decoded layer and the path it was read from.
type Layer struct {
	Path   string
	Config *schema.Config
}

// Refusal is one reason a layer is refused: the event id, the layer's
// path (empty for merge_no_files), the key, the 1-based line and column
// (0 when unknown) and the display text when the event carries one.
type Refusal struct {
	Event string
	Path  string
	Key   string
	Line  int
	Col   int
	Text  string
}

// Load reads and decodes each path, in order. A path that does not exist
// contributes nothing. With no paths the one refusal is merge_no_files. A
// path that is not a regular file is merge_layer_not_regular, one that
// cannot be read is config_gen_check_input_failed, and each refusal of
// schema.Decode is returned with the path of its layer. Every layer is
// processed, so the refusals of several layers come back in path order.
// When there is any refusal the layers are nil.
func Load(paths []string) ([]Layer, []Refusal) {
	if len(paths) == 0 {
		return nil, []Refusal{{Event: "merge_no_files"}}
	}
	var layers []Layer
	var refusals []Refusal
	for _, path := range paths {
		src, err := read(path)
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if errors.Is(err, errNotRegular) {
			refusals = append(refusals, Refusal{Event: "merge_layer_not_regular", Path: path})
			continue
		}
		if err != nil {
			refusals = append(refusals, Refusal{Event: "config_gen_check_input_failed", Path: path, Text: err.Error()})
			continue
		}
		cfg, refused := schema.Decode(src)
		for _, r := range refused {
			refusals = append(refusals, Refusal{Event: r.Event, Path: path, Key: r.Key(), Line: r.Line, Col: r.Col})
		}
		if len(refused) == 0 {
			layers = append(layers, Layer{Path: path, Config: cfg})
		}
	}
	if refusals != nil {
		return nil, refusals
	}
	return layers, nil
}

var errNotRegular = errors.New("not a regular file")

// read reads the regular file at path. It is opened non-blocking and
// checked on the open descriptor, so a FIFO is refused rather than
// waited on (base#1400).
func read(path string) ([]byte, error) {
	f, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NONBLOCK, 0)
	if err != nil {
		return nil, err
	}
	defer func() { _ = f.Close() }()
	if info, err := f.Stat(); err != nil || !info.Mode().IsRegular() {
		return nil, fmt.Errorf("%s: %w", path, errNotRegular)
	}
	return io.ReadAll(f)
}
