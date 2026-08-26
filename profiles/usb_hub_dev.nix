{ ... }:
{
  # CH32X035 factory ISP bootloader, so `wchisp flash` works without sudo.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="55e0", GROUP="users", MODE="0660"
  '';
}
