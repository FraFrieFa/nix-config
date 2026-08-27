{ pkgs, ... }:

let
  hs80-max-battery = pkgs.callPackage ../pkgs/hs80-max-battery { };
in
{
  environment.systemPackages = [ hs80-max-battery ];

  # Limit access to this exact receiver; "uaccess" grants the active local
  # desktop session access without making the HID device world-writable.
  services.udev.extraRules = ''
    SUBSYSTEM=="hidraw", ENV{ID_VENDOR_ID}=="1b1c", ENV{ID_MODEL_ID}=="0a97", ENV{ID_USB_INTERFACE_NUM}=="04", TAG+="uaccess"
  '';

  environment.etc."xdg/autostart/hs80-max-tray.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=HS80 MAX Battery
    Comment=Battery and microphone status for the Corsair HS80 MAX
    Exec=${hs80-max-battery}/bin/hs80-max-tray
    Icon=audio-headset
    Terminal=false
    OnlyShowIn=KDE;
    X-KDE-autostart-after=panel
  '';
}
