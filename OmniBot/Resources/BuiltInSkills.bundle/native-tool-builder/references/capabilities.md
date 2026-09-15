# Native capability composition

Call `native_tool_capabilities` for the authoritative operation/parameter/result catalog. The same Swift registry validates packages and authorizes runtime calls. There is no built-in-only capability path.

## Minimal invocation

```json
{
  "sessionState": {"scan": {}, "copied": {}},
  "capabilities": ["camera", "clipboard"],
  "actions": {
    "scan": [{"type":"invoke","operation":"camera.scanQRCode","result":"scan"}],
    "copy": [{"type":"invoke","operation":"clipboard.copy","arguments":{"text":{"op":"field","args":[{"get":"scan"},"text"]}},"result":"copied"}]
  }
}
```

This is a fragment; add the required package fields/screens. `assets/qr-reader.json` is runnable. Bind a normal button to `scan` and render the result with `text.value`. Scanning returns arbitrary QR text, not just OTP links.

## Families

- `camera.scanQRCode`, `photos.scanQRCode`: standard native acquisition, returns `{text}` after user selection. The package decides how to use or interpret it.
- `files.openText` / `files.openData`: user-selected file up to 1 MB, returns `{handle}`. Handles are scoped to this tool session and disappear on close/lock. `files.readText` decodes a handle to `{text}` up to 32 KB. `files.save` exports a handle using the system destination picker.
- `clipboard.copy`: copies text locally with a 30-second expiration. `dialog.confirm` presents package-provided title/message and returns `{confirmed}`.
- `otp.unlock` / `otp.lock`: control the authenticated OTP vault for this installed tool UUID. `otp.snapshot` is a passive device-time snapshot: `{unlocked, accounts:[{id,name,issuer,code,progress}], message}`. It never returns secret keys.
- `otp.previewImport`: provide either `handle` (TXT containing one otpauth URI per line) or `text` (URI/raw Base32; raw keys also need `name`). Optional issuer/algorithm/digits/period apply to raw keys. It validates the whole batch and keeps pending secrets in host memory, returning only `{accounts:[{id,name,issuer}], message}`. `otp.commitImport` saves the staged batch and skips duplicates; `otp.discardImport` drops it. The package builds the preview and confirmation buttons itself.
- `otp.delete`: accepts an account `id`; precede it with dialog.confirm and use `when` on the returned confirmation.
- `otp.encryptBackup`: password → encrypted file handle; follow with files.save. `otp.previewBackup`: handle + password → staged account preview; follow with the same otp.commitImport UI used for ordinary import.

## Lifetimes and errors

Host calls only run after installation, never from import previews. Active calls originate in user-triggered actions; onRefresh may only call passive operations such as otp.snapshot. A tool can have one active action; system interaction suspends its subsequent steps until completion. User cancellation stops the remaining steps.

Declare all result slots as empty objects in sessionState. Use secureField + sessionBinding for passwords and manual secrets. Clear imported text/passwords with setSession after use. Do not copy session data into initialState or persistent actions. Native handles, pending OTP accounts, passwords and runtime results never enter native_tool_read/list.

See `assets/totp.json` for editable JSON pages, search, progress, QR/TXT import, duplicate preview, confirmation, copy and encrypted backup. Its preinstallation only supplies the JSON package; an Agent-created copy calls the exact same public operations.
