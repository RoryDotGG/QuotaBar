#!/bin/bash
# Fetch Claude plan usage with Claude Code's keychain login, write it to a JSON file
# other apps can read, and project whether each limit lasts until reset.
# Works without the CLI. Unofficial endpoint: may change without notice.
set -euo pipefail

OUT="${CLAUDE_USAGE_FILE:-$HOME/.claude/usage-live.json}"
now=$(date +%s)

write_status() { # keep last good numbers, just update status
  local prev='{}'; [[ -s "$OUT" ]] && prev=$(cat "$OUT")
  jq -c --arg s "$1" --argjson n "$now" '. + {status: $s, checked_at: $n}' <<<"$prev" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  echo "$1" >&2; exit 1
}

if [[ -n "${CLAUDE_USAGE_RESPONSE:-}" ]]; then
  resp=$(cat "$CLAUDE_USAGE_RESPONSE") # test hook: use a saved response
else
  creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || write_status "no_credentials"
  # Never refresh the token here; `claude auth status` renews it without a model call.
  exp=$(jq -r '.claudeAiOauth.expiresAt // 0' <<<"$creds")
  (( exp / 1000 > now )) || write_status "token_expired_run_claude_auth_status"
  resp=$(jq -r '"Authorization: Bearer " + .claudeAiOauth.accessToken' <<<"$creds" |
    curl -sS --max-time 15 -H @- -H 'anthropic-beta: oauth-2025-04-20' \
      'https://api.anthropic.com/api/oauth/usage') || write_status "network_error"
  unset creds
  jq -e '.limits or .seven_day' >/dev/null <<<"$resp" 2>/dev/null || write_status "bad_response"
fi

jq -c --argjson now "$now" '
  def ts: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdate;
  def window($name; $pct; $reset; $len):
    ($reset | ts) as $r | ($r - $len) as $start
    | ([$now - $start, 60] | max) as $elapsed
    | ($pct / $elapsed) as $rate
    | ($pct + $rate * ($r - $now)) as $proj
    | {
        name: $name, used_pct: $pct, resets_at: $r,
        window_elapsed_pct: ($elapsed / $len * 100 | round),
        projected_pct_at_reset: ($proj | round),
        runs_out_at: (if $rate > 0 and $proj >= 100 then ($now + (100 - $pct) / $rate | floor) else null end),
        lasts_until_reset: ($proj < 100)
      };
  {
    status: "ok", checked_at: $now, updated_at: $now,
    limits: (
      [ (.five_hour | select(. != null) | window("5-hour"; .utilization; .resets_at; 18000)) ]
      + [ (.limits // [])[]
          # ponytail: only weekly windows seen so far; anything else assumed 5h
          | window(
              (if .kind == "weekly_all" then "Weekly · all models"
               else "Weekly · " + (.scope.model.display_name // .kind) end);
              .percent; .resets_at;
              (if .group == "weekly" then 604800 else 18000 end)) ]
    )
  }' <<<"$resp" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

jq -r '.limits[] | "\(.name): \(.used_pct)% used, \(.window_elapsed_pct)% of window gone, on pace for \(.projected_pct_at_reset)%"
  + (if .lasts_until_reset then " ✓" else " ⚠ runs out \(.runs_out_at | localtime | strftime("%a %H:%M"))" end)' "$OUT"
