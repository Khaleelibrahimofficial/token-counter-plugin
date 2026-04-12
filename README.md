# Token Counter Plugin

Real-time token usage monitoring for Claude Code with detailed context breakdown and cache efficiency tracking.

## Features

- 📊 **Real-time token monitoring** - Displays token usage after each response
- 🎯 **Context breakdown** - See system prompt, conversation, and output tokens separately
- 💾 **Cache efficiency tracking** - Monitor prompt cache hit rates and savings
- ⚠️ **70% threshold alerts** - Desktop notifications and warnings when approaching context limits
- 📈 **Session totals** - Track cumulative token usage across your session
- 🎨 **Visual progress bar** - Easy-to-read context window visualization

## Installation

### Via Claude Code Plugin System

```bash
/plugin marketplace add Khaleelibrahimofficial/token-counter-plugin
/plugin install token-counter@Khaleelibrahimofficial/token-counter-plugin
```

Or with scope (default is user):
```bash
/plugin install token-counter@Khaleelibrahimofficial/token-counter-plugin --scope user
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Khaleelibrahimofficial/token-counter-plugin.git ~/.claude/plugins/token-counter
   ```

2. Reload plugins:
   ```bash
   /reload-plugins
   ```

## How It Works

The plugin automatically monitors your token usage by hooking into Claude Code's `Stop` and `StopFailure` events. After each response, it:

1. **Reads your session transcript** - Accesses the conversation history
2. **Parses token usage data** - Extracts token counts from API responses
3. **Calculates metrics** - Determines context usage, cache efficiency, and breakdowns
4. **Displays results** - Shows a comprehensive summary in system messages
5. **Alerts on threshold** - Sends a desktop notification when reaching 70% context usage

## Output Explanation

```
[████████████░░░░░░░░░░░░░░░░] 42.3% used  (84,600 / 200,000 tokens)  [OK]

  CONTEXT BREAKDOWN:
    System prompt (instructions):     12.5k  (cached once at session start)
    Conversation so far:              72.1k  (messages, tool calls, results)

  THIS TURN:
    Output tokens generated:           3.2k  (across 1 API call)

  SESSION TOTALS:
    Total tokens output:              25.4k  (all responses combined)

  CACHE EFFICIENCY:
    Cache hit rate:                     85%  (higher = cheaper + faster)
    Reused from cache:                 12.5k
    Written to cache:                      0
    Fresh (uncached) input:            72.1k
```

### Understanding the Metrics

- **Context Usage %** - How much of your model's context window you've used
- **System Prompt** - Your instructions (cached on first message for free after first 2 reads)
- **Conversation** - User messages, tool calls, and results accumulate here
- **Cache Hit Rate** - Percentage of tokens reused from prompt cache (saves 90% cost)
- **Output Tokens** - Tokens Claude generated this turn

## Configuration

### Adjusting the Threshold

Edit `hooks/hooks.json` to change the 70% warning threshold:

```json
{
  "Stop": [
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/token-count.sh",
      "timeout": 5,
      "env": {
        "THRESHOLD": "75"  // Change threshold percentage here
      }
    }
  ]
}
```

### Model-Specific Limits

The plugin automatically detects your model and applies the correct context limit:

- **Opus**: 1,000,000 tokens
- **Sonnet (4.6)**: 200,000 tokens
- **Haiku (4.5)**: 200,000 tokens

## Troubleshooting

### No output shown

- Ensure you have `jq` and `python3` installed on your system
- Check `/tmp/claude-hook-debug.txt` for debug logs
- Verify the script is executable: `ls -la hooks/token-count.sh`

### Desktop notifications not appearing

- Verify `notify-send` is installed (Linux only)
- Some desktop environments may require permission changes
- Test with: `notify-send "Test"`

### Token counts seem wrong

- Ensure your session transcript is being written to `~/.claude/projects/`
- Wait a moment after response for transcript sync
- Check system messages for warnings about transcript sync

## Requirements

- **jq** - JSON processor (`apt install jq`)
- **python3** - For token calculations
- **notify-send** - For desktop notifications (Linux)

## Performance

- Minimal impact: Hook runs asynchronously with 5-second timeout
- Python parsing is fast for typical session sizes
- Output tokens only shown for completed responses

## Privacy & Security

- All processing is local - no data sent to external services
- Reads only your session transcript file
- No telemetry or tracking

## Contributing

Found a bug or have a feature idea? Open an issue on [GitHub](https://github.com/Khaleelibrahimofficial/token-counter-plugin/issues).

## License

MIT
