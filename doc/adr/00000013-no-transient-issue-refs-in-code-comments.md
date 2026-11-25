# Strip transient issue numbers from code comments; keep ADR refs + what/why prose

> Serves: PRD invariant 2 (never fail silently) -- the issue-ref comment
> lint is one of its enforcing guards; mechanism.

- **Date:** 2026-06-24
- **Status:** Accepted
- **Relates to:** the `doc/adr/` references that this convention
  deliberately preserves

> **Amendment (base#2182, 2026-11-26): 註解只說明程式本身。** Decision 裡的
> 「**Keep** all what/why prose; only the bare issue number goes」由該節的
> 「2026-11-26 修訂」取代。其餘決定不變，`ADR-0000xxxx` 仍然保留。

## Context

The historical convention threaded inline issue numbers (`#440`,
`#216 / #429`, `#414/#448/#469`, `refs|closes|fixes #N`) into code
comments across `base` -- in `.sh`, `justfile*`, `compose.yaml`,
`Dockerfile*`, and the `#`-comments inside `.bats` setup/helper code.
The #573 review surfaced how pervasive this had become and how little it
buys: an inline `#N` is a frozen pointer to a transient artifact. The
issue gets closed, renumbered across a repo move, or superseded, and the
comment now points at stale context while still costing a reader the
mental "go look that up" tax on every pass.

There is a more reliable traceability chain that does not rot:
`git blame -> commit -> PR -> issue`. blame is recomputed against the
live tree on every read, so it never goes stale the way a hard-coded `#N`
does. The comment's job is to say *what* the code does and *why*; the
*which-ticket* dimension is recoverable from history when (rarely) needed.

ADR references are the opposite case. `ADR-0000xxxx` is durable, curated
rationale that we maintain deliberately; an inline ADR anchor is exactly
what makes future code-tracing cheap, so keeping it offsets the cost this
convention otherwise introduces.

## Decision

Code comments in `base`'s shipped code do **not** carry transient issue
numbers. Specifically, in `.sh`, `justfile*`, `compose.yaml`,
`Dockerfile*`, and the `#`-comments of `.bats` files:

- **Strip** inline transient refs from comment text: bare `#NNN`,
  `(#NNN)`, `refs|closes|fixes #NNN`, marker forms
  (`# -- #216 / #429: auto-build gate --` -> `# -- auto-build gate --`),
  and rationale forms (`# #546: the root user entry ...` ->
  `# the root user entry ...` -- drop the number, keep the sentence).
  Collapse separators / double spaces the removal leaves behind.
- **Keep** `ADR-0000xxxx` references anywhere they appear.
- **Keep** all what/why prose; only the bare issue number goes.

The following are explicitly **not** issue references and are left
untouched:

- `@test "..."` description strings -- these are test identities mirrored
  in `TEST.md`; a `(#NNN)` inside a `@test` name is part of the test's
  name, not a comment, and rewriting it would churn `TEST.md` for no
  gain.
- Functional string literals, registered log-event names, hadolint /
  shellcheck directive codes (`DL3007`, `SC1090` -- not issue refs),
  version tags (`v0.41.0`), and URLs.
- Issue references inside non-comment code (e.g. a `#NNN` inside a
  `printf`/`_log_*` string the program emits at runtime).

A lint driver (`script/test/drivers/issueref.sh`, wired into `just test`
and `just test lint`) enforces this so the refs cannot creep back in.

### 2026-11-26 修訂（base#2182）：註解只說明程式本身

原本的決定只刪編號，其他文字一律保留，歷史敘述與長篇說明因此留在註解裡。
在 main `540dd34c`，註解有 87,097 行，占程式檔的 34%；其中 7,036 段超過兩行，
超出的部分有 48,632 行。自本修訂起，所有程式檔的註解適用下列規則：

1. 註解只說明程式本身：這段程式做什麼、有什麼不明顯的前提或限制。以重點
   敘述，一兩行為原則。
2. 修改的情境不寫在註解：為什麼改、以前怎麼寫、哪個 issue 或事故、討論過程。
   這些屬於 commit 訊息，或 issue 與 PR。
3. issue 與 PR 的編號不寫在註解，包括帶 repo 前綴的（`base#1234`）與句尾單純的
   編號。
4. 長篇說明濃縮成重點。被拿掉的背景若只存在於註解，整理後以留言貼回原本的
   issue 或 PR；那邊已有完整記載就不重貼，在 PR 說明即可。
5. `.bats` 的 `# why:` 保留，內容只寫這個測試現在在保護什麼，不寫歷史與編號，
   以一行為原則。
6. 給工具讀的註解不動：`shellcheck`、`hadolint`、bats 標籤、`tool-pin:`、各 lint
   的 allow 標記、當作 `--help` 輸出的檔頭、`just --list` 的食譜說明，以及 spec
   逐字比對的註解。

上面「not issue references」列出的例外（`@test` 名稱、字串、版本號、URL）仍然
適用。這份標準不加 lint，由 review 把關；`issueref` 維持原樣，只擋沒有前綴的
`#NNN`。既有的註解由 base#2182 分批處理。

## Out of scope

Issue references stay in commit messages, PR bodies, `CHANGELOG`,
`doc/adr/` prose (including this ADR), and the gh-artifact-format docs --
those artifacts are *about* the tickets and the references are
intentional there. Downstream repos' own comments are handled separately;
base comments propagate into `.base/` via the subtree and ride along with
the upgrade / fanout.

## Consequences

- Tracing a comment back to its originating ticket now costs one extra
  hop (`git blame` the line -> read the commit / PR -> follow to the
  issue) instead of reading an inline `#N`. This is the accepted
  tradeoff: blame does not go stale, inline numbers do, and the everyday
  reader -- who is reading *what/why*, not *which ticket* -- pays nothing.
- Comments are shorter and read as specifications of behaviour rather
  than as change-logs.
- The `issueref` lint makes the convention enforceable rather than
  aspirational; a reintroduced `#N` in a comment fails `just test`.
- 2026-11-26 修訂之後，「為什麼這樣改」只能由 `git blame` 找到 commit 與 PR，
  所以 commit 訊息要寫清楚拿掉什麼、改了什麼與原因。
- 2026-11-26 修訂沒有 lint，違反的註解只能在 review 發現；既有註解處理完之前，
  新舊寫法並存。

## Alternatives considered

- **Keep inline `#N` for traceability.** Rejected: the inline pointer
  rots (close / rename / supersede) while `git blame` does not, so the
  "traceability" it offers is the unreliable half of the pair.
- **Strip everything, including ADR refs.** Rejected: ADR anchors are
  durable curated rationale, not transient tickets; the inline anchor is
  the cheap-tracing affordance worth keeping.
- **Convention without a lint.** Rejected: an unenforced style convention
  silently regresses; the lint is what makes the acceptance criterion
  hold over time.
- **（2026-11-26 修訂）只刪歷史，保留長篇說明。** 否決：base#2183 的第一版照此
  處理三個檔案，345 行註解只減到 316 行，長篇說明都還在。
- **（2026-11-26 修訂）保留帶前綴的編號（`base#1234`）。** 否決：編號的讀者在
  issue 與 PR，`git blame` 找得到；留在句尾和沒有前綴的編號一樣會過期。
- **（2026-11-26 修訂）加 lint 限制行數或擋歷史敘述。** 否決：維護者認為 repo 的
  測試工具與檢查程式已經太多；是不是歷史也無法靠字面判斷，以關鍵字比對命中的
  行只有 31% 是歷史（base#2182 的抽樣）。
