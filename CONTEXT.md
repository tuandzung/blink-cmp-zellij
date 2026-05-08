# blink-cmp-zellij

A blink.cmp completion source that extracts words from zellij panes. Single-file Lua Neovim plugin operating as a bridge between zellij's CLI actions and blink.cmp's Source interface.

## Language

**Completion Request**:
A single invocation of `get_completions(context, callback)` by blink.cmp, typically triggered on every keystroke.
_Avoid_: query, lookup

**Pane Capture**:
The result of running `zellij action dump-screen` on a pane — raw terminal viewport content including ANSI escape codes.
_Avoid_: screenshot, snapshot

**Word Extraction**:
Pattern-based extraction of tokens (`[%w%d_:/.%-~]+`) from pane captures, producing unique completion candidates.
_Avoid_: parsing, tokenization

**All-Panes Mode**:
Configuration (`all_panes = true`) that enumerates session panes via `list-panes` and captures content from each. Opposite: single-pane mode (captures only the focused pane).

**Cancellation Function**:
A function returned by `get_completions` that blink.cmp calls to abort an in-flight request when a newer one supersedes it.

## Relationships

- A **Completion Request** triggers one or more **Pane Captures** (1 in single-pane mode, N+1 in all-panes mode)
- Each **Pane Capture** feeds into **Word Extraction**
- **Word Extraction** produces the completion items returned to blink.cmp
- A **Cancellation Function** aborts in-flight **Pane Captures** and discards their results

## Example dialogue

> **Dev:** "When a **Completion Request** fires in **All-Panes Mode**, how many **Pane Captures** run?"
> **Domain expert:** "N+1 — one `list-panes` to enumerate panes, then one `dump-screen` per non-plugin, non-current pane."

## Flagged ambiguities

- "cache" was used loosely to mean both the TTL-gated word store and the in-flight subprocess result collector — resolved: "cache" refers to the TTL-gated word store; "collection" refers to gathering async subprocess results.
