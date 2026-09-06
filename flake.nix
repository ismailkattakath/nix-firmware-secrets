{
  description = "Plant operator secrets on a device's FAT firmware partition and have NixOS copy them into root-only /run at boot. Reflash-safe: never bound to a rotating SSH host key.";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Public read-only binary cache for this flake's build outputs (CI pushes here).
  nixConfig = {
    extra-substituters = [ "https://kattakath.cachix.org" ];
    extra-trusted-public-keys = [
      "kattakath.cachix.org-1:y/w6wnb4ZArdlbfWJ82c81uCXeYgG/sGDUYCszavmEw="
    ];
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.treefmt-nix.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      flake = {
        # The reusable NixOS module (system-agnostic).
        nixosModules.firmwareProvisioning = ./modules/firmware-provisioning.nix;
        nixosModules.default = self.nixosModules.firmwareProvisioning;
      };

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        {
          # treefmt owns `nix fmt` and contributes its own `checks.treefmt`, so the
          # formatter comes from THIS flake's lock -- not from whatever the CI
          # runner's registry happens to resolve `nixpkgs#nixfmt-rfc-style` to.
          # upstream option treefmt-nix.flakeModule exists -> using it
          # (flake-module.nix:74 sets `checks.treefmt`, :76 sets `formatter` via
          # mkDefault -- which is why the bare `formatter = pkgs.nixfmt-rfc-style`
          # that used to sit here would have silently won, and had to go).
          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
            programs.deadnix.enable = true;
            programs.statix.enable = true;
          };

          # macOS companion: plant files onto the mounted FAT volume. Darwin-only.
          packages = pkgs.lib.optionalAttrs (system == "aarch64-darwin") (
            let
              firmware-plant = pkgs.callPackage ./apps/firmware-plant.nix { };
            in
            {
              inherit firmware-plant;
              default = firmware-plant;
            }
          );
          apps = pkgs.lib.optionalAttrs (system == "aarch64-darwin") (
            let
              # The package built above, not a second callPackage of the same
              # file: two call sites are two chances for the app and the package
              # to drift apart.
              app = {
                type = "app";
                program = "${config.packages.firmware-plant}/bin/firmware-plant";
              };
            in
            {
              firmware-plant = app;
              default = app;
            }
          );

          # Eval check: the module produces the expected boot oneshot with the right
          # ordering + mount gate (builds a tiny derivation only if all assertions
          # hold). Linux only -- `lib.nixosSystem` needs the flake-level nixpkgs.lib
          # (NOT pkgs.lib, which is the plain stdlib without it), so it's referenced
          # here via closure over the outer `nixpkgs` input, not a perSystem arg.
          checks = pkgs.lib.optionalAttrs (system != "aarch64-darwin") (
            let
              sys = nixpkgs.lib.nixosSystem {
                inherit system;
                modules = [
                  self.nixosModules.default
                  (_: {
                    boot.loader.grub.enable = false;
                    fileSystems."/" = {
                      device = "/dev/sda1";
                      fsType = "ext4";
                    };
                    system.stateVersion = "24.05";
                    services.firmwareProvisioning = {
                      docsHint = "See RUNBOOK.md.";
                      files.demo-token = {
                        source = "demo-token";
                        target = "/run/demo-token";
                        required = true;
                        before = [ "demo.service" ];
                        requiredBy = [ "demo.service" ];
                      };
                    };
                  })
                ];
              };
              unit = sys.config.systemd.services."firmware-file-demo-token";
            in
            {
              module-evaluates = pkgs.runCommand "firmware-provisioning-eval" { } ''
                test "${unit.serviceConfig.Type}" = "oneshot"
                test "${unit.unitConfig.RequiresMountsFor}" = "/boot/firmware"
                test "${pkgs.lib.elemAt unit.before 0}" = "demo.service"
                echo ok > "$out"
              '';
            }
          );
        };
    };
}
