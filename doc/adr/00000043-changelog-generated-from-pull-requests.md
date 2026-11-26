# changelog 從 PR 產生：分類取自標題，條目取自內文的固定段落，由 release PR 寫入

> Serves: PRD invariant 10 (documentation is derived, not duplicated) --
> changelog 條目從 PR 標題與內文推導，不再在每個 PR 另寫一份；也服務
> invariant 2 (never fail silently)：沒有條目的 PR 在 release PR 上列出，
> 不會悄悄漏掉。

- **Date:** 2026-11-26
- **Status:** Accepted
- **Relates to:** issue #2206（本決定與五個步驟；本 ADR 是步驟 1），#926
  （每個 0.Y 一個檔案、鎖定的分類），#1039（跨 RC 的 PR 條目落在錯的版本），
  #1210（union 合併的 changelog 被當成衝突），#2132（v0.43.0 正式版說明超過
  GitHub 上限），ADR-00000027（release 節奏；第 5 節的 fanout PR 內文從
  changelog 檔案取材），ADR-00000028（文件由程式推導），ADR-00000042
  （release 才跑的檢查），`ycpss91255-lab/software_factory#4`（以 PR 標籤
  分類的 release notes）、`#17`（版本與 release 規格）

維護者已在 #2206 選定方向：分類來自 PR 標題的 conventional commit 類型，
條目文字來自 PR 內文的固定段落，release 時產生。本 ADR 決定其中的四個設計
問題，並列出留給維護者的問題。狀態是 Accepted，指方向與下列建議；待決問題
回答後以修訂記錄在本檔。

## Context

### 現在的做法

- 每個 PR 手寫一條到 `doc/changelog/v0.43.md` 的 `## [Unreleased]`。
- release 由一個 bump PR 完成（例如 #2167）：改 `.version`，把
  `[Unreleased]` 改名為 `[v0.43.0-rc7] - 2026-11-25`，用
  `changelog_index.sh --write` 更新 `CHANGELOG.md` 的索引，更新 coverage
  badge。合併後在該 merge commit 打 tag。
- tag push 觸發 `self-test.yaml` 的 `release` job。它執行
  `script/release/release_notes.sh <tag>` 從 `doc/changelog/` 組出 release
  說明，用 `softprops/action-gh-release` 發布，`generate_release_notes:
  false`。正式版的說明是它自己的章節加上底下所有 `-rcN` 章節，按分類合併。
- main 的 ruleset 沒有 bypass，任何改動都要經過 PR。

### 問題

- **每個 PR 改同一段。** `.gitattributes` 的 `merge=union` 只在本機有效，
  GitHub 不採用。一個 PR 合併後，其他開著的 PR 因 changelog 衝突，要再併一次
  main、再跑一次完整 CI。
- **條目放在作者寫的地方，不是合併的地方。** 跨過 RC 的 PR，條目會落在沒有
  包含它的版本（#1039）。
- **手寫格式靠 lint 把關。** `changelog_entry.sh`（分類、700 字元上限、重複的
  條目與標題）和 `changelog-fix` 都是為手寫而存在。

### 可用的事實

- repo 只允許 merge commit，`merge_commit_title` 是 `PR_TITLE`，
  `merge_commit_message` 是 `PR_BODY`。所以 main 的 first-parent 歷史裡，每個
  merge commit 的主旨是 PR 標題加 `(#N)`，內文是合併當時的 PR 內文。從
  v0.43.0-rc1 到 2026-11-26 的 main，285 個 first-parent commit 的主旨都以
  `(#N)` 結尾。
- 同一範圍內的標題類型：`fix` 186、`docs` 26、`feat` 22、`test` 15、`ci` 11、
  `chore` 8、`refactor` 5、`perf` 4、`revert` 2，另有 6 個不是 conventional
  格式（例如 `setup:`、`readme:`、`test harness:`）。
- 同一範圍內沒有任何 commit 內文含 `## Changelog` 標題。
- tag 打在 release bump PR 的 merge commit 上（例如 `v0.43.0-rc7` 指向
  #2167 的 merge）。正式版不是最後一個 RC 的同一個 commit：`v0.42.0` 與
  `v0.42.0-rc4` 是不同的 commit，中間只有 `chore: release v0.42.0` 一個 PR。
