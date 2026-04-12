#!/bin/bash
# Show token usage after each Claude response via Stop hook
# Sends desktop notification + systemMessage warning at 70% context usage

INPUT=$(cat)
echo "[token-count] fired at $(date), input: $INPUT" >> /tmp/claude-hook-debug.txt

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

if [ -z "$SESSION_ID" ]; then
  echo "[token-count] no session_id" >> /tmp/claude-hook-debug.txt
  exit 0
fi

# Use transcript_path from hook input (more reliable than find)
SESSION_FILE=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Fallback to find if transcript_path not provided
if [ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  SESSION_FILE=$(find ~/.claude/projects -name "${SESSION_ID}.jsonl" 2>/dev/null | head -1)
fi

if [ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  echo "[token-count] no session file for $SESSION_ID" >> /tmp/claude-hook-debug.txt
  exit 0
fi

# --- Model limit detection ---
MODEL=$(jq -r '.model // "sonnet"' ~/.claude/settings.json 2>/dev/null)

declare -A MODEL_LIMITS=(
  ["opus[1m]"]=1000000
  ["opus"]=200000
  ["sonnet"]=200000
  ["sonnet-4-6"]=200000
  ["haiku"]=200000
  ["haiku-4-5"]=200000
  ["claude-haiku-4-5-20251001"]=200000
)

LIMIT=${MODEL_LIMITS[$MODEL]:-200000}

# Extract last_assistant_message for transcript sync check
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')

# --- Parse tokens via Python (full breakdown) ---
USAGE=$(SESSIONFILE="$SESSION_FILE" LAST_MSG="$LAST_MSG" python3 -c "
import json, sys, os, time

limit = $LIMIT
session_file = os.environ['SESSIONFILE']
expected_last = os.environ.get('LAST_MSG', '').strip()

# Retry loop: wait for transcript to be updated with the latest message
assistant_msgs = []
for attempt in range(10):
    with open(session_file) as f:
        lines = f.readlines()

    messages = []
    for line in lines:
        try:
            messages.append(json.loads(line))
        except:
            pass

    assistant_msgs = [m for m in messages if m.get('type') == 'assistant']
    if assistant_msgs and expected_last:
        last_content = assistant_msgs[-1].get('message', {}).get('content', '')
        if isinstance(last_content, list):
            last_text = ' '.join(
                b.get('text', '') for b in last_content if isinstance(b, dict) and b.get('type') == 'text'
            )
        else:
            last_text = str(last_content)
        # Check first 80 chars match to confirm transcript is up to date
        if expected_last[:80].strip() in last_text or last_text[:80].strip() in expected_last:
            break
    time.sleep(0.3)

if not assistant_msgs:
    sys.exit()

# --- System prompt: cached on first assistant message ---
first_u = assistant_msgs[0].get('message', {}).get('usage', {})
sys_prompt = first_u.get('cache_creation_input_tokens', 0)

# --- Current turn detection ---
turn_start_idx = 0
for i, m in enumerate(messages):
    if m.get('type') == 'user':
        content = m.get('message', {}).get('content', [])
        if isinstance(content, list):
            is_tool_result = all(c.get('type') == 'tool_result' for c in content if isinstance(c, dict))
        else:
            is_tool_result = False
        if not is_tool_result:
            turn_start_idx = i

turn_assistant_usages = [
    m.get('message', {}).get('usage', {})
    for m in messages[turn_start_idx:]
    if m.get('type') == 'assistant' and m.get('message', {}).get('usage')
]

if not turn_assistant_usages:
    sys.exit()

# --- Latest API call context (last assistant message = current state) ---
last_u = assistant_msgs[-1].get('message', {}).get('usage', {})
ctx_input = last_u.get('input_tokens', 0)
ctx_cache_read = last_u.get('cache_read_input_tokens', 0)
ctx_cache_write = last_u.get('cache_creation_input_tokens', 0)
context_window = ctx_input + ctx_cache_read + ctx_cache_write

# --- Breakdown categories ---
conversation = context_window - sys_prompt

# Output this turn
turn_output = sum(u.get('output_tokens', 0) for u in turn_assistant_usages)
turn_calls = len(turn_assistant_usages)

# Cache efficiency
cache_total = ctx_cache_read + ctx_cache_write
cache_hit_pct = (ctx_cache_read / cache_total * 100) if cache_total > 0 else 0

# Context percentage
ctx_pct = context_window / limit * 100 if limit > 0 else 0

# Cumulative output across entire session
total_output = sum(
    m.get('message', {}).get('usage', {}).get('output_tokens', 0)
    for m in assistant_msgs
)

# Format helpers
def fmt(n):
    if n >= 1_000_000:
        return f'{n/1_000_000:.1f}M'
    elif n >= 1_000:
        return f'{n/1_000:.1f}k'
    return str(n)

def limit_fmt(n):
    if n >= 1_000_000:
        return f'{n//1_000_000}M'
    elif n >= 1_000:
        return f'{n//1_000}k'
    return str(n)

# Progress bar
bar_width = 30
filled = int(bar_width * ctx_pct / 100)
bar = chr(9608) * filled + chr(9617) * (bar_width - filled)

import json

threshold = $LIMIT * 0.70

warning = ''
if context_window >= threshold:
    warning = '\n  ' + chr(9888) + ' WARNING: 70% threshold reached — consider /compact or wrapping up'

# Choose bar color indicator
if ctx_pct >= 70:
    status = 'CRITICAL'
elif ctx_pct >= 40:
    status = 'MODERATE'
else:
    status = 'OK'

call_s = 's' if turn_calls != 1 else ''
warn_inline = '  ' + chr(9888) + ' >70%' if context_window >= threshold else ''

header = f'[{bar}] {ctx_pct:.1f}% used  ({context_window:,} / {limit:,} tokens)  [{status}]{warn_inline}'

details = (
    f'  CONTEXT BREAKDOWN:\n'
    f'    System prompt (instructions):  {fmt(sys_prompt):>8}  (cached once at session start)\n'
    f'    Conversation so far:           {fmt(conversation):>8}  (messages, tool calls, results)\n'
    f'\n'
    f'  THIS TURN:\n'
    f'    Output tokens generated:       {fmt(turn_output):>8}  (across {turn_calls} API call{call_s})\n'
    f'\n'
    f'  SESSION TOTALS:\n'
    f'    Total tokens output:           {fmt(total_output):>8}  (all responses combined)\n'
    f'\n'
    f'  CACHE EFFICIENCY:\n'
    f'    Cache hit rate:                {cache_hit_pct:>7.0f}%  (higher = cheaper + faster)\n'
    f'    Reused from cache:             {fmt(ctx_cache_read):>8}\n'
    f'    Written to cache:              {fmt(ctx_cache_write):>8}\n'
    f'    Fresh (uncached) input:        {fmt(ctx_input):>8}'
)

if context_window >= threshold:
    details += '\n\n  ' + chr(9888) + ' WARNING: 70% threshold reached — consider /compact or wrapping up'

msg = header + '\n' + details

# Output JSON with context_window and pct as separate fields for shell
output = {
    'systemMessage': msg,
    '_context_window': context_window,
    '_pct': round(ctx_pct, 1)
}
print(json.dumps(output))
" 2>/dev/null)

if [ -z "$USAGE" ]; then
  exit 0
fi

# --- Extract threshold info for desktop notification ---
CONTEXT_WINDOW=$(echo "$USAGE" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('_context_window', 0))")
PCT=$(echo "$USAGE" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('_pct', 0))")

THRESHOLD=70
IS_OVER=$(python3 -c "print('yes' if float('${PCT}') >= $THRESHOLD else 'no')" 2>/dev/null)

# Set TEST_NOTIFY=1 to force a desktop notification regardless of threshold
if [ "$IS_OVER" = "yes" ] || [ "$TEST_NOTIFY" = "1" ]; then
  SENTINEL="/tmp/claude-hook-threshold-${SESSION_ID}"
  # TEST_NOTIFY bypasses the once-per-session sentinel
  if [ ! -f "$SENTINEL" ] || [ "$TEST_NOTIFY" = "1" ]; then
    notify-send --urgency=critical "Claude Code" "Context at ${PCT}% — consider wrapping up" 2>/dev/null &
    touch "$SENTINEL"
  fi
fi

# --- Write status file for VS Code / tail-watching ---
echo "$USAGE" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
msg = data.get('systemMessage', '')
if msg:
    open('/tmp/claude-token-status.txt', 'w').write(msg + '\n')
" 2>/dev/null

# --- Output systemMessage (strip internal fields) ---
echo "$USAGE" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
data.pop('_context_window', None)
data.pop('_pct', None)
print(json.dumps(data))
"
