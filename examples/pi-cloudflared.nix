# Example: a headless Raspberry Pi whose Cloudflare tunnel token AND Wi-Fi config
# are planted on the FAT firmware partition and copied to /run at boot -- so a
# fresh SD flash (new SSH host key) still comes up on the network + tunnel without
# a console. Import firmware-secrets' nixosModule and this snippet.
_: {
  services.firmwareProvisioning = {
    firmwareDir = "/boot/firmware"; # Raspberry Pi default
    docsHint = "Plant with: nix run github:kattakath/nix-firmware-secrets#firmware-plant -- cloudflared-token=./token wpa_supplicant.conf=./wpa_supplicant.conf";

    files = {
      # Required: the tunnel connector token -> /run, ordered before cloudflared.
      cloudflared-token = {
        source = "cloudflared-token";
        target = "/run/cloudflared-token";
        required = true;
        before = [ "cloudflared-connector.service" ];
        requiredBy = [ "cloudflared-connector.service" ];
      };
      # Optional: Wi-Fi creds -> where wpa_supplicant reads them.
      "wpa_supplicant.conf" = {
        source = "wpa_supplicant.conf";
        target = "/run/wpa_supplicant/wpa_supplicant-wlan0.conf";
        required = false;
        postInstall = "rfkill unblock wifi || true";
        before = [ "wpa_supplicant-wlan0.service" ];
      };
    };
  };

  # Your consumer keeps its own unit; it just reads the /run file, e.g.:
  # systemd.services.cloudflared-connector.serviceConfig.EnvironmentFile = "/run/cloudflared-token";
}
