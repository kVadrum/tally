# tally

Token and activity report for Claude Code session transcripts.

Claude Code writes every session to a JSON-lines transcript under
`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` — one line per
event (user prompt, assistant response, tool result). That file is the
ground truth for what a session actually did: how long it ran, how many
turns and tool calls, and how many tokens it burned. The live `/cost`
view covers the current interactive session only; there's no built-in
way to look back at a finished session, an autonomous `claude -p` run,
or a whole directory of past sessions. `tally` reads the transcripts and
reports.

The detail that makes this worth a tool rather than a one-line `jq`:
**correct token accounting.** Claude Code logs an assistant response
*once per content block* — a message with a thinking block, a text
block, and two tool calls becomes four transcript lines, and every one
of them carries the same `usage` object. Summing the raw lines
overcounts, often badly (2.8x on a real transcript: 136,711 raw vs the
true 48,336). `tally` groups assistant lines by `message.id` and counts
each response's usage once. Tool calls, by contrast, *are* one-per-line,
so they're counted across all lines — both halves come out right.

Bash + [`jq`](https://jqlang.github.io/jq/). No other dependencies; all
the date math is done in `jq` (`fromdateiso8601`), so there's no
reliance on GNU `date`.

## Background

tally was conceived and written by Claude in claude-expo — a private
workshop where Claude picks and builds small utilities under operator
oversight. Correctness- and security-sensitive changes get a
cross-vendor second read from Codex (OpenAI's GPT) before they land.
More on the workshop in
[claude-journal](https://github.com/kVadrum/claude-journal).

## Usage

```
tally [PATH]          report on a transcript file, or a directory of them
tally                 default PATH is the current directory
tally --json          machine-readable JSON (per-session objects + a total)
tally --quiet | -q    directory mode: print only the TOTAL line
tally --no-color      disable ANSI styling (also honors NO_COLOR)
tally --version       print version
tally -h | --help     show help
```

Point it at your transcript directory:

```
tally ~/.claude/projects/<encoded-cwd>/
```

A single file gives a detailed report; a directory gives a one-row
table per session plus a totals line.

## What it reports

Per session:

- **elapsed** — wall-clock span from the first to the last event
  timestamp. For an interactive session left open this includes idle
  time; for an autonomous run it's the real duration.
- **prompts** — count of human prompts (user events whose content is a
  string, as opposed to tool-result events).
- **turns** — assistant responses, deduplicated by `message.id`.
- **tools** — tool-call count, broken down by tool name.
- **tokens** — `input`, `output`, `cache-read`, `cache-write`, each
  deduplicated by `message.id`.
- **model(s)** and the Claude Code **client version**.

In directory mode the totals line sums every readable session.

## Output

Text by default; `--json` for a structured document. The JSON single-file
form is one object; the directory form is `{ sessions: [...], total: {...} }`.
There is intentionally no `--ci` mode — these are stats, not findings,
and nothing consumes a CI annotation of them.

## Exit codes

- `0` — reported successfully.
- `2` — usage error, bad path, no transcripts found, or (single-file
  mode) a file that isn't a valid transcript.

In directory mode, an unparseable file or one with no session events is
skipped with a note on stderr; the run still exits `0` as long as at
least one transcript was readable.

## Scope and limits

- **No cost estimate yet.** Token counts are objective ground truth;
  dollar cost is derived from per-model prices that change and go stale.
  Reporting tokens correctly first; a cost layer (driven by an explicit
  price source, not baked-in numbers) is a possible follow-up.
- **Flat directory scan** (`-maxdepth 1`, `*.jsonl`). Transcripts live
  one-per-file in a session directory; tally doesn't recurse.
- **`prompts` counts string-content user events.** Slash-command
  expansions and other injected string prompts count as prompts; tool
  results do not. This is a deliberate, documented definition rather
  than an attempt to reconstruct "what the human typed."

A note on prior art: external tools such as `ccusage` already report
Claude Code usage. `tally` is the house, dependency-light version — it
reads the same transcripts with nothing but `bash` and `jq`, and exists
mainly to give the autonomous rigs and the morning review an objective,
scriptable read on what a session did.

## Tests

```
tests/run.sh
```

Behavioral, fixture-driven. The load-bearing fixture (`basic.jsonl`)
reproduces the per-content-block duplication and pins the deduped token
count, so a regression in the `message.id` grouping fails the suite.

## Status

v0.1.2. Extracted from the claude-expo workshop as a standalone repo
(fresh history, current state). Bash + jq.

## License

MIT — see [`LICENSE`](./LICENSE). "tally" as a name and the KeMeK
Network identity are not covered by the code license.

---

KeMeK Network © 2026
