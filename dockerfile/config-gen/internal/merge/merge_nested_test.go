package merge

import "testing"

// A table nested in a table merges key by key too, at every depth
// (base#1855); the stage sub-table is the schema's nested table.
func TestMergeNestedTables(t *testing.T) {
	got := resultJSON(Merge(layers(t,
		"[\"stage:x\".network]\nmode = \"host\"\n",
		"[\"stage:x\".network]\nipc = \"host\"\n",
	)))
	want := `{"stage:x": {"network": {"mode": "host", "ipc": "host"}}}`
	if got != want {
		t.Errorf("got  %s\nwant %s", got, want)
	}
}
