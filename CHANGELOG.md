# Release notes

## 0.3.13 — Installer security correction

The optional source-archive installer previously wrote the `--replace` layout through a predictable temporary pathname. A pre-existing symbolic link at that path could redirect the write into another user-writable file. Its rollback also followed a symbolic link at `shell.json`.

- Both writes now use the same atomic transaction: a random same-directory temporary file opened exclusively with no-follow semantics, checked file and directory descriptors, file flush/fsync, descriptor-relative replacement, and directory fsync.
- The installer rejects a symlinked, foreign-owned, or group/world-writable destination directory. Replacement configuration files are owner-readable/writable only (`0600`).
- Ten installer regression tests cover the two reported paths, temporary-name collisions, hard links, directory/file substitution, failure cleanup, and durability ordering. These run in temporary fixtures without changing the desktop.

Reported during the [Omarchy marketplace review](https://github.com/omacom/omarchy-plugin-marketplace/issues/6083#issuecomment-5654851752). The prayer-time UI and reminder behaviour are unchanged.

## 0.3.12 — First public beta

Salah brings prayer times, a live Earth clock, and optional reminders to Omarchy 4.

- The compact mosque turns yellow before Fajr and Dhuhr, red before Asr, Maghrib and Isha, and green after each prayer. Reminder windows are configurable; clicking dismisses the current reminder.
- The Earth clock shows daylight, prayer intervals, a sun-height timeline, upcoming prayer times, and an optional subtle Qibla guide ending at Makkah.
- Explore the day using the dial or timeline without changing live reminders.
- Automatic location, manual coordinates/city selection, and offline timetable imports are supported. Available cached dates remain usable during provider outages.
- Qibla, automatic location, and bar countdown controls save immediately. Choose a countdown before prayer, after prayer, or both.
- Optional desktop notifications and original soft chimes are included. Audio starts off. English, Turkish, and Arabic interface text is available.

### Compatibility and validation

Developed and tested on Omarchy 4.0.3 with Qt 6.11.2. Requires Python 3.10+ with timezone data and `notify-send`; optional audio uses `pw-play`. No pip or npm runtime packages are needed.

The release has 70 passing automated tests, native QML integration checks, a GPU shader and software fallback, and GitHub CI for reminder, Qibla, solar, and provider logic.

### Beta limitations

- AlAdhan is the implemented online prayer-time provider. Its Turkey/Diyanet preset is an experimental calculation method; direct official Diyanet timetable integration is not included.
- Optional discouraged-prayer bands are labelled estimates, with prayer-specific explanations. Compare the selected timetable and method with your local community.
- IP-based location can identify a VPN or network exit city. Manual location and offline imports are available.
- Some calculation-method and diagnostic text remains English. Other desktop shells are not supported.

See the [README](README.md) for installation, privacy, configuration, and removal.
