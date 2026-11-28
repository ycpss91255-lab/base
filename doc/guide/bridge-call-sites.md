# Bridge call sites

`toml_bridge_parse` / `toml_bridge_merge` 的每個呼叫點，與取代它的 Go
`config-gen` 指令及 slice issue 的對照（base#1939，屬於 base#1395 /
[ADR-00000039](../adr/00000039-config-generator-in-go.md)）。

`test/bats/unit/bridge_call_sites_spec.bats` 掃描 `dist/script/docker/lib/`
下非註解行、非 `toml_bridge.sh` 內的呼叫，與下表第一欄的 `file:line` 逐項比對：
漏列、行號過期、同一 `file:line` 重複列都會讓 spec 失敗。slice 完成後由該 slice
更新本表。`file:line` 的路徑相對於 `dist/script/docker/lib/`。

`config-gen` 指令尚未存在時寫 `none yet`，狀態寫 `open`。

| file:line | 呼叫 | config-gen 指令 | slice | 狀態 |
|---|---|---|---|---|
| `conf.sh:189` | `toml_bridge_parse --kv` | none yet | S10a #1870 | open |
| `conf.sh:600` | `toml_bridge_merge --kv` | none yet | S10a #1870 | open |
| `conf.sh:2234` | `toml_bridge_parse --kv` | none yet | S13c #1883 | open |
| `conf.sh:2251` | `toml_bridge_parse --kv` | none yet | S13c #1883 | open |
| `conf.sh:2356` | `toml_bridge_parse --kv` | none yet | S13c #1883 | open |
| `setup_conf.sh:338` | `toml_bridge_parse --empty-arrays` | none yet | S10c #1872 | open |
| `setup_cmd.sh:164` | `toml_bridge_parse --empty-families` | none yet | S10b #1871 | open |
| `config_summary.sh:267` | `toml_bridge_parse --entries` | none yet | S13a #1881 | open |
| `dockerfile_migrate.sh:594` | `toml_bridge_parse --kv` | none yet | S13b #1882 | open |
| `ini_to_toml_migrate.sh:218` | `toml_bridge_parse --kv` | none yet | S16 #1452 | open |
