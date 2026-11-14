# Independent review, second pass: Codex `gpt-6-astra`, 2026-11-15

Same reviewer and instructions as the first pass, on commit `7a0fb70` (after the
first round of fixes); it read the earlier review only after its own. All 14 new
findings were verified and fixed in the commit that added this file.

Reviewed commit `7a0fb70`, including every requested source file. Read the earlier review only afterward. No files changed. Validation used syntax checks and in-memory reproductions; no live pastes or agent runs.

1. **High — Browser requests still identify the wrong destination.** [native-host.py:45](native-host.py:45), [polish:75](polish:75), [background.js:59](browser-extension/background.js:59).  
   Switching to another browser window during selection extraction/native-host startup makes that window the destination. Worse, `file:` URLs become empty at native-host.py:38, bypassing the browser-class check entirely; switching to a terminal can then authorize a paste there. **Fix:** carry originating tab/frame identity and validate the destination selection through the extension; independently mark browser-originated requests and fail closed when identity is unavailable.

2. **High — Focus verification does not bind subsequent keystrokes to that window.** [apply.sh:109](apply.sh:109), [apply.sh:86](apply.sh:86).  
   Paste uses global `wtype` after checking focus; another window gaining focus between those operations receives the paste. Undo’s fallback explicitly waits another 600 ms before sending an unaddressed Ctrl+Z. **Fix:** use window-addressed dispatch with exact modifiers for every operation; remove the unverified global fallback.

3. **High — Locks serialize writes, but do not preserve their order.** [shell.qml:59](shell.qml:59), [shell.qml:876](shell.qml:876), [shell.qml:883](shell.qml:883).  
   Every mutation starts a detached process. An older settings snapshot can acquire the lock after a newer snapshot and overwrite it; likewise, an already-requested history append can run after Clear and resurrect an entry. **Fix:** use one ordered writer queue for settings/history operations, and acknowledge completion before reporting persistence.

4. **High — Edited text and reply drafts are still silently truncated.** [rewrite.sh:54](rewrite.sh:54), [rewrite.sh:198](rewrite.sh:198).  
   The launcher rejects oversized selections, but Refine/regeneration silently cuts edited sources and drafts at 20,000 characters. A long Detailed result or pasted draft loses its final decisions before reaching the agent. **Fix:** validate these inputs explicitly and refuse oversized generations without discarding the text, or process them completely.

5. **Medium — Large results can disappear when Copy/Apply closes the popup.** [shell.qml:934](shell.qml:934), [shell.qml:941](shell.qml:941), [shell.qml:879](shell.qml:879).  
   Results and history entries travel as single command-line arguments, while the editor has no size limit. A 140,000-byte edit exceeds Linux’s per-argument limit: launching the copy/apply and history writers fails, but the popup still closes; I reproduced `E2BIG` with an equivalent Unicode payload. **Fix:** pass content through stdin/private files and close only after confirmed success.

6. **Medium — Private content is exposed through process arguments.** [shell.qml:934](shell.qml:934), [shell.qml:879](shell.qml:879), [rewrite.sh:237](rewrite.sh:237).  
   Applied text, originals, history entries, and Claude system prompts containing pins/drafts appear in argv. On systems with normally readable `/proc` process arguments, another local account can observe them despite the private file permissions. **Fix:** transport sensitive payloads through stdin or private file descriptors.

7. **Medium — Visiting History during pin editing can delete the pin.** [shell.qml:885](shell.qml:885), [shell.qml:786](shell.qml:786), [shell.qml:378](shell.qml:378).  
   Edit a pin → Alt+H → Back → Adjust → Cancel. History leaves `editingPin` active; reopening Adjust replaces its text with the ordinary note, and Cancel saves that replacement or deletes the pin when empty. This sequence reproduced in memory. **Fix:** finish/cancel pin editing before every view transition, retaining both owning mode and tone.

8. **Medium — Failed Undo attempts permanently consume Undo.** [apply.sh:69](apply.sh:69).  
   The state becomes `undone=true` before focus or key dispatch succeeds. If focus temporarily fails, or both dispatch methods fail, a later retry says “Already undone” although nothing was undone. **Fix:** keep the transaction locked, but mark completion only after successful dispatch or an explicitly completed recovery action.

9. **Medium — Reply’s Paste can replace the selected message.** [apply.sh:110](apply.sh:110), [shell.qml:934](shell.qml:934).  
   Select text inside an editable field, open Reply, then Paste: only Insert collapses the selection, so Reply sends Ctrl+V over the still-selected text. Unlike Replace, it also supplies no original for clipboard recovery. **Fix:** define and validate a reply insertion destination; at minimum, collapse the selection deliberately and retain recovery text.

10. **Medium — Postprocessing corrupts legitimate markup.** [rewrite.sh:303](rewrite.sh:303).  
    Wrapper stripping runs unconditionally. An otherwise correct result `<text>keep this SVG text element</text>` becomes `keep this SVG text element`; this reproduced without an agent. **Fix:** preserve literal output rather than guessing that matching boundary tags are wrappers.

