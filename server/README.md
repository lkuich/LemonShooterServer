# LemonShooter dedicated server

The dedicated server hosts authoritative 16-combatant matches without creating
a local player, HUD, voice session, or input devices.

## Quick start

Keep the executable, `.pck`, and `server.cfg` in the same directory, then run:

```sh
./LemonShooterServer.x86_64 --server-config server.cfg
```

On Windows:

```powershell
.\LemonShooterServer.exe --server-config server.cfg
```

On macOS:

```sh
./LemonShooter.app/Contents/MacOS/LemonShooter --server-config server.cfg
```

The macOS archive is universal and runs natively on Apple Silicon and Intel
Macs. Public downloads should be Developer ID signed and notarized; local
unsigned builds may require explicit approval in macOS Privacy & Security.

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