- `release` job 的 checkout 是淺的，權限只有 `contents: write`。

### 本決定推翻的一段舊理由

`doc/changelog/CONVENTIONS.md` 與 `script/release/changelog_categories.sh`
的檔頭都寫著：不以 conventional commit 類型分類，因為那是作者的角度，而且會把
`test:`、`chore:`、`refactor:` 都塞進 changelog。本決定改以類型決定**分類**，
但**是否產生條目**由 PR 內文有沒有固定段落決定。段落是作者主動寫的，沒有段落
就沒有條目，所以 `test:` 或 `chore:` 不會因為類型而進入 changelog。這兩段文字
在步驟 5 改寫。

## Decision

### 1. 產生的內容放在哪裡：由 release PR 寫進 `doc/changelog/`

選項：

- **A. 只用於 release 說明。** tag push 時由 `release` job 產生，
  `doc/changelog/` 不再更新。
- **B. release PR 寫進 `doc/changelog/`。** 產生腳本在 release bump PR 裡執行，
  寫出 `## [vX.Y.Z...] - 日期` 章節，`release` job 照舊用 `release_notes.sh`
  讀檔。
- **C. 兩者都做。** B 之外，tag 時再產生一次並比對。

**建議 B，並加上 C 的比對作為防護。** 理由：

- release bump PR 本來就改 `doc/changelog/`，不需要新的流程，也不需要 bypass。
- 內容在打 tag 前可以在 PR 上審，需要時可直接改字。A 要到 tag 已經存在後才
  看得到結果（ADR-00000042 記錄過這種代價）。
- `release_notes.sh` 的拒絕條件（沒有章節、章節重複、沒有條目、超過 125,000
  字元）照舊有效。
- `CHANGELOG.md` 索引與 ADR-00000027 第 5 節的 fanout PR 內文都從
  `doc/changelog/` 取材，A 會讓它們失去來源。
- 一般 PR 不再改 `doc/changelog/`，同時只有一個 release PR 在改，衝突消失。

比對防護：release PR 產生後到合併前，main 可能又合併了其他 PR，這些 PR 會落在
tag 的範圍裡，卻不在章節裡。所以 tag 的 `release` job 重新算出範圍內有段落的
PR 編號，若有編號不在該 tag 的章節中就拒絕發布。比對只看 PR 編號，不比對文字，
因為文字允許在 release PR 上修改。`release` job 現在的 checkout 是淺的，比對需要
取得到上一個 tag 為止的歷史。拒絕或只警告，是待決問題 5。細節在步驟 4。

### 2. 現有工具的去留

| 項目 | 去留 | 步驟 |
|---|---|---|
| `script/release/changelog_categories.sh` | 保留並修改：分類清單不變，加入類型到分類的對應（見第 5 節）；改寫檔頭推翻舊理由的那段 | 2、5 |
| 新的產生腳本（`script/release/` 下） | 新增：從 first-parent 歷史產生一個版本的章節，並提供檢查 PR 段落的模式 | 2 |
| `script/release/release_notes.sh` | 保留，不改：仍從 `doc/changelog/` 組出 release 說明與 RC 合併 | — |
| `script/release/changelog_index.sh` | 保留，不改：release PR 照舊執行 | — |
| `script/release/justfile.release` | 修改：新增產生腳本的 recipe，與 `changelog-index` 並列 | 2 |
| `script/test/drivers/changelog_entry.sh` | 移除：它只檢查 `[Unreleased]`。700 字元上限移到 PR 段落檢查；分類清單的檢查改由產生腳本只輸出清單內的分類來保證 | 5 |
| `just test changelog-fix`（`--changelog-entry-fix`） | 移除：產生的章節每個分類只出現一次 | 5 |
| `script/test/drivers/changelog_layout.sh` | 保留並修改：系列檔、compare link、索引推導、一個 tag 一個章節仍然需要；「恰好一個檔案有 `[Unreleased]`」改為「沒有 `[Unreleased]`」 | 5 |
| `script/test/test.sh` 的 `changelog-entry` 登錄與說明 | 隨 driver 移除 | 5 |
| `.gitattributes` 的兩行 `merge=union` | 移除：只剩 release PR 寫這些檔案，union 只會把真的衝突藏起來 | 5 |
| `doc/changelog/CONVENTIONS.md` | 改寫：說明 PR 段落怎麼寫，指向對應表的位置，不再抄一份分類清單 | 3、5 |
| `.github/pull_request_template.md` | 修改：加入固定段落（見待決問題 3） | 3 |
| `.github/workflows/self-test.yaml` | 修改：`single-issue-pr` job 加一個步驟（第 3 節）；`release` job 加比對防護 | 3、4 |
| `script/ci/config_gen_paths.sh` | 修改：產生腳本若放在 `script/release/`，與其他 release 腳本一樣列入 | 2 |
| specs：`changelog_entry_lint_spec`、`changelog_layout_lint_spec`、`changelog_index_spec`、`release_notes_spec`、`gitattributes_spec`、`self_test_yaml_spec`、`justfile_spec` | 第一個隨 driver 移除；layout、gitattributes、self-test、justfile 的 spec 隨對應修改更新；index 與 release notes 的 spec 不變 | 2–5 |
| `dist/script/base/init.sh` | 不變：只替下游建立初始的 `CHANGELOG.md` | — |

