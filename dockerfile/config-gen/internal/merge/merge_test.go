package merge

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/ycpss91255-lab/base/dockerfile/config-gen/internal/load"
	"github.com/ycpss91255-lab/base/dockerfile/config-gen/internal/schema"
)

// layer decodes src into a layer; a layer the schema refuses fails the
// test, so every fixture below is a layer Load would hand to Merge.
func layer(t *testing.T, src string) load.Layer {
	t.Helper()
	cfg, refused := schema.Decode([]byte(src))
	if len(refused) != 0 {
		t.Fatalf("fixture refused: %+v\n%s", refused, src)
	}
	return load.Layer{Path: "layer.toml", Config: cfg}
}

func layers(t *testing.T, srcs ...string) []load.Layer {
	t.Helper()
	var out []load.Layer
	for _, s := range srcs {
		out = append(out, layer(t, s))
	}
	return out
}

func quote(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

// valueJSON writes v as the bridge's JSON does: `, ` and `: ` separators.
func valueJSON(v schema.Value) string {
	switch v.Kind {
	case schema.VArray:
		parts := []string{}
		for _, it := range v.Items {
			parts = append(parts, valueJSON(it))
		}
		return "[" + strings.Join(parts, ", ") + "]"
	case schema.VTable:
		parts := []string{}
		for _, m := range v.Members {
			parts = append(parts, quote(m.Key)+": "+valueJSON(m.Value))
		}
		return "{" + strings.Join(parts, ", ") + "}"
	}
	return quote(v.Scalar.Text)
}

func nodeJSON(r Result, i int) string {
	parts := []string{}
	for _, c := range r.Tree.Nodes[i].Children {
		switch c.Kind {
		case schema.ChildNode:
			parts = append(parts, quote(c.Key)+": "+nodeJSON(r, c.Node))
		case schema.ChildRow:
			parts = append(parts, quote(c.Key)+": "+quote(c.Row.Value.Text))
		case schema.ChildDeferred:
			parts = append(parts, quote(c.Key)+": "+valueJSON(r.Deferred[c.Defer].Value))
		}
	}
	return "{" + strings.Join(parts, ", ") + "}"
}

// resultJSON is the ordered JSON of a Result, the shape of
// `toml_bridge.py --merge`.
func resultJSON(r Result) string {
	if len(r.Tree.Nodes) == 0 {
		return "{}"
	}
	return nodeJSON(r, 0)
}

// Each expected value below is the JSON `toml_bridge.py --merge` printed
// for the same layers, low to high (base#1855).
func TestMergeMatchesBridge(t *testing.T) {
	cases := []struct {
		name string
		in   []string
		want string
	}{
		{"table key-level merge",
			[]string{"[environment]\nA = \"1\"\n", "[environment]\nB = \"2\"\n"},
			`{"environment": {"A": "1", "B": "2"}}`},
		{"array replaces whole",
			[]string{"[[volumes]]\nsrc = \"a\"\n", "[[volumes]]\nsrc = \"b\"\n"},
			`{"volumes": [{"src": "b"}]}`},
		{"empty array replaces",
			[]string{"[[volumes]]\nsrc = \"a\"\n", "volumes = []\n"},
			`{"volumes": []}`},
		{"absent array inherits",
			[]string{"[[volumes]]\nsrc = \"a\"\n", "[deploy]\ngpu_mode = \"all\"\n"},
			`{"volumes": [{"src": "a"}], "deploy": {"gpu_mode": "all"}}`},
		{"empty table exists",
			[]string{"[environment]\n"},
			`{"environment": {}}`},
		{"empty table after a table",
			[]string{"[deploy]\ngpu_mode = \"all\"\n", "[environment]\n"},
			`{"deploy": {"gpu_mode": "all"}, "environment": {}}`},
		{"empty upper table keeps lower keys",
			[]string{"[environment]\nA = \"1\"\n", "[environment]\n"},
			`{"environment": {"A": "1"}}`},
		{"alias un-inherit",
			[]string{"[deploy]\ngpu_runtime = \"nvidia\"\nruntime = \"runc\"\n", "[deploy]\nruntime = \"runc\"\n"},
			`{"deploy": {"runtime": "runc"}}`},
		{"alias canonical in the same layer stays",
			[]string{"[deploy]\nruntime = \"runc\"\n", "[deploy]\ngpu_runtime = \"nvidia\"\nruntime = \"runc\"\n"},
			`{"deploy": {"runtime": "runc", "gpu_runtime": "nvidia"}}`},
		{"stage alias un-inherit",
			[]string{"[\"stage:x\"]\n\"deploy.gpu_runtime\" = \"nvidia\"\nk = \"v\"\n", "[\"stage:x\"]\n\"deploy.runtime\" = \"runc\"\n"},
			`{"stage:x": {"k": "v", "deploy.runtime": "runc"}}`},
		{"stage table key-level merge",
			[]string{"[\"stage:x\"]\nk = \"v\"\n", "[\"stage:x\"]\nj = \"w\"\n"},
			`{"stage:x": {"k": "v", "j": "w"}}`},
		{"three layers",
			[]string{
				"[deploy]\ngpu_mode = \"all\"\n",
				"[environment]\nA = \"1\"\n[[volumes]]\nsrc = \"a\"\n[deploy]\ngpu_runtime = \"auto\"\n[\"stage:x\"]\n\"deploy.gpu_runtime\" = \"nvidia\"\nk = \"v\"\n",
				"volumes = []\n[environment]\n[\"stage:x\"]\n\"deploy.runtime\" = \"runc\"\n[deploy]\nruntime = \"runc\"\n",
			},
			`{"deploy": {"gpu_mode": "all", "runtime": "runc"}, "environment": {"A": "1"}, "volumes": [], "stage:x": {"k": "v", "deploy.runtime": "runc"}}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := resultJSON(Merge(layers(t, c.in...)))
			if got != c.want {
				t.Errorf("got  %s\nwant %s", got, c.want)
			}
		})
	}
}

func TestMergeNilIsEmpty(t *testing.T) {
	if got := resultJSON(Merge(nil)); got != "{}" {
		t.Errorf("Merge(nil) = %s, want {}", got)
	}
}

func TestMergeIsDeterministic(t *testing.T) {
	in := layers(t,
		"[deploy]\ngpu_mode = \"all\"\n",
		"[environment]\nA = \"1\"\nB = \"2\"\nC = \"3\"\n[\"stage:x\"]\nk = \"v\"\nj = \"w\"\n",
		"[environment]\nD = \"4\"\n[\"stage:x\"]\ni = \"u\"\n",
	)
	first := resultJSON(Merge(in))
	for i := 0; i < 50; i++ {
		if got := resultJSON(Merge(in)); got != first {
			t.Fatalf("run %d differs:\n%s\n%s", i, got, first)
		}
	}
}
