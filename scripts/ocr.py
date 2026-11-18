#!/home/oarabile/.local/share/rapidocr-venv/bin/python
import os
import sys
import time
import subprocess

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/tmp")

def notify(title, body, urgency="normal"):
    subprocess.run(
        ["notify-send", "-u", urgency, "-a", "Quickshell OCR", "-i", "accessories-character-map", title, body],
        check=False
    )

def format_markdown(result):
    if not result:
        return ""
    items = []
    for box, text, _score in result:
        y_top = min(pt[1] for pt in box)
        y_bot = max(pt[1] for pt in box)
        x_left = min(pt[0] for pt in box)
        height = max(1.0, y_bot - y_top)
        items.append((y_top, x_left, height, text.strip()))

    items.sort(key=lambda it: (it[0], it[1]))

    lines = []
    current_line = []
    current_y = None
    current_h = None

    for y_top, x_left, height, text in items:
        if not text:
            continue
        if current_y is None:
            current_y = y_top
            current_h = height
            current_line = [(x_left, text)]
        elif abs(y_top - current_y) <= max(current_h, height) * 0.55:
            current_line.append((x_left, text))
        else:
            current_line.sort(key=lambda x: x[0])
            lines.append(" ".join(t for _, t in current_line))
            current_y = y_top
            current_h = height
            current_line = [(x_left, text)]

    if current_line:
        current_line.sort(key=lambda x: x[0])
        lines.append(" ".join(t for _, t in current_line))

    return "\n\n".join(lines)

def main():
    if len(sys.argv) < 2 or not sys.argv[1]:
        notify("OCR Failed", "No image source provided.", "critical")
        sys.exit(1)

    is_file = sys.argv[1] == "--file"
    if is_file:
        if len(sys.argv) < 3 or not sys.argv[2]:
            notify("OCR Failed", "No file path provided.", "critical")
            sys.exit(1)
        img_path = sys.argv[2]
        win_addr = sys.argv[3] if len(sys.argv) > 3 else ""
        cleanup = False
    else:
        clip_id = sys.argv[1]
        win_addr = sys.argv[2] if len(sys.argv) > 2 else ""
        img_path = os.path.join(RUNTIME_DIR, f"qs_ocr_{clip_id}_{int(time.time() * 1000)}.png")
        cleanup = True

    try:
        if cleanup:
            with open(img_path, "wb") as f:
                subprocess.run(["cliphist", "decode", clip_id], stdout=f, check=True)
        elif not os.path.isfile(img_path):
            notify("OCR Failed", f"File not found: {img_path}", "critical")
            sys.exit(1)

        from rapidocr_onnxruntime import RapidOCR
        result, _ = RapidOCR()(img_path)

        markdown = format_markdown(result)
        if not markdown:
            notify("OCR Warning", "No text detected in image.")
            sys.exit(0)

        subprocess.run(
            ["wl-copy", "--type", "text/plain;charset=utf-8"],
            input=markdown.encode("utf-8"),
            check=True
        )

        if win_addr:
            subprocess.run(
                ["hyprctl", "dispatch", "focuswindow", f"address:{win_addr}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            time.sleep(0.15)
        subprocess.run(["wtype", "-M", "ctrl", "v", "-m", "ctrl"], check=False)

        n = len(markdown.split("\n\n"))
        notify("OCR Complete", f"Pasted Markdown ({n} {'line' if n == 1 else 'lines'}).")

    except Exception as e:
        notify("OCR Failed", str(e)[:140], "critical")
        sys.exit(1)
    finally:
        if cleanup and os.path.exists(img_path):
            os.remove(img_path)

if __name__ == "__main__":
    main()