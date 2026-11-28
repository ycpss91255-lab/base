package load

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"syscall"
	"testing"
	"time"
)

// layerFile writes src to name under a fresh directory and returns its path.
func layerFile(t *testing.T, name, src string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(src), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// validLayer is a layer schema.Decode accepts without a refusal.
const validLayer = "# a layer with nothing set\n"

// unknownTable is a layer whose only fault is the unknown table [foo], on
// line 1 (event conf_unknown_table, key foo).
const unknownTable = "[foo]\n"

func TestLoadNoPathsIsMergeNoFiles(t *testing.T) {
	for name, paths := range map[string][]string{"nil": nil, "empty": {}} {
		layers, refusals := Load(paths)
		if layers != nil {
			t.Errorf("%s: layers = %v, want nil", name, layers)
		}
		want := []Refusal{{Event: "merge_no_files", Path: ""}}
		if !reflect.DeepEqual(refusals, want) {
			t.Errorf("%s: refusals = %+v, want %+v", name, refusals, want)
		}
	}
}

func TestLoadAbsentPathContributesNothing(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "absent.toml")
	layers, refusals := Load([]string{missing})
	if len(layers) != 0 || refusals != nil {
		t.Fatalf("Load(absent) = (%v, %v), want no layers and nil refusals", layers, refusals)
	}
}

func TestLoadSkipsAbsentBetweenPresentLayers(t *testing.T) {
	a := layerFile(t, "a.toml", validLayer)
	c := layerFile(t, "c.toml", validLayer)
	missing := filepath.Join(t.TempDir(), "absent.toml")
	layers, refusals := Load([]string{a, missing, c})
	if refusals != nil {
		t.Fatalf("refusals = %+v, want nil", refusals)
	}
	if len(layers) != 2 || layers[0].Path != a || layers[1].Path != c {
		t.Fatalf("layer paths = %+v, want [%s %s]", layers, a, c)
	}
	for _, l := range layers {
		if l.Config == nil {
			t.Errorf("layer %s has a nil Config", l.Path)
		}
	}
}

func TestLoadDirectoryIsNotRegular(t *testing.T) {
	dir := t.TempDir()
	layers, refusals := Load([]string{dir})
	if layers != nil {
		t.Errorf("layers = %v, want nil", layers)
	}
	want := []Refusal{{Event: "merge_layer_not_regular", Path: dir}}
	if len(refusals) != 1 || refusals[0].Event != want[0].Event || refusals[0].Path != want[0].Path {
		t.Fatalf("refusals = %+v, want event %s on %s", refusals, want[0].Event, dir)
	}
}

func TestLoadFifoIsNotRegularAndDoesNotBlock(t *testing.T) {
	fifo := filepath.Join(t.TempDir(), "layer.fifo")
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Fatal(err)
	}
	type result struct {
		layers   []Layer
		refusals []Refusal
	}
	done := make(chan result, 1)
	go func() {
		l, r := Load([]string{fifo})
		done <- result{l, r}
	}()
	select {
	case got := <-done:
		if got.layers != nil {
			t.Errorf("layers = %v, want nil", got.layers)
		}
		if len(got.refusals) != 1 || got.refusals[0].Event != "merge_layer_not_regular" || got.refusals[0].Path != fifo {
			t.Fatalf("refusals = %+v, want merge_layer_not_regular on %s", got.refusals, fifo)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Load blocked on a FIFO with no writer")
	}
}

func TestLoadUnreadableFileIsInputFailed(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads a mode 000 file")
	}
	path := layerFile(t, "locked.toml", validLayer)
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	layers, refusals := Load([]string{path})
	if layers != nil {
		t.Errorf("layers = %v, want nil", layers)
	}
	if len(refusals) != 1 {
		t.Fatalf("refusals = %+v, want one", refusals)
	}
	r := refusals[0]
	if r.Event != "config_gen_check_input_failed" || r.Path != path {
		t.Errorf("refusal = %+v, want config_gen_check_input_failed on %s", r, path)
	}
	if !strings.Contains(r.Text, path) || !strings.Contains(r.Text, "permission denied") {
		t.Errorf("Text = %q, want it to hold %q and %q", r.Text, path, "permission denied")
	}
}

func TestLoadSchemaRefusalNamesItsLayer(t *testing.T) {
	path := layerFile(t, "bad.toml", unknownTable)
	layers, refusals := Load([]string{path})
	if layers != nil {
		t.Errorf("layers = %v, want nil", layers)
	}
	if len(refusals) != 1 {
		t.Fatalf("refusals = %+v, want one", refusals)
	}
	r := refusals[0]
	if r.Event != "conf_unknown_table" || r.Path != path || r.Key != "foo" || r.Line != 1 {
		t.Errorf("refusal = %+v, want conf_unknown_table on %s, key foo, line 1", r, path)
	}
	if r.Col < 1 {
		t.Errorf("Col = %d, want a known column", r.Col)
	}
}

func TestLoadRefusalOfSecondLayerOnly(t *testing.T) {
	first := layerFile(t, "first.toml", validLayer)
	second := layerFile(t, "second.toml", unknownTable)
	_, refusals := Load([]string{first, second})
	if len(refusals) != 1 || refusals[0].Path != second {
		t.Fatalf("refusals = %+v, want exactly one, on %s", refusals, second)
	}
}

func TestLoadEveryLayerIsProcessedInOrder(t *testing.T) {
	first := layerFile(t, "first.toml", unknownTable)
	second := layerFile(t, "second.toml", unknownTable)
	layers, refusals := Load([]string{first, second})
	if layers != nil {
		t.Errorf("layers = %v, want nil", layers)
	}
	if len(refusals) != 2 || refusals[0].Path != first || refusals[1].Path != second {
		t.Fatalf("refusals = %+v, want one on %s then one on %s", refusals, first, second)
	}
}
