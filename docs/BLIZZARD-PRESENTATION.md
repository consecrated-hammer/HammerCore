# Blizzard presentation

`presentation = "blizzard"` in `HC:Init` opts one consumer into the complete
native-artwork preview. Other consumers retain their existing theme. This is a
build capability, not a saved preference or a public theme selector. Theme.lua
resolves it after the consumer's database exists, including frames created
before `HC:Start`, and fixes it for the session. Saved `hammerCore.theme` is
preserved. Diagnostics report both values; the hidden theme command cannot
claim to change the fixed preview.

## Artwork and geometry

`Theme.NATIVE` is the resource manifest. It uses the client's dialog background
and border, tooltip inset/background, quest selection highlight, checkbox tick,
chat scroll-down arrow, slider thumb, scrollbar knob and status-bar texture.
Native close controls use `UIPanelCloseButton`; ordinary actions use
`UIPanelButtonTemplate`. Secure quiz sharing keeps its secure template and uses
panel button textures without inheriting scripts. Binding icons use quickslot
borders with native square highlight and pressed art. No Blizzard-owned frames
or global tooltip/menu appearance is altered.

Outer frames have 32px border art and 11px backdrop insets. Settings children
are inset 12px so their backgrounds do not cover the outer border. The native
settings window gets 40px additional width to retain its useful viewport.
Nested inset borders use 8px art and 3px insets; checkboxes are 22px, vertical
scrollbars 16px with 16x24 thumbs, horizontal slider thumbs 28px. Native footer
links use text links. Alternating modern stripes, watermark, fades and vertical
selection accents are hidden; headings use the native gold palette. Input and
menu behaviour remains in the existing widget factories.

Checkboxes deliberately remain ordinary Buttons with art and manual checked
state: inheriting an auto-toggling CheckButton would execute existing handlers
twice. Popup dismissal retains the existing click-catcher and owner-hide behaviour;
popups are not added to the global Escape list, which would close settings
along with a menu. Tile icon skinning changes only art, without replacing
secure scripts. The key-capture scrim remains a neutral translucent dimming
overlay behind the native dialog, without replacing gameplay with texture art.

These paths are the source manifest, not evidence of in-client texture
rendering. The Forever native visual review must check every artwork/state,
control size, text contrast and scale 0.7–1.3. Headless fixtures cannot prove it.

## Private native update notices

Native copies never register their sections or renderer in
`ConsecratedHammerWhatsNew`. Their automatic and manual notices use their own
native window. Modern copies keep their combined notice and renderer.

Scheduling extends the existing `ConsecratedHammerWelcome` open/queue/busy
protocol. A native request owns one busy claim and records it under the
additive `nativeNotices` key. Actual Welcome claims take precedence, including
welcomes waiting to open. Additional native notices queue behind an open owner.
The claim is released on close, opt-out or failure; seen callbacks run only
after a successful showing. A manual request replaces its own pending automatic
request, leaving other addons' entries alone. Failed renders retry once and
then release with a diagnostic message; later manual requests can recover.

Older aggregate windows expose no open flag. Their visible named escape frames
ending in WhatsNew, with a sections table, are observed read-only. A pending
native request retries after the old window closes. There are no idle polls;
retry callbacks exist only while delivery is pending. Older copies do not need
a vendor update. Fresh-install suppression, opt-out and combat deferral remain.

`tests/test_native_presentation.lua` covers constructor contracts, queue/seen
lifecycle, actual Welcome scheduling, both registration orders and render
failure. Set `HAMMERCORE_PREVIOUS_SOURCE` to a previous released src directory
to exercise native notices alongside that implementation; default tests remain
portable and use the current Modern path.
