#!/bin/bash
# Claude Code statusline: exports rate_limits to a file other apps can read,
# projects usage at reset, and prints a one-line status.
set -euo pipefail

OUT="${CLAUDE_USAGE_FILE:-$HOME/.claude/usage-live.json}"
input=$(cat)

# rate_limits is absent until the first API response; keep the last good file then.
if printf '%s' "$input" | jq -e '.rate_limits.five_hour or .rate_limits.seven_day' >/dev/null; then
  printf '%s' "$input" | jq -c '
    def proj($w; $len):
      if $w == null then null else
        (now | floor) as $now
        | ($w.resets_at - $len) as $start
        | ([($now - $start), 60] | max) as $elapsed
        | ($w.used_percentage / $elapsed) as $rate
        | {
            used_pct: $w.used_percentage,
            resets_at: $w.resets_at,
            projected_pct_at_reset: (($w.used_percentage + $rate * ($w.resets_at - $now)) * 10 | round / 10),
            runs_out_at: (if $rate > 0 then ($now + (100 - $w.used_percentage) / $rate | floor) else null end),
            lasts_until_reset: (($w.used_percentage + $rate * ($w.resets_at - $now)) < 100)
          }
      end;
    {
      updated_at: (now | floor),
      session_id,
      model: .model.display_name,
      five_hour: proj(.rate_limits.five_hour; 18000),
      seven_day: proj(.rate_limits.seven_day; 604800)
    }' > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  # ponytail: linear burn rate since window start; append $OUT to a .jsonl if you want recent-rate projections
fi

jq -r '
  def fmt($n; $w): if $w == null then empty else
    "\($n) \($w.used_pct)% → \($w.projected_pct_at_reset)%" + (if $w.lasts_until_reset then "" else " ⚠" end) end;
  [fmt("5h"; .five_hour), fmt("7d"; .seven_day)] | join("  ")
' "$OUT" 2>/dev/null || true
