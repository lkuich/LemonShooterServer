# LemonShooter dedicated server

This is the open-source, authoritative dedicated server for LemonShooter. It
contains the server lifecycle, network protocol, match simulation, AI, physics,
and collision-only versions of the core maps. Client UI, rendering assets,
audio, and proprietary game content are intentionally not part of this
repository.

The server is built with Godot 4.7 and licensed under the GNU Affero General
Public License v3.0. The game client remains a separate project and license.

## Download v0.1.1

- [Linux x86_64](https://github.com/lkuich/LemonShooterServer/releases/download/v0.1.1/LemonShooter-Server-Linux-x86_64.zip)
- [Windows x86_64](https://github.com/lkuich/LemonShooterServer/releases/download/v0.1.1/LemonShooter-Server-Windows-x86_64.zip)
- [macOS universal](https://github.com/lkuich/LemonShooterServer/releases/download/v0.1.1/LemonShooter-Server-macOS-Universal.zip)

See the [v0.1.1 release notes](https://github.com/lkuich/LemonShooterServer/releases/tag/v0.1.1)
for checksums, compatibility details, and the ad-hoc-signed macOS build notice.

## Run a release

Keep the executable, `.pck`, and `server.cfg` together. Then run:

```sh
./LemonShooterServer.x86_64 --server-config server.cfg
```

On Windows use `LemonShooterServer.exe`; on macOS use
`LemonShooter.app/Contents/MacOS/LemonShooter`. Forward UDP 7000 by default.
See [server/README.md](server/README.md) for configuration and hosting details.

## Build locally

Install Godot 4.7 and its export templates, then:

```sh
./build.sh
./build.sh macos --debug
```

Every build loads the packaged `.pck` and constructs a headless match on all
core maps. Script errors, missing resources, or a failed map boot stop the
build.

## Releases

Pushing a `v*` tag runs the release workflow for Linux, Windows, and universal
macOS, then opens a draft GitHub release with all three archives. Manual
workflow runs build the same artifacts without publishing a release.

macOS CI artifacts receive a valid ad-hoc signature and are verified on a macOS
runner. Frictionless Gatekeeper approval still requires a Developer ID
certificate and Apple notarization.

## Contributing

Changes to RPC signatures, snapshots, serialized config, or content identity
may require a multiplayer protocol bump. Please run the parser and a debug
server build before opening a pull request.
