{ lib, pkgs, ... }:
{
  users.users.fabius.extraGroups = lib.mkAfter [ "dialout" ];

  users.users.fabius.packages = with pkgs; [
    ffmpeg
  ];

  services.udev.extraRules = ''                                                                                                                                                                                                                                                                                             
    # Raspberry Pi BCM2708 boot modes, used by rpiboot.                                                                                                                                                                                                                                                                     
    SUBSYSTEM=="usb", ATTR{idVendor}=="0a5c", ATTR{idProduct}=="2763", GROUP:="users", MODE:="0664"                                                                                                                                                                                                                         
    SUBSYSTEM=="usb", ATTR{idVendor}=="0a5c", ATTR{idProduct}=="2764", GROUP:="users", MODE:="0664"                                                                                                                                                                                                                         
    # Rename Pi Zero W USB gadget ethernet to a stable name regardless of port                                                                                                                                                                                                                                              
    SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0525", ATTRS{idProduct}=="a4a2", NAME="usb-signaged"                                                                                                                                                                                                                 
  '';                                                                                                                                                                                                                                                                                                                       
                                                                                                                                                                                                                                                                                                                            
  networking.networkmanager.ensureProfiles.profiles.signaged-pi-gadget = {                                                                                                                                                                                                                                                  
    connection = {
      id = "signaged-pi-gadget";                                                                                                                                                                                                                                                                                            
      type = "ethernet";
      "interface-name" = "usb-signaged";                                                                                                                                                                                                                                                                                    
      autoconnect = true;
    };
    ipv4 = {
      method = "manual";                                                                                                                                                                                                                                                                                                    
      address1 = "10.42.0.1/24";
    };                                                                                                                                                                                                                                                                                                                      
    ipv6.method = "ignore";
  };                                                                                                                                                                                                                                                                                                                        
}
