#!/usr/bin/env python3
"""Local Quick Look for Dolphin: images, first-page PDF previews and plain text."""
import fcntl
import mimetypes
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk


class Preview(Gtk.Application):
    def __init__(self, path):
        super().__init__(application_id="org.dotfiles.Preview", flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.path = path
        self.worker = None
        self.closed = False
        self.was_active = False
        self.worker_lock = threading.Lock()
        self.temporary = tempfile.TemporaryDirectory(prefix="dolphin-preview-")

    def do_activate(self):
        self.window = Gtk.ApplicationWindow(application=self, title=self.path.name)
        self.window.set_default_size(760, 620)
        # Fixed sizing hints make this a floating preview immediately on Sway,
        # including before its persistent for_window rule has been reloaded.
        self.window.set_resizable(False)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for edge in ("top", "bottom", "start", "end"):
            getattr(box, "set_margin_" + edge)(12)
        self.window.set_child(box)
        label = Gtk.Label(label=self.path.name)
        label.set_ellipsize(3)
        box.append(label)
        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.body.set_vexpand(True)
        self.body.set_hexpand(True)
        box.append(self.body)
        footer = Gtk.Box(spacing=12)
        footer.append(Gtk.Label(label="Release Space or press Esc to close"))
        button = Gtk.Button(label="Open normally")
        button.connect("clicked", lambda *_: Gio.AppInfo.launch_default_for_uri(self.path.as_uri(), None))
        footer.append(button)
        close = Gtk.Button(label="Close")
        close.connect("clicked", lambda *_: self.window.close())
        footer.append(close)
        box.append(footer)
        keys = Gtk.EventControllerKey()
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-released", self.key_released)
        keys.connect("key-pressed", self.key_pressed)
        self.window.add_controller(keys)
        self.window.connect("close-request", self.cleanup)
        self.window.connect("notify::is-active", self.focus_changed)
        self.window.present()
        GLib.idle_add(self.load)

    def key_released(self, controller, key, code, modifiers):
        if key == Gdk.KEY_space:
            self.window.close()

    def key_pressed(self, controller, key, code, modifiers):
        if key == Gdk.KEY_Escape:
            self.window.close()
            return True
        return key == Gdk.KEY_space  # Ignore hold/autorepeat; close on release.

    def focus_changed(self, window, _):
        if window.is_active():
            self.was_active = True
        elif self.was_active:
            window.close()

    def cleanup(self, *_):
        with self.worker_lock:
            self.closed = True
            if self.worker and self.worker.poll() is None:
                self.worker.terminate()
        self.temporary.cleanup()
        return False

    def picture(self, path):
        if self.closed:
            return False
        image = Gtk.Picture.new_for_filename(str(path))
        image.set_content_fit(Gtk.ContentFit.CONTAIN)
        image.set_can_shrink(True)
        image.set_vexpand(True)
        image.set_hexpand(True)
        self.body.append(image)
        return False

    def pdf(self):
        prefix = Path(self.temporary.name) / "page"
        try:
            with self.worker_lock:
                if self.closed:
                    return
                self.worker = subprocess.Popen(["pdftoppm", "-f", "1", "-singlefile", "-scale-to", "1400",
                    "-png", str(self.path), str(prefix)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.worker.wait(timeout=8)
            if self.worker.returncode == 0:
                GLib.idle_add(self.picture, prefix.with_suffix(".png"))
        except (OSError, subprocess.TimeoutExpired):
            if self.worker and self.worker.poll() is None:
                self.worker.kill()

    def load(self):
        mime = mimetypes.guess_type(self.path)[0] or "application/octet-stream"
        if mime.startswith("image/"):
            self.picture(self.path)
        elif mime == "application/pdf":
            threading.Thread(target=self.pdf, daemon=True).start()
        elif mime.startswith("text/") or self.path.suffix.lower() in (".md", ".json", ".py", ".qml", ".toml", ".yaml", ".yml", ".conf", ".log"):
            with self.path.open("rb") as stream:
                text = stream.read(65537)
            view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True)
            view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
            view.get_buffer().set_text(text[:65536].decode("utf-8", errors="replace") + ("\n… Preview truncated" if len(text) > 65536 else ""))
            scroll = Gtk.ScrolledWindow(vexpand=True, hexpand=True)
            scroll.set_child(view)
            self.body.append(scroll)
        else:
            self.body.append(Gtk.Label(label=f"{mime}\n{self.path.stat().st_size:,} bytes\nUse Open normally for this file type."))
        return False


if __name__ == "__main__":
    os.umask(0o077)
    if len(sys.argv) != 2:
        raise SystemExit(2)
    path = Path(sys.argv[1]).resolve()
    if not path.is_file():
        raise SystemExit(0)
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    fd = os.open(runtime / "dotfiles-preview.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit(0)
    Preview(path).run([sys.argv[0]])
