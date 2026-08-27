#!/usr/bin/env python3
"""KDE-friendly system tray for the Corsair HS80 MAX."""

from __future__ import annotations

import sys
import threading

from PySide6.QtCore import QObject, QSettings, QThread, Signal
from PySide6.QtGui import QAction, QColor, QFont, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

import hs80_max_battery as hs80


class Poller(QThread):
    updated = Signal(object)

    def __init__(self, interval: int = 60):
        super().__init__()
        self.interval = interval
        self._wake = threading.Event()

    def refresh(self):
        self._wake.set()

    def run(self):
        while not self.isInterruptionRequested():
            try:
                devices = hs80.find_receivers()
                status = hs80.get_status(devices) if devices else hs80.HeadsetStatus(False)
            except (OSError, RuntimeError):
                status = hs80.HeadsetStatus(False)
            self.updated.emit(status)
            self._wake.wait(self.interval)
            self._wake.clear()


def battery_icon(level: float | None, connected: bool) -> QIcon:
    if not connected or level is None:
        return QIcon.fromTheme("network-wireless-disconnected-symbolic", QIcon.fromTheme("audio-headset"))
    size = 64
    pixmap = QPixmap(size, size)
    pixmap.fill(QColor(0, 0, 0, 0))
    painter = QPainter(pixmap)
    color = QColor("#e74c3c" if level <= 15 else "#f39c12" if level <= 30 else "#2ecc71")
    painter.setPen(color)
    painter.setBrush(color)
    painter.drawRoundedRect(6, 14, 48, 38, 5, 5)
    painter.drawRect(54, 26, 5, 14)
    painter.setPen(QColor("white"))
    font = QFont()
    font.setBold(True)
    font.setPixelSize(18)
    painter.setFont(font)
    painter.drawText(6, 14, 48, 38, 0x84, str(round(level)))
    painter.end()
    return QIcon(pixmap)


class Tray(QObject):
    notice = Signal(str, str, bool)

    def __init__(self):
        super().__init__()
        self.settings = QSettings("hs80-max", "tray")
        self.last_level = self.settings.value("last_level", None, float)
        self.notified: set[int] = set()
        self.tray = QSystemTrayIcon(QIcon.fromTheme("audio-headset"))
        self.menu = QMenu()
        self.status_action = QAction("Checking HS80 MAX…")
        self.status_action.setEnabled(False)
        self.mic_action = QAction("Microphone: unknown")
        self.mic_action.setEnabled(False)
        self.menu.addAction(self.status_action)
        self.menu.addAction(self.mic_action)
        self.menu.addSeparator()
        refresh = self.menu.addAction(QIcon.fromTheme("view-refresh"), "Refresh now")
        refresh.triggered.connect(lambda: self.poller.refresh())
        timeout_menu = self.menu.addMenu(QIcon.fromTheme("preferences-system-time"), "Auto-off timeout")
        for minutes in (0, 5, 10, 15, 30, 60, 90):
            label = "Disabled" if minutes == 0 else f"{minutes} minutes"
            action = timeout_menu.addAction(label)
            action.triggered.connect(lambda _checked=False, value=minutes: self.set_timeout(value))
        self.menu.addSeparator()
        quit_action = self.menu.addAction(QIcon.fromTheme("application-exit"), "Quit")
        quit_action.triggered.connect(QApplication.quit)
        self.tray.setContextMenu(self.menu)
        self.tray.activated.connect(self.activated)
        self.tray.show()
        self.notice.connect(self.show_notice)

        self.poller = Poller()
        self.poller.updated.connect(self.update_status)
        self.poller.start()

    def activated(self, reason):
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.poller.refresh()

    def set_timeout(self, minutes: int):
        self.status_action.setText("Setting auto-off timeout…")
        def work():
            try:
                hs80.set_inactive_time(hs80.find_receivers(), minutes)
                self.settings.setValue("inactive_time", minutes)
                message = f"Auto-off set to {minutes} minutes" if minutes else "Auto-off disabled"
                self.notice.emit("HS80 MAX", message, False)
            except Exception as error:
                self.notice.emit("HS80 MAX", f"Could not set auto-off: {error}", True)
            self.poller.refresh()
        threading.Thread(target=work, daemon=True).start()

    def show_notice(self, title: str, message: str, warning: bool):
        icon = QSystemTrayIcon.MessageIcon.Warning if warning else QSystemTrayIcon.MessageIcon.Information
        self.tray.showMessage(title, message, icon, 5000 if warning else 3000)

    def update_status(self, status: hs80.HeadsetStatus):
        if not status.connected:
            self.status_action.setText("Headset disconnected")
            self.mic_action.setText("Microphone: unavailable")
            self.tray.setToolTip("HS80 MAX — disconnected")
            self.tray.setIcon(battery_icon(None, False))
            return

        level = status.battery or 0
        charging = None
        if self.last_level is not None:
            if level > self.last_level:
                charging = True
            elif level < self.last_level:
                charging = False
        state = "charging" if charging else "discharging" if charging is False else "charge state unknown"
        self.status_action.setText(f"Battery: {level:g}% — {state}")
        mic = "muted" if status.microphone_muted else "active" if status.microphone_muted is False else "unknown"
        self.mic_action.setText(f"Microphone: {mic}")
        timeout = self.settings.value("inactive_time", "not configured")
        self.tray.setToolTip(f"HS80 MAX — {level:g}%\nMicrophone: {mic}\nAuto-off: {timeout} min")
        self.tray.setIcon(battery_icon(level, True))

        for threshold in (20, 10, 5):
            if level <= threshold and threshold not in self.notified:
                self.notified.add(threshold)
                self.tray.showMessage("HS80 MAX battery low", f"{level:g}% remaining",
                                      QSystemTrayIcon.MessageIcon.Warning, 6000)
        if level > 25:
            self.notified.clear()
        self.last_level = level
        self.settings.setValue("last_level", level)

    def stop(self):
        self.poller.requestInterruption()
        self.poller.refresh()
        self.poller.wait(2000)


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("HS80 MAX")
    app.setQuitOnLastWindowClosed(False)
    tray = Tray()
    app.aboutToQuit.connect(tray.stop)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
