// Package merge folds the decoded setup.toml layers into one tree by the
// rules of ADR-37 sec. Merge semantics (base#1855), the rules
// toml_bridge.py's _merge_toml applies.
package merge

import (
	"strings"

	"github.com/ycpss91255-lab/base/dockerfile/config-gen/internal/load"
	"github.com/ycpss91255-lab/base/dockerfile/config-gen/internal/schema"
)

// Result is the merged layers: the table tree and the arrays it keeps,
// laid out as one layer's schema.Config lays them out.
type Result struct {
	Tree     schema.Tree
	Deferred []schema.Deferred
}

// aliases are the deprecated spellings _LEGACY_ALIASES lists: a table
// whose name is Table (or starts with it when it ends in ":"), the
// canonical key and the legacy key.
var aliases = []struct{ table, canonical, legacy string }{
	{"deploy", "gpu_runtime", "runtime"},
	{"stage:", "deploy.gpu_runtime", "deploy.runtime"},
}

// entry is one child of a merged table: a table, a scalar or an array.
type entry struct {
	key  string
	kind schema.ChildKind
	row  schema.Field
	def  schema.Deferred
	node *table
}

// table is one merged table; meta carries its Path, Text, Line, Implicit
// and Inline from the layer that created it.
type table struct {
	meta    schema.Node
	entries []*entry
}

func (t *table) find(key string) int {
	for i, e := range t.entries {
		if e.key == key {
			return i
		}
	}
	return -1
}

// Merge folds layers, lowest precedence first, into one Result. A table
// present on both sides merges key by key at every depth; any other value,
// an array included, is replaced whole by the higher layer, in the place
// the lower layer gave its key. A layer that spells only the legacy key of
// an alias pair drops the canonical key it would inherit.
func Merge(layers []load.Layer) Result {
	root := &table{}
	for _, l := range layers {
		cfg := l.Config
		for _, c := range cfg.Tree.Nodes[0].Children {
			if c.Kind != schema.ChildNode {
				put(root, toEntry(cfg, c))
				continue
			}
			i := root.find(c.Key)
			if i < 0 || root.entries[i].kind != schema.ChildNode {
				put(root, &entry{key: c.Key, kind: schema.ChildNode, node: &table{meta: cfg.Tree.Nodes[c.Node]}})
				i = root.find(c.Key)
			}
			dst := root.entries[i].node
			layer := cfg.Tree.Nodes[c.Node]
			for _, a := range aliases {
				applies := a.table == c.Key || strings.HasSuffix(a.table, ":") && strings.HasPrefix(c.Key, a.table)
				if applies && hasKey(layer, a.legacy) && !hasKey(layer, a.canonical) {
					dst.drop(a.canonical)
				}
			}
			mergeInto(dst, cfg, c.Node)
		}
	}
	var out Result
	emit(&out, root)
	return out
}

func hasKey(n schema.Node, key string) bool {
	for _, c := range n.Children {
		if c.Key == key {
			return true
		}
	}
	return false
}

func (t *table) drop(key string) {
	if i := t.find(key); i >= 0 {
		t.entries = append(t.entries[:i], t.entries[i+1:]...)
	}
}

// put replaces the entry with e's key in place, or appends e.
func put(t *table, e *entry) {
	if i := t.find(e.key); i >= 0 {
		t.entries[i] = e
		return
	}
	t.entries = append(t.entries, e)
}

// mergeInto merges the children of cfg's node idx into dst.
func mergeInto(dst *table, cfg *schema.Config, idx int) {
	for _, c := range cfg.Tree.Nodes[idx].Children {
		if i := dst.find(c.Key); i >= 0 && c.Kind == schema.ChildNode && dst.entries[i].kind == schema.ChildNode {
			mergeInto(dst.entries[i].node, cfg, c.Node)
			continue
		}
		put(dst, toEntry(cfg, c))
	}
}

// toEntry copies child c of cfg, a table with its whole subtree.
func toEntry(cfg *schema.Config, c schema.Child) *entry {
	e := &entry{key: c.Key, kind: c.Kind}
	switch c.Kind {
	case schema.ChildRow:
		e.row = c.Row
	case schema.ChildDeferred:
		e.def = cfg.Deferred[c.Defer]
	case schema.ChildNode:
		e.node = &table{meta: cfg.Tree.Nodes[c.Node]}
		mergeInto(e.node, cfg, c.Node)
	}
	return e
}

// emit appends t and what it holds to out in depth-first order, each
// table before its children, and returns t's node index.
func emit(out *Result, t *table) int {
	i := len(out.Tree.Nodes)
	n := t.meta
	n.Children = nil
	out.Tree.Nodes = append(out.Tree.Nodes, n)
	var children []schema.Child
	for _, e := range t.entries {
		c := schema.Child{Kind: e.kind, Key: e.key}
		switch e.kind {
		case schema.ChildRow:
			c.Row = e.row
		case schema.ChildDeferred:
			c.Defer = len(out.Deferred)
			out.Deferred = append(out.Deferred, e.def)
		case schema.ChildNode:
			c.Node = emit(out, e.node)
		}
		children = append(children, c)
	}
	out.Tree.Nodes[i].Children = children
	return i
}
