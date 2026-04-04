# Chat Scroll Challenge — Solution

## UX Issues Identified & Fixed

### 🔴 Issue 1 — Compile Error: Missing `onSend` parameter
**Problem:** The custom `_Composer` widget declared `onSend` as a required parameter, but it was never passed in the `composerBuilder`. This caused a compile-time error and the app wouldn't run at all.  
**Fix:** Added `onSend: _handleMessageSend` to the `_Composer` instantiation inside `composerBuilder`.

---

### 🔴 Issue 2 — Double Message Send
**Problem:** Both `onMessageSend` on the `Chat` widget and the custom `_Composer` were calling `_handleMessageSend`, causing every message to be sent and inserted twice.  
**Fix:** Removed `onMessageSend` from the `Chat` widget entirely. The `_Composer` is now the single source of truth for sending messages.

---

### 🔴 Issue 3 — Auto-scroll Not Working During Streaming
**Problem:** `animateTo` was used to scroll during streaming. While the animation was in progress, new content arrived and `maxScrollExtent` grew — but the animation completed at the old (smaller) value. This made `_isAtBottom` become `false`, which stopped the auto-scroll permanently mid-stream.  
**Fix:** Replaced `animateTo` with `jumpTo` (synchronous, no animation delay) combined with a `Timer.periodic(100ms)` that continuously scrolls to the latest `maxScrollExtent` as long as streaming is active. A `WidgetsBinding.instance.addPostFrameCallback` wrapper ensures the layout is fully rendered before each scroll on Flutter Web.

---

### 🟡 Issue 4 — Manual Scroll Didn't Pause Auto-scroll
**Problem:** The scroll listener (`_handleScroll`) couldn't distinguish between programmatic scroll events (from `jumpTo`) and real user drag events. When `jumpTo` fired every 100ms, it triggered the listener and sometimes reset `_isAtBottom` incorrectly, preventing the user from scrolling up during streaming.  
**Fix:** Added two guards:
- `_isProgrammaticScroll` flag: set to `true` before `jumpTo` and `false` immediately after, so the listener ignores programmatic events.
- `_userIsDragging` flag: set via `NotificationListener<ScrollNotification>` — detects real drag starts (`dragDetails != null`) and ends, so `jumpTo` is skipped entirely while the user is actively scrolling.

---

### 🟡 Issue 5 — Composer Rendered at Top Instead of Bottom
**Problem:** The `composerBuilder` in `flutter_chat_ui` v2.x renders the composer at the top of the chat list, not at the bottom of the screen.  
**Fix:** Replaced the internal `composerBuilder` with a `SizedBox.shrink()` (empty widget), and placed the `_Composer` widget outside the `Chat` widget entirely — at the bottom of a `Column` that wraps the `Expanded` chat area.

---

### 🟡 Issue 6 — Hint Text Not Visible (White on White)
**Problem:** The `TextField` in the composer used a hardcoded `Colors.grey.shade200` background, which in light mode made the hint text invisible (light text on light background).  
**Fix:** Replaced all hardcoded colors with proper `Theme.of(context).colorScheme` values:
- Background: `colorScheme.surfaceContainerHighest`
- Hint text: `colorScheme.onSurfaceVariant`
- Input text: `colorScheme.onSurface`

This ensures correct visibility in both light and dark modes.

---

### 🟡 Issue 7 — `setState` After `dispose` (Memory Bug)
**Problem:** In both `onDone` and `_handleStreamError`, `_stopAutoScrollTimer()` (which touches `_scrollController`) was called before the `mounted` check. If the widget was disposed mid-stream, this caused a `setState after dispose` error.  
**Fix:** Wrapped `_stopAutoScrollTimer()` calls with `if (mounted)` checks before interacting with any widget state.

---

### 🟡 Issue 8 — `TextEditingController` Not Disposed
**Problem:** The `_controller` in `_ComposerState` was never disposed, causing a memory leak.  
**Fix:** Added `_controller.dispose()` inside `_ComposerState.dispose()`.

---

## Deployed URL

🔗 **[https://chat-scroll-2026-abc123.web.app](https://chat-scroll-2026-abc123.web.app)**

---

## Screen Recording



The recording demonstrates:
1. ✅ Auto-scroll follows streaming content to the bottom automatically
2. ✅ Manual scroll upward pauses auto-scroll immediately
3. ✅ Returning to the bottom resumes auto-scroll
4. ✅ Stop button halts the stream instantly
5. ✅ Composer is positioned correctly at the bottom with visible hint text
