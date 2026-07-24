# Contributing

Contributions are welcome under the repository's AGPL-3.0 license.

Before submitting a change:

```sh
godot --headless --path . --editor --quit
./build.sh linux --debug
```

Keep gameplay mutations host-authoritative. When changing an RPC signature,
snapshot, lobby configuration, or compatibility contract, update every sender
and receiver and bump `NetworkSession.PROTOCOL_VERSION` when old and new builds
must not interoperate.

Do not add client-only models, textures, sounds, UI, signing credentials, or
private service credentials to this repository.
