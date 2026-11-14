# Independent review: Codex `gpt-6-astra`, 2026-11-14

Adversarial, read-only review of commit `554dc97`, run with
`codex exec -m gpt-6-astra -c model_reasoning_effort=high --sandbox read-only`.
Every finding was checked against the code and all 18 were fixed in the commit
that added this file (#3 Read-on-edited-rewrite was judged a bug; the useful idea
behind it is on the FEATURES.md roadmap).

1. **High — Paste proceeds after focus failure.** [apply.sh:73](apply.sh:73), [apply.sh:24](apply.sh:24). Closing the source window before clicking Replace still sends Ctrl+V to whichever window receives focus. Additionally, `focus()` returns the successful `sleep` status even when both focus dispatches fail; clipboard and paste failures also produce a success toast and undo record. **Fix:** abort on clipboard/focus failure, verify the active window before sending keys, and record undo only after successful dispatch.

2. **High — Long selections are silently shortened before replacing the entire selection.** [polish:44](polish:44). Selecting 30 KB rewrites only the first 20 KB, but Replace overwrites all 30 KB; even “Original” and the clipboard recovery contain only the truncated prefix. The byte cutoff can also split a UTF-8 character, which I reproduced. **Fix:** retain the complete original and reject oversized input explicitly, or process it completely; truncate previews only.

3. **High — Settings and history writes race and can corrupt or resurrect data.** [shell.qml:58](shell.qml:58), [shell.qml:861](shell.qml:861), [shell.qml:865](shell.qml:865). Every change launches an independent writer using the same `.tmp` filename. Rapid setting changes can overwrite newer settings or interleave writes; history append/rotation can lose entries, and a pending rotation can restore history after Clear. **Fix:** serialize writes and clearing through one writer, with locking and unique temporary files followed by atomic replacement.

4. **High — Browser requests can capture the wrong source window.** [background.js:59](browser-extension/background.js:59), [polish:46](polish:46). The extension awaits selection extraction and native-host startup before the launcher samples `activewindow`; no originating tab/frame identity reaches the apply path. Switching applications during that interval makes Replace target the other application. **Fix:** preserve browser target identity and apply through the originating tab/frame with selection validation; abort when that target cannot be verified.

5. **High — Concurrent Codex generations share their result file.** [rewrite.sh:236](rewrite.sh:236). Pressing Ctrl+R while a Codex generation of the same style is running starts another job that removes and writes the same `codex-$style.txt`. Jobs can read another generation’s answer or an empty/partial file; all custom tones also share `codex-custom.txt`. **Fix:** allocate a unique result and error file per invocation and clean them up with a trap.

6. **High — The singleton check is not atomic; simultaneous launches share input.** [polish:16](polish:16), [polish:30](polish:30). Two launches before Quickshell appears both pass `pgrep` and overwrite the same `input.txt` and `.tmp`. A popup can therefore rewrite another request’s text while retaining its own target window. **Fix:** acquire an exclusive lock before capturing input and hold it for the popup’s lifetime; use a unique request directory.

7. **High — The `/tmp` fallback permits precreated-directory/symlink attacks.** [polish:29](polish:29), [apply.sh:11](apply.sh:11), [rewrite.sh:202](rewrite.sh:202). When `XDG_RUNTIME_DIR` is unset, another local user can precreate writable `/tmp/text-polish` and plant symlinks for predictable filenames. `mkdir -p -m 700` does not secure an existing directory, so subsequent redirects can overwrite files accessible to the victim. **Fix:** require a validated private runtime directory or create a securely owned per-user fallback and reject unexpected ownership, permissions, or symlinks.

8. **Medium — Undo’s “once only” protection races.** [apply.sh:35](apply.sh:35). Two rapid Undo invocations can both read `undone=false` before either updates it and then send two Ctrl+Z events, undoing unrelated earlier work. Both also use the same state temporary file. **Fix:** lock the complete undo transaction, including state validation, dispatch, and update; coordinate apply-state writes through the same lock.

9. **Medium — History and settings lack private permissions.** [shell.qml:58](shell.qml:58), [shell.qml:862](shell.qml:862). With umask `022` and traversable parent directories, the writers create readable directories/files containing selected text, replies, pins, and writing samples. Other local accounts can read them. **Fix:** create state directories with mode `0700` and files with `0600`, including temporary files, and repair existing permissions.

