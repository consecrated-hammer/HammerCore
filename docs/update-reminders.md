# Stable release update reminders

Each private HammerCore copy can discover a newer installed release of its own
addon from hidden guild, home party/raid and instance-group messages. There is
no HTTP/CurseForge query and no claim that this finds the latest published file.
Only the peer's actual installed version is announced, never a cached version.

Visibility > Updates > Update reminders defaults on and is independent of the
startup line and What's new. Off stops this module's listening, announcements,
replies and notices, including queued callbacks. It keeps the recent cache for
re-enabling. The setting and cache use the addon's existing HC.State scope.

The wire protocol is `CHVer1` plus `addonFolder<TAB>major.minor.patch`. Both local
and incoming versions must be plain stable versions with three numeric parts,
no leading zeros or suffixes, at most four digits per part. Dev/alpha/beta/test
copies do not register this module's prefix or events, send messages, update the
cache, or show notices. Invalid incoming versions are ignored before cache or
reply handling. Compare components numerically.

Each addon shows at most one gold-prefixed chat line per login, even if toggled
or several higher versions are heard. A recent newer release can remind again
on a later login until updated. The cache stores only version and local receipt
time, expires after 72 hours, and drops invalid/future/stale or no-longer-newer
records. No names, GUIDs, chat content or roster details are retained.

Login announcements and live notices wait briefly. Roster/guild events only
announce changed channel membership/count; unchanged roster/rank churn is silent. Sends/replies
are limited to once per addon/channel per 30 seconds. Random delayed replies
to older copies are cancelled if another equal/newer copy answers first.
Deferred callbacks recheck setting, generation and current channel membership.
An API rejection gets at most one delayed retry; modern enum success and
duplicate-prefix results are recognised alongside legacy boolean/void returns.
Modern C_ChatInfo and legacy globals are supported; missing APIs fail quietly.
A missing timer falls back to immediate operations with the send throttle.

Staged development builds intentionally do not participate. The stable paths,
cache across logins, private-copy isolation, channel routing and opt-out are
covered by `tests/test_update_reminders.lua` with simulated clocks/transport.
Actual two-client delivery and chat rendering remain native acceptance checks.

The 72-hour expiry is measured from the last matching observation, not the first.
Continued stable observations legitimately keep a newer-than-installed release
recent. The shared core snapshot is 0.5.5; 0.5.4 is reserved for Speedster's
separate native-presentation pilot. Exact commit pins remain the authority.
API result contracts were checked against the client's generated
[ChatInfo documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua)
and [Chat constants](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatConstantsDocumentation.lua).
