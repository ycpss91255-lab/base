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
	case schema.VScalar:
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

// The layers have the shape of the issue's bridge table rows, spelled with
// keys and values the schema accepts: the schema refuses a free-form
// [environment] key, `src`, `gpu_mode = "all"`, `runtime = "runc"` and a
// free-form stage key, so env_N, `source`, `force`, `off` and
// `network.*` stand in for them (base#1855). The merge outcome of each
// row does not depend on the key or value spelled.
func TestMergeMatchesBridge(t *testing.T) {
	cases := []struct {
		name string
		in   []string
		want string
	}{
		{"table key-level merge",
			[]string{"[environment]\nenv_1 = \"A=1\"\n", "[environment]\nenv_2 = \"B=2\"\n"},
			`{"environment": {"env_1": "A=1", "env_2": "B=2"}}`},
		{"array replaces whole",
			[]string{"[[volumes]]\nsource = \"a\"\n", "[[volumes]]\nsource = \"b\"\n"},
			`{"volumes": [{"source": "b"}]}`},
		{"empty array replaces",
			[]string{"[[volumes]]\nsource = \"a\"\n", "volumes = []\n"},
			`{"volumes": []}`},
		{"absent array inherits",
			[]string{"[[volumes]]\nsource = \"a\"\n", "[deploy]\ngpu_mode = \"force\"\n"},
			`{"volumes": [{"source": "a"}], "deploy": {"gpu_mode": "force"}}`},
		{"empty table exists",
			[]string{"[environment]\n"},
			`{"environment": {}}`},
		{"empty table after a table",
			[]string{"[deploy]\ngpu_mode = \"force\"\n", "[environment]\n"},
			`{"deploy": {"gpu_mode": "force"}, "environment": {}}`},
		{"empty upper table keeps lower keys",
			[]string{"[environment]\nenv_1 = \"A=1\"\n", "[environment]\n"},
			`{"environment": {"env_1": "A=1"}}`},
		{"alias un-inherit",
			[]string{"[deploy]\ngpu_runtime = \"nvidia\"\nruntime = \"off\"\n", "[deploy]\nruntime = \"off\"\n"},
			`{"deploy": {"runtime": "off"}}`},
		{"alias canonical in the same layer stays",
			[]string{"[deploy]\nruntime = \"off\"\n", "[deploy]\ngpu_runtime = \"nvidia\"\nruntime = \"off\"\n"},
			`{"deploy": {"runtime": "off", "gpu_runtime": "nvidia"}}`},
		{"stage alias un-inherit",
			[]string{"[\"stage:x\"]\n\"deploy.gpu_runtime\" = \"nvidia\"\n\"network.mode\" = \"host\"\n", "[\"stage:x\"]\n\"deploy.runtime\" = \"off\"\n"},
			`{"stage:x": {"network.mode": "host", "deploy.runtime": "off"}}`},
		{"stage table key-level merge",
			[]string{"[\"stage:x\"]\n\"network.mode\" = \"host\"\n", "[\"stage:x\"]\n\"network.ipc\" = \"host\"\n"},
			`{"stage:x": {"network.mode": "host", "network.ipc": "host"}}`},
		{"three layers",
			[]string{
				"[deploy]\ngpu_mode = \"force\"\n",
				"[environment]\nenv_1 = \"A=1\"\n[[volumes]]\nsource = \"a\"\n[deploy]\ngpu_runtime = \"auto\"\n[\"stage:x\"]\n\"deploy.gpu_runtime\" = \"nvidia\"\n\"network.mode\" = \"host\"\n",
				"volumes = []\n[environment]\n[\"stage:x\"]\n\"deploy.runtime\" = \"off\"\n[deploy]\nruntime = \"off\"\n",
			},
			`{"deploy": {"gpu_mode": "force", "runtime": "off"}, "environment": {"env_1": "A=1"}, "volumes": [], "stage:x": {"network.mode": "host", "deploy.runtime": "off"}}`},
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
		"[deploy]\ngpu_mode = \"force\"\n",
		"[environment]\nenv_1 = \"A=1\"\nenv_2 = \"B=2\"\nenv_3 = \"C=3\"\n[\"stage:x\"]\n\"network.mode\" = \"host\"\n\"network.ipc\" = \"host\"\n",
		"[environment]\nenv_4 = \"D=4\"\n[\"stage:x\"]\n\"network.pid\" = \"host\"\n",
	)
	first := resultJSON(Merge(in))
	for i := 0; i < 50; i++ {
		if got := resultJSON(Merge(in)); got != first {
			t.Fatalf("run %d differs:\n%s\n%s", i, got, first)
		}
	}
}