`script/ci/release/archive.manifest` 不變，它只列整個 `doc/`。

release bump 目前由 harness 端的 `release-bump.sh` 執行，不在本 repo。它改為
呼叫新的 recipe，是 harness 那邊的修改，不在本 ADR 範圍。

### 3. PR 段落在哪裡檢查：`single-issue-pr` job 加一個步驟

選項：

- **A. `single-issue-pr` job。** 它在每個 pull request 都執行（沒有 `if:`，
  docs-only PR 也跑），已經透過 API 讀取當下的 PR 內文，改完內文後「Re-run
  failed jobs」就會得到新結果。在 merge group、push、手動觸發時沒有 PR，直接
  通過。
- **B. `lint-static` 的 lint 群組。** 它讀 repo 裡的檔案，沒有 PR 標題與內文，
  要另外傳進去。
- **C. `commit-attribution` job。** 它走 commit 範圍，不讀 PR 內文。

**建議 A。** 新步驟呼叫步驟 2 產生腳本的檢查模式，不是另一個工具。檢查與產生
共用同一個段落解析與同一張對應表，兩邊不會判斷不一致。檢查的內容：

1. 段落不存在，或去掉 HTML 註解與空白後是空的：通過，並印出「本 PR 不產生
   changelog 條目」。
2. 段落有內容：標題必須能對應到一個分類，否則失敗並印出標題。
3. 段落有內容：去掉多餘空白後不超過 700 字元（原 `changelog_entry.sh` 的
   上限）。
4. 段落有內容，同時又修改 `doc/changelog/` 的 `[Unreleased]`：失敗。這條只在
   過渡期有用（第 4 節），步驟 5 移除。

這個檢查不保證合併時的內容。`pull_request` 事件沒有設定 `types:`，只在開啟、
推送與重新開啟時觸發；檢查通過後再改標題或內文，不會重新檢查，修改會直接進入
merge commit。merge commit 無法再改，所以產生腳本不能因為這種 PR 永久擋住
release，處理方式見第 6 節。

job 名稱不再只描述「一個 issue」，是否改名是待決問題 4。

### 4. 現有手寫的 `[Unreleased]` 條目如何銜接：過渡版本兩者合併

選項：

- **A. 切換前先發一個版本。** `[Unreleased]` 清空後才切換，不會混用。
- **B. 過渡版本兩者合併。** 過渡後的第一個 release PR 照舊把手寫的
  `[Unreleased]` 改名為版本章節，再把產生的條目按分類併進同一個章節。
- **C. 把手寫條目改寫成已合併 PR 的段落。** 合併後改 PR 內文不會改到 merge
  commit，產生腳本讀不到。

**建議 B。** 理由：

- 不需要去重。切換前合併的 PR 內文沒有固定段落（上述範圍內為 0 個），所以
  產生腳本不會替它們產生條目；它們的條目就是手寫的那條。
