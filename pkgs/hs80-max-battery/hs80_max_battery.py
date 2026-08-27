#!/usr/bin/env python3
"""Inspect passive HID reports from a Corsair HS80 MAX wireless receiver."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path

USB_VENDOR = "1b1c"
USB_PRODUCT = "0a97"
RECEIVER_ENDPOINT = 0x08
HEADSET_ENDPOINT = 0x09


@dataclass(frozen=True)
class HidrawDevice:
    path: Path
    sysfs: Path
    report_size: int


@dataclass(frozen=True)
class HeadsetStatus:
    connected: bool
    battery: float | None = None
    microphone_muted: bool | None = None
    charging: bool | None = None
    raw: str | None = None

    def as_dict(self) -> dict[str, object]:
        return {
            "connected": self.connected,
            "battery": self.battery,
            "microphone_muted": self.microphone_muted,
            "charging": self.charging,
        }


def _read_text(path: Path) -> str:
    try:
        return path.read_text().strip().lower()
    except OSError:
        return ""


def _usb_parent(device: Path) -> Path | None:
    current = device.resolve()
    for parent in (current, *current.parents):
        if (parent / "idVendor").exists() and (parent / "idProduct").exists():
            return parent
    return None


def find_receivers() -> list[HidrawDevice]:
    found: list[HidrawDevice] = []
    for entry in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
        device = entry / "device"
        usb = _usb_parent(device)
        if usb is None:
            continue
        if _read_text(usb / "idVendor") != USB_VENDOR:
            continue
        if _read_text(usb / "idProduct") != USB_PRODUCT:
            continue
        try:
            descriptor = (device / "report_descriptor").read_bytes()
        except OSError:
            descriptor = b""
        # The HS80 MAX vendor interface advertises 63-byte payloads. Including
        # the report ID, reads are 64 bytes. The media-control interface does not.
        report_size = 64 if b"\x95\x3f" in descriptor else 0
        found.append(HidrawDevice(Path("/dev") / entry.name, entry, report_size))
    return found


def v2_request(endpoint: int, command: int) -> bytes:
    """Build the 65-byte Corsair Wireless V2 HID message used by HeadsetControl."""
    request = bytearray(65)
    request[:5] = bytes([0x00, 0x02, endpoint, 0x02, command])
    return bytes(request)


def read_report(fd: int, timeout: float) -> bytes | None:
    ready, _, _ = __import__("select").select([fd], [], [], timeout)
    if not ready:
        return None
    return os.read(fd, 64)


def flush_reports(fd: int, max_reports: int = 64, max_seconds: float = 0.1) -> int:
    """Drain stale reports without allowing a noisy device to loop forever."""
    deadline, drained = time.monotonic() + max_seconds, 0
    while drained < max_reports and time.monotonic() < deadline:
        if read_report(fd, min(0.005, max(0, deadline - time.monotonic()))) is None:
            break
        drained += 1
    return drained


def vendor_device(devices: list[HidrawDevice]) -> HidrawDevice:
    device = next((item for item in devices if item.report_size == 64), None)
    if device is None:
        raise RuntimeError("HS80 MAX vendor interface not found")
    return device


def wake_device(fd: int) -> bool:
    os.write(fd, v2_request(RECEIVER_ENDPOINT, 0x13))
    os.write(fd, v2_request(RECEIVER_ENDPOINT, 0x12))
    flush_reports(fd)
    os.write(fd, v2_request(HEADSET_ENDPOINT, 0x12))
    return read_report(fd, 1.0) is not None


def initialize_device(fd: int) -> bool:
    """Enter software mode, as required for changing the idle timeout."""
    def control(endpoint: int, command: int, payload: bytes = b"") -> bytes:
        request = bytearray(v2_request(endpoint, command))
        request[3] = 0x01
        request[5:5 + len(payload)] = payload
        return bytes(request)

    os.write(fd, v2_request(RECEIVER_ENDPOINT, 0x13))
    os.write(fd, control(RECEIVER_ENDPOINT, 0x03, b"\x00\x02"))
    os.write(fd, v2_request(RECEIVER_ENDPOINT, 0x12))
    os.write(fd, control(HEADSET_ENDPOINT, 0x03, b"\x00\x02"))
    flush_reports(fd)
    os.write(fd, v2_request(HEADSET_ENDPOINT, 0x12))
    return read_report(fd, 1.0) is not None


def get_status(devices: list[HidrawDevice]) -> HeadsetStatus:
    device = vendor_device(devices)
    fd = os.open(device.path, os.O_RDWR)
    try:
        if not wake_device(fd):
            return HeadsetStatus(connected=False)
        flush_reports(fd)
        battery_response = None
        battery = None
        for _ in range(4):
            os.write(fd, v2_request(HEADSET_ENDPOINT, 0x0F))
            response = read_report(fd, 1.0)
            if response is None:
                continue
            battery_response = response
            raw = response[4] | (response[5] << 8)
            if 1 <= raw <= 1000:
                battery = raw / 10
                break
        if battery is None:
            return HeadsetStatus(connected=False, raw=battery_response.hex(" ") if battery_response else None)

        flush_reports(fd)
        os.write(fd, v2_request(HEADSET_ENDPOINT, 0xA6))
        mic_response = read_report(fd, 1.0)
        muted = None if mic_response is None or len(mic_response) < 5 else mic_response[4] == 1
        return HeadsetStatus(
            connected=True,
            battery=battery,
            microphone_muted=muted,
            raw=battery_response.hex(" ") if battery_response else None,
        )
    finally:
        os.close(fd)


def set_inactive_time(devices: list[HidrawDevice], minutes: int) -> None:
    if not 0 <= minutes <= 90:
        raise ValueError("inactivity timeout must be between 0 and 90 minutes")
    fd = os.open(vendor_device(devices).path, os.O_RDWR)
    try:
        if not initialize_device(fd):
            raise RuntimeError("headset is not connected")
        toggle = bytearray(65)
        toggle[:7] = bytes([0, 2, HEADSET_ENDPOINT, 1, 0x0D, 0, int(minutes > 0)])
        os.write(fd, toggle)
        if minutes:
            timeout_ms = minutes * 60 * 1000
            timer = bytearray(65)
            timer[:6] = bytes([0, 2, HEADSET_ENDPOINT, 1, 0x0E, 0])
            timer[6:10] = timeout_ms.to_bytes(4, "little")
            os.write(fd, timer)
    finally:
        os.close(fd)


def main() -> int:
    parser = argparse.ArgumentParser(description="Corsair HS80 MAX status and settings")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument("--plain", action="store_true", help="print only the battery percentage")
    parser.add_argument("--watch", action="store_true", help="poll continuously")
    parser.add_argument("--interval", type=float, default=60, help="watch interval in seconds")
    parser.add_argument("--inactive-time", type=int, metavar="MINUTES", help="set auto-off timeout (0-90)")
    parser.add_argument(
        "--battery",
        action="store_true",
        help="query battery using the HS80 MAX/Corsair Wireless V2 protocol",
    )
    args = parser.parse_args()

    devices = find_receivers()
    if not devices:
        print("Corsair HS80 MAX receiver (1b1c:0a97) not found.", file=sys.stderr)
        return 1
    if args.inactive_time is not None:
        try:
            set_inactive_time(devices, args.inactive_time)
        except (OSError, RuntimeError, ValueError) as error:
            print(f"Could not set inactivity timeout: {error}", file=sys.stderr)
            return 4
        print(f"Inactivity timeout set to {args.inactive_time} minutes")
        return 0
    if args.battery or args.inactive_time is None:
        while True:
            try:
                status = get_status(devices)
            except (OSError, RuntimeError) as error:
                status = HeadsetStatus(False)
                if not (args.json or args.plain):
                    print(str(error), file=sys.stderr)
            if args.json:
                print(json.dumps(status.as_dict()), flush=True)
            elif args.plain:
                print("" if status.battery is None else f"{status.battery:g}", flush=True)
            elif status.connected:
                mic = "muted" if status.microphone_muted else "active" if status.microphone_muted is False else "unknown"
                print(f"Battery: {status.battery:g}% | Microphone: {mic}", flush=True)
            else:
                print("Headset disconnected", flush=True)
            if not args.watch:
                return 0 if status.connected else 3
            time.sleep(max(2, args.interval))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
