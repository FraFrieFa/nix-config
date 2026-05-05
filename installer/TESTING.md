# Installer testing

Do not test installer partitioning on a real disk until the unit and VM tests pass.

## Fast checks

Run the Rust unit tests through Nix:

```sh
nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#checks.x86_64-linux.installer-unit
```

Run all flake checks:

```sh
nix --extra-experimental-features nix-command --extra-experimental-features flakes flake check
```

Build the installer system closure without creating an ISO:

```sh
nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#nixosConfigurations.installer.config.system.build.toplevel --no-link
```

Build the ISO:

```sh
nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#installer
```

## Local development shell

Use the installer dev shell for direct `cargo` commands and VM tooling:

```sh
nix --extra-experimental-features nix-command --extra-experimental-features flakes develop .#installer
cargo test
```

## VM safety test

Create a disposable disk with an existing partition and empty space:

```sh
qemu-img create -f qcow2 /tmp/nixos-installer-test.qcow2 80G
```

Boot the installer ISO with that disk attached. The helper uses user-mode networking, curses display, and a QMP socket at `/tmp/nixos-installer-test.qmp`:

```sh
installer/scripts/qemu-run
```

Set `INSTALLER_VM_VNC=:7` if you want VNC instead of curses. QEMU user-mode networking gives the guest outbound internet through the host without root privileges. The helper also forwards host port `2222` to guest port `22`.

For agent debugging, run QEMU inside a detached tmux pane and capture the current visible screen as plain text:

```sh
installer/scripts/qemu-tmux
installer/scripts/qemu-screen
installer/scripts/qemu-screen --trim
```

`qemu-screen` uses `tmux capture-pane`, so it returns the screen contents without terminal escape sequences. `--trim` crops blank outer rows/columns and trailing whitespace. Run it from inside the dev shell to avoid wrapping the capture in extra `nix develop` output.

Inside the VM, create a small existing partition first, then leave the rest empty. The installer should only offer the empty region. After running the partition step, verify with `lsblk`, `blkid`, or `parted` that:

- the original partition still exists
- one new EFI partition was created
- one new root partition was created
- only the two new partitions were formatted

## VM monitor controls

Send a key:

```sh
installer/scripts/qemu-sendkey ret
installer/scripts/qemu-sendkey down
installer/scripts/qemu-sendkey tab
installer/scripts/qemu-sendkey ctrl-alt-f2
```

Send a raw QMP command:

```sh
installer/scripts/qemu-qmp '{"execute":"query-status"}'
```

Use QMP for scripted tests.

Only move to real hardware after this works repeatedly in a VM.