- 不依賴發版時間，也處理得了切換時還開著、已經寫了 `[Unreleased]` 的 PR。
- 從步驟 3 合併起，PR 寫段落，不再寫 `[Unreleased]`。第 3 節第 4 項防止同一個
  PR 兩邊都寫。

過渡版本之後 `[Unreleased]` 是空的，步驟 5 移除它與相關規則。若維護者打算在
步驟 3 之前先發一個版本，A 也成立，兩者擇一是待決問題 6。

### 5. 類型到分類的對應，放在一處

對應放在 `script/release/changelog_categories.sh`，與分類清單同一個檔案。產生
與檢查都只透過一個函式取得一個 PR 的分類，輸入是 PR 標題。與
`software_factory#4` 對齊時（它以 PR 標籤分類），只替換這個函式與對應表，產生
腳本的其他部分不變。對齊也可能改變分類清單本身，那是對齊時的決定。

| PR 標題 | 分類 |
|---|---|
| 類型後有 `!`（例如 `feat!:`、`fix(ci)!:`） | `BREAKING` |
| `feat` | `Added` |
| `fix` | `Fixed` |
| `perf`、`refactor`、`revert`、`docs`、`test`、`ci`、`build`、`chore`、`style` | `Changed` |
| 其他類型，或不是 `type(scope): ...` 格式 | 無法對應：有段落時 PR 檢查失敗；產生腳本不拒絕，列為待處理（第 6 節） |

- BREAKING 只看標題的 `!`，不看內文的 `BREAKING CHANGE:`，來源只有一個。
- `Deprecated`、`Removed`、`Security` 無法從類型得到（待決問題 1）。
- 非使用者可見的類型對應到 `Changed`，因為有沒有條目已由段落決定（待決問題 2）。

### 6. 沒有段落的 PR，與無法自動處理的 PR

沒有段落的 PR 不產生條目。產生腳本把範圍內的 PR 分成兩份清單印在 stderr：

- **沒有條目**：沒有段落，或段落是空的。
- **待處理**：有段落，但標題無法對應分類，或段落超過 700 字元。這種 PR 是在檢查
  通過後才修改的（第 3 節）。它的條目不寫進章節。

release bump PR 的內文附上這兩份清單。審查者可以看出漏寫，並在 release PR 裡
直接加上或改寫條目。合併後改 PR 內文不會改到 merge commit，所以這是唯一的補救
位置。產生腳本只在無法判斷範圍時拒絕（第 8 節），不因單一 PR 的內容拒絕，
否則一個已合併、無法再改的 PR 會永遠擋住 release。

### 7. 條目文字的來源與格式

- 來源是 main first-parent 歷史中 merge commit 的內文，不是 GitHub API。它可以
  離線產生，結果固定，bats 可以用 fixture repo 測。代價：合併後改 PR 內文不會
  生效，以及依賴上述 repo 設定（`PR_TITLE`、`PR_BODY`）。
- 段落是 `## Changelog` 標題到下一個 `## ` 標題之間的文字（標題名稱見待決
  問題 3），去掉 HTML 註解。標題比對是完全相同的一整行：第 2 層、大小寫相同，
  fenced code block 內的不算。
- 一個 PR 一個條目：`- <段落文字> (#N)`。段落第一行是條目的開頭，其餘照
  `CONVENTIONS.md` 的格式縮排接在後面。
- 同一分類內按合併順序排列；分類按 `CHANGELOG_CATEGORIES` 的順序輸出。

### 8. 版本範圍

- 上一個 tag：從 release PR 的基準 commit（它最後合併的 main）沿 first-parent
  往回找最近的 `v*` tag，RC 也算。等同
  `git describe --tags --abbrev=0 --first-parent --match 'v[0-9]*' <base>`。
  找到的版本不低於這次的版本時拒絕。
- 範圍：`<上一個 tag>..<基準 commit>` 的 first-parent commit。上一個 release
  PR 的 merge 正是上一個 tag，所以 release PR 自己不會進入範圍。
- 範圍內有 commit 的主旨不以 `(#N)` 結尾時，不猜它屬於哪個 PR，列入第 6 節的
  待處理清單。main 的 ruleset 只允許經 PR 合併，所以正常情況不會出現。

### 9. RC

