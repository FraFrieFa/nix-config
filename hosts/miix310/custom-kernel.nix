{ lib, pkgs, ... }:

# Hand-crafted kernel config for Lenovo MIIX 310 — Intel Atom x5-Z8350 (Cherry Trail / Airmont)
# Hardware inventory (fixed):
#   CPU     : Atom x5-Z8350, 4 cores, no hyperthreading, Airmont/Silvermont ISA
#   GPU     : Intel i915 [8086:22b0], DSI-1 panel (rotated 90°)
#   Storage : eMMC HCG8e (sdhci_acpi, mmc2), SD slot (mmc0)
#   WiFi    : RTL8723BS SDIO (mmc1, vendor 0x024c/0xb723)
#   BT      : Broadcom BCM UART (BCM2E1A/BCM2E3A/BCM2E64)
#   Audio   : rt5645 (I2C), Intel SST/SOF cht-bsw, HDMI LPE
#   Touch   : FocalTech FTSC1000 (I2C-HID, ACPI)
#   IMU     : Kionix KX023 accel (KIOX000A), AKM AK09911C mag
#   Camera  : OV2680 + AtomISP2 (non-functional in mainline)
#   PMIC    : X-Powers AXP288 (battery gauge, extcon)
#   I2C     : 7× DesignWare (808622C1:00-06)
#   UART    : 3× DesignWare 8250 (8086228E:00-02)
#   SPI     : Intel platform + PXA2xx (NOR flash)
#   DMA     : DesignWare DMAC
#   USB     : xHCI [8086:22b5]
#   Thermal : int3400/int3403/int3406, intel_soc_dts_iosf
#   MEI/TXE : Intel TXE
#   TPM     : MSFT0101 (TPM 2.0 CRB)

let
  baseKernel = pkgs.linuxPackages.kernel;
  kernelPackages = pkgs.linuxPackages_custom {
    inherit (baseKernel) version src modDirVersion;
    configfile = ./kernel-config-6.18.34;
    allowImportFromDerivation = false;
  };
in
{
  boot.kernelPackages = lib.mkForce (
    kernelPackages.extend (_: super: {
      kernel = super.kernel.overrideAttrs (old: {
        passthru = (old.passthru or {}) // {
          features = (old.passthru.features or {}) // {
            efiBootStub = true;
          };
        };
      });
    })
  );
}
