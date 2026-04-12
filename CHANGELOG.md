# Changelog

All notable changes to the Token Counter Plugin will be documented in this file.

## [1.0.0] - 2026-04-12

### Added
- Initial release of Token Counter Plugin
- Real-time token usage monitoring on Stop and StopFailure hooks
- Context breakdown showing system prompt, conversation, and output tokens
- Cache efficiency tracking with hit rate percentage
- Session total output token tracking
- 70% threshold warning with desktop notifications
- Visual progress bar for context window usage
- Support for all Claude models (Opus, Sonnet, Haiku)
- Model-specific context limit detection
- Debug logging to `/tmp/claude-hook-debug.txt`
- Status file output to `/tmp/claude-token-status.txt` for external monitoring

### Features
- Automatic transcript sync detection with retry logic
- System prompt caching detection via `cache_creation_input_tokens`
- Cache read efficiency calculation
- Session-level sentinel to prevent duplicate notifications
- Graceful error handling for missing transcripts

### Requirements
- jq (JSON query tool)
- python3
- notify-send (for desktop notifications on Linux)