- 每個 tag，不論 RC 或正式版，都有自己的章節，範圍從上一個 tag（RC 也算）到
  這次。
- 正式版 `vX.Y.0` 的範圍是最後一個 RC 到正式版，通常沒有條目。正式版的 release
  說明照舊由 `release_notes.sh` 合併它的 RC 章節。
- 沒有 RC 的版本，例如修補版，範圍從上一個正式版開始。
- 條目落在合併後的第一個 tag，與作者何時開 PR 無關，#1039 的情形不再發生。

### 待決問題（維護者決定）

1. **`Deprecated`、`Removed`、`Security` 怎麼表達。** 選項：段落第一行可寫
   `Category: Removed` 覆蓋分類，只接受清單內的值；或從清單移除這三個，用於
   新條目時歸到 `Changed`。建議前者。現在的 `[Unreleased]` 中，#2203、#2200、
   #2186 的標題都是 `fix(...)`，卻寫在 `Changed` 下，說明作者的判斷與類型會不同，
   覆蓋也能處理這種情形。
2. **非使用者可見的類型有段落時。** 歸到 `Changed`（建議），或檢查失敗要求改
   類型。
3. **段落標題與範本。** 建議 `## Changelog`（ASCII，與 #2206 的例子相同）。
   PR 範本是否預先放這個標題與一段註解說明；預先放的空段落視為沒有段落。
4. **`single-issue-pr` 是否改名。** 改名要同步修改 `ci-rollup` 與 `release`
   的 `needs:` 及相關 spec。建議不改名，在 job 註解說明多了一個步驟。
5. **tag 時的比對防護是拒絕還是警告。** 建議拒絕，與 `release_notes.sh` 一致；
   代價是 tag 已經存在才發現（ADR-00000042 同樣的取捨）。
6. **過渡方式。** 第 4 節的 B（建議），或在步驟 3 前先發一個版本（A）。

## Consequences

- 一般 PR 不再修改 `doc/changelog/`，合併後不會讓其他 PR 因 changelog 衝突而
  再跑一次 CI。#1210 在 changelog 上的情形消失。
- 條目落在實際包含它的版本，#1039 的情形消失。
- release bump PR 多一步：執行產生腳本，審查產生的章節與沒有條目的 PR 清單。
- 忘了寫段落的 PR 不會被 CI 擋，只會出現在 release PR 的清單上。檢查通過後才
  改壞的段落也一樣，會出現在待處理清單上。
- 合併後才修改的 PR 內文不會進入 changelog，要在 release PR 上改。
- 產生腳本依賴 repo 的 merge commit 設定（`PR_TITLE`、`PR_BODY`）。設定改變
  時，所有 PR 都讀不到段落，release PR 的清單會列出範圍內所有 PR，審查者可以
  看出來。
- `Deprecated`、`Removed`、`Security` 在待決問題 1 回答前只能在 release PR 上
  手改。
- 125,000 字元的 release 說明上限仍然適用；#2132（v0.43.0 正式版過長）不因本
  決定改變。
- 與 `software_factory#4` 對齊時只替換第 5 節的函式與對應表。

## Alternatives

- **繼續手寫，修掉衝突。** GitHub 不支援自訂 merge driver，`merge=union` 在
  GitHub 上無效；衝突來自所有 PR 改同一段，不是格式問題。不採用。
- **每個 PR 一個檔案（fragment，例如 `doc/changelog/unreleased/<PR>.md`）。**
  沒有衝突，但仍是每個 PR 手寫一份，格式仍要 lint；維護者已選定從 PR 產生。
  不採用。
- **GitHub 的自動 release notes（`.github/release.yml`，以標籤分類）。** 標籤
  不是可靠的訊號（ADR-00000027 第 3 節），而且只列 PR 標題，沒有條目文字；這是
  `software_factory#4` 的方向，留到對齊時再決定。現在不採用。
- **release 時從 GitHub API 讀 PR。** 可以反映合併後的內文修改，但需要 token、
  結果會隨時間改變、測試要模擬 API。改用 merge commit 內文（第 7 節）。
- **只產生 release 說明，不寫 `doc/changelog/`。** 見第 1 節選項 A。不採用。
