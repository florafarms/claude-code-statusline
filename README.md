# Claude Code Statusline — Real Quota %, Burn Rate, Per-Model Breakdown

A drop-in statusline for [Claude Code](https://claude.com/claude-code) that shows your **real** plan usage — pulled from Anthropic's OAuth `/usage` endpoint, not just local token counts.

```
💰 $0.52  🔥 $11.91/h  📊 5h 24% (4h20m)  🗓 7d 65% (5d04h)  Fable 3.1M/➤Opus 7.3M◄/Sonnet 3.2M
```

| Segment | Meaning |
|---|---|
| 💰 `$X` | Current session cost (gray) |
| 🔥 `$X/h` | Burn rate of the active 5-hour block (red) |
| 📊 `5h X%` | % consumed of the **5-hour rate-limit block** + time until reset |
| 🗓 `7d X%` | % consumed of the **weekly limit** + time until reset (days when >24h, hours otherwise) |
| 🧠 `Opus X%` | % of the weekly Opus quota (only when Anthropic reports it) |
| `Fable / Opus / Sonnet / Haiku` | Tokens spent in this block per model — Fable (pink), Opus (magenta), Sonnet (cyan), Haiku (green). Names are separated by bold-black slashes. Only models with usage are shown; Mythos counts as Fable |
| `➤...◄` | The **active model** is bracketed by red arrows and underlined (keeping its family color), so you can see at a glance which model this session is on. Always shown even with zero tokens |

Color thresholds: **green** <50% · **yellow** <80% · **red** ≥80%.
Estimated values are prefixed with `~` and show `⚠ datos Xm` if the Anthropic endpoint is unreachable.

---

## Install — one command

```bash
git clone https://github.com/florafarms/claude-code-statusline.git ~/claude-code-statusline \
  && bash ~/claude-code-statusline/install.sh
```

> Replace `florafarms` with the GitHub user/org hosting this repo.

After install, restart Claude Code (or run `/statusline`).

### What the installer does

1. Copies `statusline.sh` to `~/.claude/scripts/statusline.sh`
2. Adds a `statusLine` entry to `~/.claude/settings.json` (merging — won't overwrite existing keys)
3. Refresh interval: 10 s

The script also caches the Anthropic quota response for **30 s** to avoid hitting the endpoint on every refresh.

---

## How another Claude Code agent can install this for the user

Paste this prompt into a fresh Claude Code session:

> Clone <https://github.com/florafarms/claude-code-statusline> into `~/claude-code-statusline` and run `install.sh`. Then verify by echoing test JSON into the script:
> `echo '{"cost":{"total_cost_usd":0}}' | bash ~/.claude/scripts/statusline.sh`
> Show me the rendered output.

The installer is idempotent — re-running it just refreshes the script.

---

## Requirements

- **macOS, Linux, or Windows** (macOS reads the OAuth token from Keychain; Linux/Windows read it straight from Claude Code's own credentials file — see *Windows / Linux notes* below)
- **Python 3** (built-in on macOS; see Windows notes if `python3`/`python` resolve to a Microsoft Store stub)
- **curl**
- **Claude Code** already authenticated (`claude /login` once)
- **Optional but recommended:** [`ccusage`](https://github.com/ryoppippi/ccusage) — `npm i -g ccusage` — enables burn-rate and per-model breakdown

---

## How the % numbers work

The script reads `https://api.anthropic.com/api/oauth/usage` with the OAuth token Claude Code already stored — on macOS, via Keychain:

```
security find-generic-password -s "Claude Code-credentials" -w
```

On Windows/Linux, from Claude Code's own credentials file instead (see *Windows / Linux notes* below).

That endpoint returns the **real** `five_hour.utilization`, `seven_day.utilization`, and `seven_day_opus.utilization` — the same numbers you see at <https://claude.ai/settings/usage>.

### Fallback when the endpoint is rate-limited or offline

| Field | Fallback |
|---|---|
| 5-hour % | Last persisted value; if none, `block_tokens / 220 M` from `ccusage blocks --active` |
| 7-day % | Last persisted value; if none, `sum(daily.totalTokens last 7d) / 1.5 B` from `ccusage daily` |
| 5-hour reset | `ccusage`-derived `projection.remainingMinutes` |
| 7-day reset | Next Monday 12:00 UTC (Anthropic's typical weekly cutoff) |

Estimated values are prefixed `~` so you always know whether you're looking at ground truth or an approximation.

---

## Windows / Linux notes

There's no Keychain outside macOS, but you don't need one: Claude Code stores the same OAuth token (`claudeAiOauth.accessToken`) in plain JSON at `~/.claude/.credentials.json` on every platform. The script tries Keychain first and, if that fails or isn't available, reads that file directly — so real quota % (not just the ccusage estimate) works on Windows and Linux too, no extra setup needed.

**Windows-specific gotcha:** `python3`/`python` on PATH can silently be a Microsoft Store "app execution alias" stub — `command -v` finds it, but running it just opens the Store instead of executing code. The script probes candidates for real (`"$cand" -c ""`) before using them, and falls back to scanning `%LOCALAPPDATA%\Programs\Python\Python3*\python.exe` (the typical `winget install Python.Python.3.x` / python.org installer location) if PATH only offers the broken stub. If you hit this, install a real Python with:

```bash
winget install --id Python.Python.3.12 -e --source winget
```

Also note Windows consoles default to a legacy codepage (cp1252) that can't print the emoji this script uses — it forces `PYTHONIOENCODING=utf-8` before invoking Python to avoid a crash. This is a no-op on macOS/Linux.

---

## Files

| Path | Purpose |
|---|---|
| `statusline.sh` | The script Claude Code runs every 10 s |
| `install.sh` | Idempotent installer |
| `README.md` | This file |

State files created at runtime (gitignored):

```
~/.claude/scripts/.statusline_cache.json   # 30s cache of API + ccusage responses
~/.claude/scripts/.quota_last_seen.json    # last good quota snapshot for fallback
```

---

## Uninstall

```bash
rm ~/.claude/scripts/statusline.sh
# then remove the "statusLine" key from ~/.claude/settings.json
```

---

## Credits & licence

Built collaboratively in a Claude Code session. Endpoint discovery inspired by [`cclimits`](https://github.com/cruzanstx/cclimits) and [ClaudeMeter](https://github.com/eddmann/ClaudeMeter).

MIT — do what you want, no warranty.