11. **Medium — Original selections remain on disk independently of History.** [polish:44](polish:44), [shell.qml:913](shell.qml:913).  
    Successful launches leave `input-*.txt` behind after closing, even with History disabled or cleared. Cleanup happens only on a subsequent launch after 24 hours; the persistent cache fallback can retain selections indefinitely if Polish is not reopened. **Fix:** clean request files when the popup and its jobs finish, retaining the age sweep only for crash recovery.

12. **Medium — Changing agents can change an older translation’s language.** [shell.qml:434](shell.qml:434), [shell.qml:516](shell.qml:516).  
    Translate into English, then Hindi, return to the English version and change agents. `setAgent()` omits `c.lang`, so the new version uses the saved Hindi preference; reproduced through the extracted functions. **Fix:** carry the current version’s language when regenerating with another agent.

13. **Medium — Tweet enforcement and its displayed counter disagree.** [rewrite.sh:280](rewrite.sh:280), [shell.qml:1595](shell.qml:1595).  
    Bash counts Unicode code points while the UI counts UTF-16 units: 150 emoji pass the backend as 150 but display as 300. The backend also measures whitespace-trimmed text while returning the untrimmed result. **Fix:** use one consistent, platform-appropriate counting rule on the exact final text for validation, retries and display.

14. **Low — Installation generates invalid JSON for valid checkout paths.** [install.sh:15](install.sh:15).  
    A checkout directory containing `"` or a backslash is interpolated into JSON without escaping, breaking native-host registration. **Fix:** generate the manifest with `jq --arg` or a JSON serializer.

### Earlier findings

Statuses refer to the numbered findings in [the earlier review](docs/reviews/2026-11-14-codex-gpt-6-astra.md).

| # | Earlier issue | Current status and evidence |
|---|---|---|
| 1 | Paste after focus failure | **Fixed for explicit failure:** [apply.sh:104](apply.sh:104) aborts. The later focus race remains finding 2 above. |
| 2 | Original selections truncated | **Fixed:** [polish:59](polish:59) counts characters and rejects oversized originals. Edited-source truncation remains finding 4. |
| 3 | Settings/history write races | **Partly fixed:** unique temporary files and locks prevent collisions, but detached writers remain unordered at [shell.qml:59](shell.qml:59) and [shell.qml:878](shell.qml:878). |
| 4 | Wrong browser source window | **Partly fixed:** [polish:75](polish:75) rejects some non-browser targets; [native-host.py:45](native-host.py:45) still samples the active window without origin identity. |
| 5 | Shared Codex output files | **Fixed:** [rewrite.sh:249](rewrite.sh:249) allocates a unique output; [rewrite.sh:38](rewrite.sh:38) registers cleanup. |
| 6 | Concurrent launches share input | **Fixed for the reported race:** launch locking at [polish:39](polish:39), unique inputs at [polish:45](polish:45), and startup polling at [polish:108](polish:108). |
| 7 | Shared `/tmp` symlink attacks | **Fixed:** ownership/symlink checks and private fallback at [lib.sh:6](lib.sh:6), mirrored at [native-host.py:65](native-host.py:65). |
| 8 | Concurrent Undo executes twice | **Fixed:** [apply.sh:58](apply.sh:58) locks apply/undo transactions. Premature consumption remains finding 8 above. |
| 9 | Public state-file permissions | **Fixed through normal launch:** [lib.sh:17](lib.sh:17) repairs permissions; [polish:104](polish:104) sets a private umask. |
| 10 | Standard replies discard adjustments | **Fixed:** [rewrite.sh:136](rewrite.sh:136) selects Standard before appending adjustments. |
| 11 | Read analyzes edited Rewrite | **Fixed:** [shell.qml:488](shell.qml:488) permits alternate sources only in Rewrite. |
| 12 | Reply draft lost after one restyle | **Fixed:** [shell.qml:502](shell.qml:502) carries forward `c.draft`. |
| 13 | Prefetch ignores changed instructions | **Fixed:** [shell.qml:626](shell.qml:626) includes pins/custom definitions in cache matching. |
| 14 | Pin edits lost or misapplied | **Partly fixed:** Settings/tone transitions finish edits, but [shell.qml:885](shell.qml:885) leaves History transitions unprotected. |
| 15 | Ctrl+Enter applies hidden History result | **Fixed:** [shell.qml:1300](shell.qml:1300) restricts the shortcut to Main/Adjust/Tone. |
| 16 | Undo uses first keyboard layout | **Fixed for the reported case:** [apply.sh:45](apply.sh:45) reads the active keymap and matches its layout row. |
| 17 | Tweet silently exceeds limit | **Partly fixed:** [rewrite.sh:283](rewrite.sh:283) emits a final warning, but inconsistent counting misses cases described above. |
| 18 | Rejected browser requests leak files | **Fixed for normal rejection paths:** [polish:33](polish:33) cleans handoff files on lock/singleton rejection. Accepted input-file retention is finding 11. |

The “all 18 … fixed” claim at [FEATURES.md:247](FEATURES.md:247) is therefore inaccurate.

**Five most important fixes**

1. Bind paste/undo to verified destinations with exact modifiers.
2. Serialize settings and history operations in request order.
3. Eliminate silent truncation and argv-based text transport.
4. Complete pin edits on every view/mode transition.
5. Consume Undo only after successful execution.