# Blizzard presentation

`presentation = "blizzard"` in `HC:Init` opts one consumer into the complete
native-artwork preview. Other consumers retain their existing theme. This is a
build capability, not a saved preference or a public theme selector. Theme.lua
resolves it after the consumer's database exists, including frames created
before `HC:Start`, and fixes it for the session. Saved `hammerCore.theme` is
preserved. Diagnostics report both values; the hidden theme command cannot
claim to change the fixed preview.

## Artwork and geometry

`Theme.NATIVE` and `Theme.RaidBorder` are the resource manifest. The owner’s
reference is the compact raid/Party panel: `UI-Background-Rock` provides the
stone interior, and the eight `Interface\RaidFrame\RaidPanel-*` pieces provide
its bronze surround. Every non-transparent surface has an opaque base below
the client texture, so texture alpha cannot show the game world through it.
Title bars use the client’s marble texture in a warm bronze tone; inset fields
use the dark native dialog background and bronze-tinted inset borders.

The native settings window is 860x660. Its pages are horizontal
`PanelTopTabButtonTemplate` tabs, with proper active/inactive art and extra room
for the unread marker. Owned show/display callbacks preserve sizing and wrap
extra pages into additional rows. Child controls sit inside a 16px inset; the
border stays on the parent artwork layer. The side rail and redundant one-page subtab are absent.
The gold title/brand and stock window-scale slider sit in a compact title bar.
Descriptions wrap and reserve their measured height. Footer links remain text
links, and the read-only macro well has a minimum 64px height and a small game
font. Existing page names, search registration and callbacks are preserved.

Native close controls use UIPanelCloseButton; actions use UIPanelButtonTemplate.
Settings/header horizontal sliders use UISliderTemplate, its native groove and
32px thumb, with an art-only fallback for headless fixtures. Vertical scrollbars
remain 16px with a native groove. Checkboxes are 22px. Secure quiz sharing retains its secure template
and adds panel art without inheriting click scripts. Native binding pages use matching, top-aligned framed columns with equal heights
and matching heading/content insets; wrapped hints reserve shared vertical space.
Binding icons use native
quickslot borders, square highlights and pressed art. Selected/wrong states use
native highlight art and label colours. No Blizzard-owned frame is reskinned.

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
Native selection/quiz verdicts use a quest-highlight overlay and label colour,
without tinting frame border art. Neutral states clear both.

The claim is released on close, opt-out or failure; seen callbacks run only
after a successful showing. A manual request replaces its own pending automatic
request and inherits that request’s seen callback, leaving other addons’ entries
alone. Standalone manual views do not advance the automatic seen record.
A repeated Show raises an already-visible window; a distinct request deferred
by combat survives closing that prior window. Failed renders retry once and
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
