# Contributing

Thanks for your interest! This is a small, focused flake — contributions that keep
it small and focused are the most welcome.

## Dev loop

```sh
nix flake check                         # eval + build the module check + treefmt
nix fmt                                 # treefmt: nixfmt + deadnix + statix
nix build .#checks.x86_64-linux.module-evaluates
nix eval  .#packages.aarch64-darwin.firmware-plant.drvPath
```

## Guidelines

- Keep the NixOS module dependency-free (only `config`/`lib`).
- No identity, host names, or secret **values** in code — this repo plants secrets
  the operator supplies out-of-band; it must never embed one.
- New options need a `description` and, where useful, an `example`.
- Update `README.md` and `examples/` for user-facing changes.
- One logical change per PR; CI (format + eval check) must pass.

## Reporting

Open an issue with your NixOS version, device/board, and the relevant
`services.firmwareProvisioning` config (redact secret **values**).
