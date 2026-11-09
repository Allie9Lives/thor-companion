# Thor phone keyboard — 0.7.0

## Use

1. On the Thor, open Thor Monitor and scroll to **Phone keyboard**. Enable **Thor Remote Keyboard**, then select it. The keyboard is already enabled on this test device; Gboard was restored as the default after verification.
2. Tap a text field in the Thor app you want to type into. Leave the Thor open and unlocked. A small panel offers **Switch keyboard** to return to Gboard or another keyboard.
3. On iPhone, open Thor Companion → Controls → Open keyboard. If setup status has not refreshed, tap **Check keyboard setup**. Type a draft and tap **Send text**. Backspace, Enter, Tab and arrow buttons act on the Thor's focused editor.

Drafts send on the explicit Send action, not on each iPhone keystroke. Successful complete sends clear the draft. Enter uses the focused app's normal keyboard action (for example Search), or inserts a newline in multiline fields. Apps with custom raw/game input instead of a standard text editor may not accept this keyboard.

## Implementation

Uses Android's InputMethodService/InputConnection commitText API for Unicode, rather than shell `input text` or ASCII keycode conversion: https://developer.android.com/reference/android/inputmethodservice/InputMethodService

RemoteKeyboard is an optional system-bound IME protected by BIND_INPUT_METHOD. There are no exported text-injection broadcasts, clipboard writes, accessibility service, or network text endpoint. Existing authenticated owner-only encrypted BLE control writes carry allowlisted `text` or `key` requests. Existing GATT UUIDs and characteristic order are unchanged. The shell controls helper is not needed for typing.

Text commands contain at most 120 UTF-8 bytes, with each complete JSON write constrained to the protocol's existing 180-byte limit. The companion chunks by Unicode code point and JSON-escaped byte size, sends in order, and checks correlated acknowledgements. Maximum draft is 2,000 code points. Text goes to the current editor without reading its contents. The keyboard must be selected and visible for an editable field; input is rejected while the Thor is locked/asleep or no keyboard view is active.

Text and key requests are non-idempotent. They are never automatically retried or replayed after reconnect. An uncertain acknowledgement stops the batch and tells the user to check the Thor before sending again. Partial sends cannot be rolled back. Same-request deduplication is shared with existing controls. Drafts live only in the phone page's memory; host telemetry, readback and diagnostics do not include text.

## Verification

- Java validation tests: Unicode, byte limits, invalid surrogates/control characters, literal shell metacharacters, key allowlist.
- Flutter suite: 54 passed, including escaped/multibyte packet sizing, ordered chunks, unique request IDs, uncertain acknowledgement stopping without replay, background/disconnected rejection and key validation.
- Real Thor instrumentation: 7 checks passed against an actual focused Android EditText: Unicode including emoji/Chinese/accents, duplicate ID suppression, emoji backspace, selection replacement, cursor movement, newline Enter, rejection with the input view closed.
- Test input absent from host diagnostics. Temporary instrumentation APK uninstalled. Gboard default restored. Normal monitoring resumed from the host UI with the prior continuous-mode choice.
- Native host and iPhone 0.7.0 installed; Android companion APK, development IPA (including battery extension), and source archives rebuilt.
