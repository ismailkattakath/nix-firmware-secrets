> [!IMPORTANT]
> ## Archived 2026-09-12 — this flake now lives inside `kattakath/nix-config`
>
> The code moved to **`modules/features/firmware-secrets/`** in
> [kattakath/nix-config](https://github.com/kattakath/nix-config), as a *capsule*: a
> directory that may not reach outside itself, enforced by the repo's `ast-grep` gate rather
> than by convention.
>
> **Why:** maintaining seven satellite flakes cost seven CI pipelines, seven merge queues and a
> lock-bump dance for every cross-cutting change — for repos with 2 GitHub stars between them.
> The rationale, the four competing architectures that were scored, the adversarial review that
> found three blocking defects, and an honest list of what the collapse gives up are all in
> [`docs/monoflake-capsule-adr.md`](https://github.com/kattakath/nix-config/blob/main/docs/monoflake-capsule-adr.md).
>
> **This repository is read-only.** Its history is preserved here and is the only place it
> exists — the absorption was a plain copy, not a `git subtree`, so `git blame` in nix-config
> stops at the collapse commit and continues here.

# nix-firmware-secrets

[![CI](https://github.com/kattakath/nix-firmware-secrets/actions/workflows/ci.yml/badge.svg)](https://github.com/kattakath/nix-firmware-secrets/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Built with Nix](https://img.shields.io/badge/built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)

**Reflash-safe secrets for headless NixOS devices.** Plant a secret on the device's
FAT *firmware* partition from another machine; a boot-time oneshot copies it into a
root-only `/run` file **before** the consuming service starts. The secret is never
bound to the SSH host key, so a fresh SD/USB flash doesn't lock you out.

> Status: early / beta. Small, focused, and used in production on one Pi.

## The problem it solves

`agenix` and `sops-nix` decrypt at activation using the machine's **SSH host key**.
But re-flashing an SD card **mints a new host key** — so those secrets can no longer
be decrypted, and a headless device (no console) never comes back. The classic
example: a Raspberry Pi whose only remote path is a Cloudflare tunnel whose token
*is* one of those secrets. One reflash and it's bricked-until-console.

The FAT firmware partition is the one thing you can write from another machine
**after** flashing. So: plant the secret there, and let NixOS copy it to `/run` at
boot. No host key involved.

```
[laptop]  flash secret-free image ─► plant token on FAT partition
                                          │
[device boot]  firmware mounted ─► oneshot copies token ─► /run/token (0600)
                                          │
               cloudflared / wpa_supplicant reads /run/token ─► online
```

## Prerequisites

- **Nix** with flakes enabled (`experimental-features = nix-command flakes`).
- **NixOS** on the target device (this ships a NixOS module).
- A device that mounts a FAT *firmware* partition at boot (e.g. a Raspberry Pi's `/boot/firmware`).
- **macOS** (optional) to use the `firmware-plant` companion for planting files onto the card.

## Install

```nix
# flake.nix
{
  inputs.firmware-secrets.url = "github:kattakath/nix-firmware-secrets";

  # in your nixosSystem modules:
  #   firmware-secrets.nixosModules.default
}
```

## Usage

```nix
services.firmwareProvisioning.files.my-token = {
  source     = "my-token";              # basename planted on the FAT partition
  target     = "/run/my-token";         # root-only /run file your service reads
  required   = true;                    # fail the unit if the plant is missing
  before     = [ "my-service.service" ];
  requiredBy = [ "my-service.service" ];
};
```

See [`examples/pi-cloudflared.nix`](examples/pi-cloudflared.nix) for a Cloudflare
tunnel token + Wi-Fi setup.

### Options (`services.firmwareProvisioning`)

| Option | Default | Meaning |
|---|---|---|
| `firmwareDir` | `/boot/firmware` | Mount point of the FAT partition |
| `docsHint` | `""` | Text appended to the "source not found" message |
| `files.<name>.source` | — | Basename planted on the partition |
| `files.<name>.target` | — | Destination `/run` path |
| `files.<name>.mode` | `0600` | Mode of the installed file |
| `files.<name>.required` | `false` | Fail the unit if the plant is absent |
| `files.<name>.postInstall` | `""` | Shell to run after install |
| `files.<name>.{before,requiredBy}` | `[ ]` | systemd `Before=` / `RequiredBy=` on the consuming unit |
| `files.<name>.wantedBy` | `[ "multi-user.target" ]` | systemd `WantedBy=` |

## Planting from macOS

```sh
nix run github:kattakath/nix-firmware-secrets#firmware-plant -- \
  my-token=./my-token wpa_supplicant.conf=./wpa_supplicant.conf
```

Copies each `NAME=localfile` onto the mounted FAT volume (default label `FIRMWARE`;
override with `--volume`). Each `NAME` must match a `files.<x>.source`.

## Security model — read this

- The FAT partition is **world-readable on the card** and unencrypted. Treat a
  planted secret as *exposed to anyone with physical access to the card*.
- The `/run` copy is `0600` root-only, and lives on tmpfs (never the disk).
- This is the right trade-off for *appliance* secrets (tunnel tokens, Wi-Fi PSKs)
  where the alternative is a bricked headless device. It is **not** a replacement
  for `agenix`/`sops-nix` for multi-machine fleets, servers, or high-value secrets.

## When to use something else

| You want… | Use |
|---|---|
| Git-encrypted secrets, multi-machine fleets, servers | [sops-nix](https://github.com/Mic92/sops-nix) / [agenix](https://github.com/ryantm/agenix) |
| Secrets only inside `nix develop` | [agenix-shell](https://github.com/aciceri/agenix-shell) |
| A headless device that gets re-flashed and can't lose network/tunnel | **this** |

## Used in production

See it wired into a real fleet in **[kattakath/nix-config](https://github.com/kattakath/nix-config)** — [`hosts/nixpi.nix`](https://github.com/kattakath/nix-config/blob/main/hosts/nixpi.nix) imports `nixosModules.default` for a headless Raspberry Pi's Cloudflare-tunnel token + Wi-Fi.

## License

MIT © Ismail Kattakath
