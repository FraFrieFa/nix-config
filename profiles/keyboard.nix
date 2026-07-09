{ config, lib, ... }:
let
  repeat = config.local.keyboard.repeat;
in
{
  options.local.keyboard.repeat = {
    delay = lib.mkOption {
      type = lib.types.ints.positive;
      default = 250;
      description = "Keyboard repeat delay in milliseconds.";
    };

    rate = lib.mkOption {
      type = lib.types.ints.positive;
      default = 40;
      description = "Keyboard repeat rate in repeats per second.";
    };
  };

  config.services.xserver = {
    autoRepeatDelay = lib.mkDefault repeat.delay;
    autoRepeatInterval = lib.mkDefault (1000 / repeat.rate);
  };
}