10. **Medium — Standard replies discard pins, Refine requests, and adjustments.** [rewrite.sh:178](rewrite.sh:178). Length, emoji, and user requests are appended to `task` earlier, then the Reply/Proofread branch replaces that entire variable. Consequently, refining a Standard reply with “decline politely” never sends that instruction to the agent; I confirmed the missing request in the constructed prompt. **Fix:** select the Standard base style before appending adjustments and pins.

11. **Medium — Switching to Read can analyze an edited rewrite instead of the original.** [shell.qml:481](shell.qml:481), [shell.qml:677](shell.qml:677). Edit a Rewrite result, then enter Read for the first time: `baseSource()` permits Read and obtains the previous rewrite’s edited text. Summarize/Translate consequently operate on that text despite the documented original-source behavior. **Fix:** return an alternate source only when the destination mode is Rewrite.

12. **Medium — Reply drafts survive only one restyle.** [shell.qml:490](shell.qml:490). Edit a reply to include a decision, choose another tone, then choose a third tone. The intermediate result has `edited=false`, so `replyDraft()` returns empty even though that version stores the original draft; the third generation loses the user’s decision. **Fix:** carry forward `c.draft` when the current reply has no newer hand edit.

13. **Medium — Prefetched results ignore changed instructions.** [shell.qml:612](shell.qml:612). Enable Prepare next tone, let it prepare Tweet, then add a Tweet pin through Adjust and cancel before selecting Tweet. The cache matches only style, mode, agent, and source, so it returns the answer generated without the pin; custom-tone edits have the same problem. **Fix:** include effective pins and custom-tone configuration in the cache identity or invalidate affected entries when they change.

14. **Medium — Pin editing can discard edits or modify another tone’s pin.** [shell.qml:366](shell.qml:366), [shell.qml:762](shell.qml:762). Clicking another pin overwrites unsaved editor text. More seriously, leaving a pin edit through Settings retains `editingPin`; subsequently opening Adjust for another tone and cancelling can update or delete that tone’s pin at the stale index. **Fix:** finish or explicitly cancel pin editing before every pin, tone, mode, or view transition, and retain the edited pin’s owning tone independently.

15. **Medium — Ctrl+Enter in History can replace text using a hidden result.** [shell.qml:1284](shell.qml:1284). Open History from a completed editable Rewrite and press Ctrl+Enter while searching: the shortcut remains enabled and falls through to `apply("replace")` for the hidden current version. **Fix:** explicitly restrict apply/copy shortcuts to Main, with separate handlers for Adjust and the tone editor.

16. **Medium — Undo resolves Z using the first configured layout, not the active layout.** [apply.sh:55](apply.sh:55). With layouts such as `us,fr` and French active, `cut -d, -f1` selects US and computes the wrong physical keycode. Undo can send another Ctrl shortcut instead. **Fix:** resolve the active layout and variant, including any modifiers required to produce Z.

17. **Medium — Tweet can return an over-limit result as successful.** [rewrite.sh:266](rewrite.sh:266), [rewrite.sh:280](rewrite.sh:280). If the initial answer and both retries exceed 280 characters, the final result still emits `F`/`OK`; there is no final length rejection. This contradicts the claim that Tweet produces a fitting post. **Fix:** validate after the last attempt and surface an explicit over-limit result instead of success.

18. **Low — Rejected browser requests leak selection files.** [native-host.py:37](native-host.py:37), [polish:16](polish:16). Using a browser menu while a popup is already open creates `browser-*.txt`, but the launcher exits before consuming or deleting it. Repeated attempts retain selected text and accumulate files until runtime cleanup. **Fix:** give the host responsibility for cleanup after launcher acknowledgement, including rejected launches and startup failures.

The five most important fixes are:

1. Verify the originating target and abort failed paste operations.
2. Stop silently truncating text that Replace will overwrite.
3. Serialize settings, history, and undo transactions.
4. Isolate launcher inputs and agent outputs per request.
5. Secure runtime and persistent-state directories and files.