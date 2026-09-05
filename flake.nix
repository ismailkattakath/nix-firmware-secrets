{
  description = "Plant operator secrets on a device's FAT firmware partition and have NixOS copy them into root-only /run at boot. Reflash-safe: never bound to a rotating SSH host key.";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
          formatter = pkgs.nixfmt-rfc-style;

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
                  (
                    { ... }:
                    {
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
                    }
                  )
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
