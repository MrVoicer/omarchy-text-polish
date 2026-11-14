# Feature and readiness review — Codex gpt-6-astra (2026-11-15)

Asked for new feature ideas, independently (not told our backlog), read-only,
at commit `dc94407`. Reproduced verbatim below.

**Follow-up (same day):** verified and fixed the concrete issues it raised:
- `apply.sh` put the original text on jq's command line for the undo state;
  now built from the request file.
- Command Code was detected as `commandcode` but run as `cmd`; both now use
  `commandcode`.
- Punchy dropped meaning-changing qualifiers and Concise could drop facts for
  length; prompts now say meaning beats style.
- FEATURES.md/README claims narrowed ("told never to invent", window-level
  targeting, provider still sees text, prompt injection "should", per-agent
  restrictions, History keeps results on close, which is intentional).
- Still open: LICENSE, a complete installer (all bindings, optional Right Alt,
  dependency checks). Feature picks are tracked in FEATURES.md's roadmap.

---

**Polish should compete on control and trust: improve this text, preserve what matters, and return it reliably to the right place.** More tones would add little.

The competitive baseline is already high: [Apple offers proofreading, rewriting and summaries](https://support.apple.com/en-mt/guide/iphone/iph6f08da1d2/ios), [Grammarly offers personalized voice](https://support.grammarly.com/hc/en-us/articles/23153676821773-View-and-customize-your-voice-profile), and Raycast supports both [selection-replacing AI commands](https://manual.raycast.com/ai/ai-commands) and [existing AI subscriptions](https://www.raycast.com/core-features/ai). “Your own subscription” is useful positioning, but insufficient differentiation alone. Against a ChatGPT tab, Polish’s opportunity is eliminating the copy–prompt–compare–paste workflow.

I read the requested docs and implementation paths. This is a static assessment; I made no changes or live agent calls.

**17 feature ideas**

Effort: **S** = contained change; **M** = multiple components or substantial interaction work; **L** = new integration boundary. Proposed shortcuts are illustrative. A searchable **Ctrl+K action menu** could expose occasional actions without expanding the tone row.

1. **Accept individual changes — keep the useful corrections and reject the rest.**
   - **Who/moment:** Someone proofreading an email likes the grammar fixes but dislikes one rewritten sentence.
   - **Fit:** Extend Rewrite’s Changes view in `shell.qml` with structured edit hunks; next/previous change, accept/reject, then normal Replace.
   - **Effort/risk:** **M.** No new compositor dependency; difficult cases are overlapping edits and maintaining offsets after hand editing.
   - **Rules:** Compatible. Actions appear only in Changes; no additional toggle or tone.

2. **Protect exact wording — freeze names, quotations, code or contractual phrases.**
   - **Who/moment:** A developer wants prose improved without changing an API identifier; a salesperson must preserve approved wording.
   - **Fit:** In Original, select a span → Ctrl+K → Protect. `shell.qml` records ranges; `rewrite.sh` substitutes and validates opaque placeholders before restoring text.
   - **Effort/risk:** **M.** Operates inside the popup; Unicode offsets and lost or duplicated placeholders require careful handling.
   - **Rules:** Compatible **only when protection comes from Polish’s controls**, never syntax embedded in selected text.

3. **Critical-detail check — flag changed numbers, URLs and protected terms.**
   - **Who/moment:** Before sending a polished quote, deadline or technical explanation.
   - **Fit:** Deterministic source/output comparison after Rewrite; a compact warning opens the relevant Changes hunks. Start with literal differences, not claims of semantic fact-checking.
   - **Effort/risk:** **M.** No new Wayland dependency; legitimate reformatting and unit conversions can create false positives.
   - **Rules:** Compatible. Keep explanations outside generated text; do not add an automatic second agent run.

4. **Fill reply blanks — turn `[time]` and `[price]` into a completion flow.**
   - **Who/moment:** A user has a good reply but must supply two missing details.
   - **Fit:** Reply detects candidate placeholders; an action jumps between them with Tab. Paste highlights unresolved fields before proceeding.
   - **Effort/risk:** **S.** Internal QML work; distinguish placeholders from ordinary bracketed prose. Existing paste-target limitations remain.
   - **Rules:** Compatible. The supplied values are user input, not inferred commitments.

5. **Exact output budgets — fit a form without repeated “shorter” requests.**
   - **Who/moment:** Filling a 500-character application field or writing a 100-word abstract.
   - **Fit:** Adjust → optional word/character maximum; live counter in the existing footer; `rewrite.sh` validates the result and offers a shortening retry.
   - **Effort/risk:** **S.** No new compositor work; define counting precisely, especially emoji and platform-specific limits.
   - **Rules:** Compatible. Explicit retries reveal their extra run; do not create another tone.

6. **Personal terminology — preserve the vocabulary that generic assistants keep “fixing.”**
   - **Who/moment:** People using product names, specialist terms, regional English or a preferred transliteration.
   - **Fit:** Settings → terminology editor, stored in per-user state; Changes → “Remember this spelling.” Apply across relevant Rewrite/Reply tones.
   - **Effort/risk:** **M.** No new Wayland dependency; matching inflections and resolving conflicting preferences are the main challenges.
   - **Rules:** Compatible. Preferences apply silently; ship no personal vocabulary or examples from the author.

7. **Source-backed Read — inspect the passage supporting a summary point.**
   - **Who/moment:** Someone checking whether a policy summary omitted a condition.
   - **Fit:** In Read, keyboard-select a point → reveal its source excerpt in Original. `rewrite.sh` returns structured references; validate excerpts against the input.
   - **Effort/risk:** **M.** No compositor dependency; fabricated or ambiguous references must fail visibly.
   - **Rules:** Compatible. Keep the fixed Read chips and render supporting evidence separately from answer text.

8. **Ask this selection — answer a specific question from the supplied text.**
   - **Who/moment:** “Does this policy allow cancellation after renewal?”
   - **Fit:** Extend Read’s Refine field into an explicit question action, retaining the original selection and supporting excerpts. Answer “not stated” when appropriate.
   - **Effort/risk:** **M.** No additional Wayland risk; resisting unsupported inference is the main model risk.
   - **Rules:** Compatible within Read. Questions originate in Polish’s own field; no new mode or web research agent.

9. **Explicit context tray — supply the earlier message without explaining it again.**
   - **Who/moment:** Replying to a message whose meaning depends on an earlier exchange.
   - **Fit:** Reply/Read → Add context → paste an excerpt into a temporary tray. Preview and remove excerpts before generating.
   - **Effort/risk:** **M.** Explicit paste avoids unreliable cross-app selection capture; enforce a combined input limit.
   - **Rules:** Compatible if all excerpts remain untrusted reference material. No automatic conversation scraping.

10. **Reply coverage check — show which questions the draft answers.**
    - **Who/moment:** A client asks four questions and the drafted response answers only three.
    - **Fit:** Reply → Ctrl+K → Check coverage; show answered/unanswered items beside supporting source passages, then return to the draft.
    - **Effort/risk:** **M.** No new compositor dependency; assessment requires an additional model run and can be wrong.
    - **Rules:** Compatible as an explicit, cost-labelled action. Never invent answers to fill gaps automatically.

11. **Private launch — omit this interaction from Polish’s history.**
    - **Who/moment:** Rewriting a sensitive personal message without changing the global history preference.
    - **Fit:** A dedicated launcher flag/binding sets privacy before generation; `shell.qml`, `apply.sh` and cleanup paths honor it, including undo-state retention.
    - **Effort/risk:** **M.** Clipboard managers and agent/provider retention lie outside Polish’s history controls.
    - **Rules:** Compatible. Describe it as **no Polish history**, not “nothing is stored anywhere.”

12. **Clipboard input fallback — work when primary selection is unavailable.**
    - **Who/moment:** Text is visibly selected, but the app does not expose the selection to Polish.
    - **Fit:** Add explicit `polish --clipboard`: Ctrl+C → dedicated binding → familiar popup. Start Copy-only unless the destination can be established safely.
    - **Effort/risk:** **S.** Clipboard ownership and stale contents; show the captured text and never silently substitute clipboard content.
    - **Rules:** Compatible. Explicit invocation needs no setting and preserves the untrusted-text boundary.

13. **Browser-anchored replacement — replace the captured selection, not merely paste into its window.**
    - **Who/moment:** A user changes tabs or a web editor moves focus while generation runs.
    - **Fit:** Extend `browser-extension/`, `native-host.py` and `apply.sh` with a request token tied to tab, frame, element and selection. Revalidate before applying; fall back to Copy on mismatch.
    - **Effort/risk:** **L.** Hyprland identifies windows, not browser fields; rich editors, navigation and undo integration complicate browser-side replacement.
    - **Rules:** Compatible and strengthens targeted delivery. No broad background page access.

14. **Stop and recover — abandon a stuck generation without losing the draft.**
    - **Who/moment:** An agent hits a rate limit or a request takes much longer than expected.
    - **Fit:** While busy, expose Stop; classify errors into actionable Retry or Choose agent. Preserve intent, edits and adjustments.
    - **Effort/risk:** **M.** Correctly terminate the run’s process tree without killing clipboard services or unrelated agent sessions.
    - **Rules:** Compatible. Switching providers remains explicit; avoid hidden fallback runs and disclosure to another provider.

15. **Resume a saved draft — continue work after the popup closes.**
    - **Who/moment:** A user has refined a difficult reply but needs to return later.
    - **Fit:** Ctrl+K → Save draft; History → Resume restores source, intent and chosen version. Resumed drafts start Copy-only because old targets are stale.
    - **Effort/risk:** **M.** Window addresses and selections cannot safely survive across sessions; richer retention needs clear boundaries.
    - **Rules:** Compatible as explicit saving to private state. This extends history beyond its current copy-only behavior.

16. **Certified local-only profile — make offline behavior an explicit guarantee.**
    - **Who/moment:** A user wants sensitive text processed locally or needs writing help without connectivity.
    - **Fit:** Agent picker exposes a verified local configuration, potentially through OpenCode, with a health check and enforced absence of remote fallback.
    - **Effort/risk:** **L.** No new compositor issue; hardware requirements, model quality and enforcing network isolation are the substantial work.
    - **Rules:** Compatible. This is a guarantee and setup workflow, not merely another model label; local capability may already be configurable through a user’s agent.

17. **Rewrite only this passage — improve one awkward sentence inside a good draft.**
    - **Who/moment:** Most of an email is right, but the opening needs work.
    - **Fit:** Select text inside the result editor → Refine selection; send surrounding text as reference, then splice the result into a new version.
    - **Effort/risk:** **M.** Internal selection handling avoids new Wayland capture; stale offsets during streaming or editing must invalidate the operation.
    - **Rules:** Compatible. Surrounding text remains untrusted context; instructions come exclusively from Refine.

**Top five by new-user value versus effort**

| Rank | Feature | Why |
|---|---|---|
| 1 | **Clipboard input fallback** | Small investment that turns “doesn’t work in my app” into a usable workflow. |
| 2 | **Fill reply blanks** | Makes the existing promise not to invent details practical and reduces accidental unfinished replies. |
| 3 | **Critical-detail check** | Makes review faster precisely where an unnoticed rewrite error is costly; no extra inference required. |
| 4 | **Accept individual changes** | Removes the all-or-nothing choice between accepting an intrusive rewrite and manually repairing it. |
| 5 | **Stop and recover** | Every new user eventually encounters an authentication, timeout or rate-limit failure; recovery determines whether they return. |

Browser-anchored replacement is strategically important, but its integration cost keeps it outside this value/effort top five.

For the existing roadmap: **translation from Rewrite is a useful small improvement**, especially for multilingual messaging. Global Read pins are worthwhile housekeeping. Dictation cleanup should consume existing dictated text first. Other compositors should follow a stable capture/apply interface and a reliable Hyprland release.

**Three things I would deliberately not build**

1. **Always-on grammar underlines or automatic replacement.** This introduces persistent monitoring, app-specific integration and interruption into a product whose strength is deliberate invocation.
2. **A general chat assistant with browsing, tools and autonomous sending.** It expands the permission and reliability surface while duplicating the agent CLI or browser assistant the user already has.
3. **A large tone marketplace or dozens of built-in styles.** Custom tones already cover niche needs. More overlapping chips undermine distinct modes and the uncluttered interface.

**Installation and trust gaps to address before expanding features**

- **The install promise exceeds the installer.** [install.sh](install.sh:20) prints one Rewrite binding; it does not establish the advertised Right Alt, Reply or Undo flows. Provide dependency checks, a complete binding setup, uninstall instructions and a disposable first-run exercise. Make Right Alt optional because of AltGr use.

- **Agent discovery has concrete first-run problems.** [rewrite.sh](rewrite.sh:15) looks for `commandcode`, but execution invokes `cmd`. The selected/default agent is also not reconciled with installed agents before generation. Detect the actual executable, select an available agent, and distinguish installation, authentication and model-access failures.

- **Package and compatibility information is missing.** I found no license file, package manifest, automated test suite or release workflow in the checked-out file inventory. Establish a license, versioned releases, dependency versions, update/rollback instructions and a clear supported Omarchy/Hyprland baseline. Include Python and `xkbcli`, which the implementation uses.

- **Window targeting is not selection targeting.** The browser bridge captures tab/frame information but does not retain it for application. Native launches also treat unknown editability as editable in [shell.qml](shell.qml:21). Document the boundary and provide conservative fallbacks; a successful shortcut dispatch does not prove the intended text was replaced.

- **One privacy claim is contradicted by code.** [apply.sh](apply.sh:147) passes the original text through `jq --arg original`, placing it on a process command line despite the stated rule. Fix this before advertising that text never enters argv.

- **Retention needs a first-run explanation.** History defaults on and records the complete result plus the first 300 source characters, including when a result is simply closed: [shell.qml](shell.qml:938). Explain local history, undo state, clipboard exposure and provider retention separately. “No middleman” does not mean local inference.

- **Narrow absolute safety claims.** “Never invents,” “every fact kept,” and prompt-injection immunity are aspirations, not guarantees established by prompts. Read-only sandboxing and plan modes also do not by themselves establish “no tools.” Publish the actual per-agent restrictions and reproducible quality checks.

- **Resolve prompt conflicts before adding more styles.** Punchy explicitly removes “approximately” and “assuming that,” which can change meaning; Concise demands half the length while preserving every fact. Fidelity should win when those goals conflict. These are more consequential than adding another tone.

My first release investment would be **installation, accurate trust claims and dependable recovery**, followed by the five ranked features.