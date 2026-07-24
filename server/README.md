# LemonShooter dedicated server

The dedicated server hosts authoritative 16-combatant matches without creating
a local player, HUD, voice session, or input devices.

## Downloads and source

Download the current prerelease for:

- [Linux x86_64](https://github.com/lkuich/LemonShooterServer/releases/download/v0.1.1/LemonShooter-Server-Linux-x86_64.zip)
- [Windows x86_64](https://github.com/lkuich/LemonShooterServer/releases/download/v0.1.1/LemonShooter-Server-Windows-x86_64.zip)
- [macOS universal](https://github.com/lkuich/LemonShooterServer/releases/download/v0.1.1/LemonShooter-Server-macOS-Universal.zip)

Release notes and asset checksums are on the
[v0.1.1 release page](https://github.com/lkuich/LemonShooterServer/releases/tag/v0.1.1).

## Quick start

Extract the archive and run the launcher from its root:

```sh
./run-server.sh
```

It selects the macOS or Linux binary, loads the adjacent `server.cfg`, and
forwards extra arguments:

```sh
./run-server.sh --port 7100 --private
```

To use another configuration, pass it explicitly:

```sh
./run-server.sh --server-config /path/to/community-server.cfg
```

Windows operators should run
`.\LemonShooterServer.exe --server-config server.cfg` from PowerShell.

The macOS archive is universal and runs natively on Apple Silicon and Intel
Macs. Prerelease builds are ad-hoc signed but not notarized, so first launch may
require Control-clicking the app and choosing **Open**, or approving it under
**System Settings → Privacy & Security**. Frictionless Gatekeeper approval
requires a Developer ID signature and Apple notarization.

Forward the configured gameplay port as **UDP only** (UDP 7000 by default).
UDP 7001 is optional LAN discovery and should not be exposed to the internet.
Public-directory heartbeats and community-pack downloads are outbound HTTPS.

Command-line `--port`, `--name`, and `--private` values override `server.cfg`.

## Rotation and population

`rotation` is ordered. Each entry accepts `map`, `mode`, `score_limit`,
`time_limit`, `bot_count`, `bot_difficulty`, `powerup_spawn_rate`, and
`koth_variant`. Bots never satisfy `minimum_humans`. A populated lobby starts
after `countdown_seconds`; completed matches show results for `result_seconds`
and advance the rotation. If every human leaves during a match, the server waits
30 seconds, returns to the lobby, and retains the current rotation entry.

Community packs are fixed for the process lifetime. Each pack descriptor must
include its HTTPS URL, exact SHA-256, byte size, display name, author, version,
and local `path` (or already exist in the verified cache). Restart the server to
change the pack set.

Logs are written to standard output. Capture them with systemd, Docker, a game
panel, or PowerShell transcript tooling.

## Troubleshooting

- A bind error means the UDP port is already used or unavailable.
- Protocol errors mean client and server builds differ; protocol 29 is required.
- Content-set errors require the exact advertised pack hashes.
- Public listing requires a valid directory URL and outbound HTTPS.
- Do not expose a remote shell, admin port, or UDP 7001.
- If macOS reports a prerelease as damaged, repair that extracted copy with
  `codesign --force --deep --sign - LemonShooter.app`, then approve it using the
  steps above. Only do this for an archive whose SHA-256 matches the release.
