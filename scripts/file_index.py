#!/usr/bin/env python3
"""
Exact Sparse TF-IDF Vector + SQLite FTS5/BM25 file & image content indexer for Quickshell Launcher.
- Two-phase sync:
  1. `sync` indexes filenames, text/code/Markdown/Typst/PDF/Office docs synchronously in tens of ms,
     reuses cached image OCR + VLM captions, and detaches a low-priority `sync-images` worker for new images.
  2. `sync-images` runs at `nice -n 19` in batches, extracting text via RapidOCR and visual descriptions
     via `image_caption.py` (SmolVLM-256M or tiny-image-captioning), committing progressively.
- Guardrails skip tiny UI icons (< 10 KB or < 128x128 px) and theme/cursor/asset folders.
"""
import argparse
import difflib
import json
import math
import os
import re
import signal
import sqlite3
import struct
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

HOME = Path.home()
STATE_DIR = HOME / ".local/state/quickshell-launcher"
DB_PATH = STATE_DIR / "content-index.db"
CACHE_TXT = STATE_DIR / "file-index.txt"
IMG_LOCK_PATH = STATE_DIR / "image-sync.pid"

SCRIPT_DIR = Path(__file__).resolve().parent
CAPTION_SCRIPT = SCRIPT_DIR / "image_caption.py"
RAPIDOCR_PYTHON = HOME / ".local/share/rapidocr-venv/bin/python"
CAPTION_PYTHON = HOME / ".local/share/caption-venv/bin/python"

SEARCH_ROOTS = [
    HOME / "Documents",
    HOME / "Downloads",
    HOME / "Pictures",
    HOME / "Videos",
    HOME / "Projects",
]

SKIP_DIRS = {
    ".git", "node_modules", "__pycache__", ".venv", "venv",
    "target", "build", ".cache", "dist", ".next", ".cargo",
}

IMAGE_SKIP_DIRS = {
    "assets", "asset", "cursors", "cursor", "icons", "icon",
    "themes", "theme", "sprites", "thumbnails", ".thumbnails",
}

TEXT_EXTS = {
    ".txt", ".md", ".markdown", ".rst", ".org", ".tex", ".typ",
    ".py", ".c", ".cpp", ".cc", ".h", ".hpp", ".go", ".rs",
    ".ts", ".tsx", ".js", ".jsx", ".v", ".odin", ".java", ".kt",
    ".sh", ".fish", ".zsh", ".bash", ".qml", ".json", ".toml",
    ".yaml", ".yml", ".csv", ".tsv", ".html", ".htm", ".xml",
    ".css", ".scss", ".sql", ".ini", ".conf", ".cfg", ".log",
}

XML_ZIP_EXTS = {".docx", ".odt", ".epub", ".pptx", ".xlsx"}
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".avif"}

SCHEMA_VERSION = 4
MAX_DOC_TERMS = 600
MAX_EXTRACT_BYTES = 15 * 1024 * 1024
MIN_IMAGE_BYTES = 10 * 1024
MAX_IMAGE_BYTES = 25 * 1024 * 1024
MIN_IMAGE_DIM = 128
MAX_TEXT_CHARS = 120_000
TOKEN_RE = re.compile(r"[a-z0-9]{2,}")

STOPWORDS = {
    "the", "and", "for", "with", "this", "that", "from", "are", "was", "were",
    "have", "has", "had", "not", "but", "you", "your", "can", "will", "into",
    "also", "than", "then", "them", "they", "their", "there", "here", "what",
    "when", "where", "which", "while", "about", "after", "before", "between",
    "each", "other", "some", "such", "only", "same", "very", "just", "more",
    "most", "use", "used", "using", "its", "out", "all", "any", "both", "few",
    "how", "why", "who", "whom", "been", "being", "does", "did", "doing",
    "would", "could", "should", "may", "might", "must", "shall", "over",
    "under", "again", "further", "once", "during", "through", "above", "below",
    "import", "def", "return", "const", "let", "var", "function", "class",
    "true", "false", "null", "none", "void", "int", "str", "self", "public",
    "private", "static", "export", "default", "include", "endif", "ifdef",
}


def connect_db() -> sqlite3.Connection:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), timeout=15.0)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")

    ver = conn.execute("PRAGMA user_version;").fetchone()[0]
    if ver != SCHEMA_VERSION:
        conn.executescript(
            """
            DROP TABLE IF EXISTS files;
            DROP TABLE IF EXISTS files_fts;
            DROP TABLE IF EXISTS file_vectors;
            DROP TABLE IF EXISTS doc_features;
            DROP TABLE IF EXISTS doc_terms;
            DROP TABLE IF EXISTS term_postings;
            DROP TABLE IF EXISTS idf_stats;
            DROP TABLE IF EXISTS doc_meta;
            DROP TABLE IF EXISTS image_cache;
            """
        )
        conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION};")

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS files (
            path TEXT PRIMARY KEY,
            mtime INTEGER NOT NULL,
            size INTEGER NOT NULL
        );
        """
    )
    conn.execute(
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
            path UNINDEXED,
            title,
            body,
            tokenize='porter unicode61'
        );
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS doc_terms (
            path TEXT NOT NULL,
            term TEXT NOT NULL,
            tf_w REAL NOT NULL,
            PRIMARY KEY (path, term)
        );
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS term_postings (
            term TEXT NOT NULL,
            path TEXT NOT NULL,
            weight REAL NOT NULL,
            PRIMARY KEY (term, path)
        );
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS idf_stats (
            term TEXT PRIMARY KEY,
            idf REAL NOT NULL
        );
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS doc_meta (
            path TEXT PRIMARY KEY,
            has_body INTEGER NOT NULL
        );
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS image_cache (
            path TEXT PRIMARY KEY,
            mtime INTEGER NOT NULL,
            size INTEGER NOT NULL,
            ocr_text TEXT NOT NULL DEFAULT '',
            caption_text TEXT NOT NULL DEFAULT ''
        );
        """
    )
    return conn


def get_image_dimensions(path: Path) -> tuple[int, int] | None:
    """Fast header-only image dimension parser (PNG, GIF, JPEG, WEBP) with zero dependencies."""
    try:
        with open(path, "rb") as f:
            head = f.read(32)
            if len(head) < 16:
                return None
            # PNG
            if head[:8] == b"\x89PNG\r\n\x1a\n" and len(head) >= 24:
                w, h = struct.unpack(">II", head[16:24])
                return int(w), int(h)
            # GIF
            if head[:6] in (b"GIF87a", b"GIF89a"):
                w, h = struct.unpack("<HH", head[6:10])
                return int(w), int(h)
            # WEBP
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                chunk = head[12:16]
                if chunk == b"VP8X" and len(head) >= 30:
                    w = 1 + int.from_bytes(head[24:27], "little")
                    h = 1 + int.from_bytes(head[27:30], "little")
                    return w, h
                if chunk == b"VP8 " and len(head) >= 30:
                    w, h = struct.unpack("<HH", head[26:30])
                    return w & 0x3FFF, h & 0x3FFF
                if chunk == b"VP8L" and len(head) >= 25:
                    b0, b1, b2, b3 = head[21:25]
                    w = 1 + (((b1 & 0x3F) << 8) | b0)
                    h = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6))
                    return w, h
            # JPEG
            if head[:2] == b"\xff\xd8":
                f.seek(2)
                while True:
                    b = f.read(1)
                    if not b:
                        break
                    while b == b"\xff":
                        b = f.read(1)
                    if not b:
                        break
                    marker = b[0]
                    if marker in (0xD8, 0xD9, 0x01) or (0xD0 <= marker <= 0xD7):
                        continue
                    seg_len_bytes = f.read(2)
                    if len(seg_len_bytes) < 2:
                        break
                    seg_len = struct.unpack(">H", seg_len_bytes)[0]
                    if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                        sof = f.read(5)
                        if len(sof) == 5:
                            h, w = struct.unpack(">HH", sof[1:5])
                            return int(w), int(h)
                        break
                    f.seek(seg_len - 2, os.SEEK_CUR)
    except Exception:
        return None
    return None


def is_indexable_image(path: Path, size: int) -> bool:
    if path.suffix.lower() not in IMAGE_EXTS:
        return False
    if size < MIN_IMAGE_BYTES or size > MAX_IMAGE_BYTES:
        return False
    lower_parts = {part.lower() for part in path.parent.parts}
    if lower_parts & IMAGE_SKIP_DIRS:
        return False
    dims = get_image_dimensions(path)
    if dims is not None:
        w, h = dims
        if w < MIN_IMAGE_DIM or h < MIN_IMAGE_DIM:
            return False
    return True


def compose_image_body(caption_text: str, ocr_text: str) -> str:
    parts = []
    cap = caption_text.strip()
    ocr = ocr_text.strip()
    if cap:
        parts.append(f"[Caption] {cap}")
    if ocr:
        parts.append(f"[OCR] {ocr}")
    return "\n".join(parts)


def tokenize_content(text: str) -> list[str]:
    raw = TOKEN_RE.findall(text.lower())
    filtered = [t for t in raw if t not in STOPWORDS]
    return filtered if filtered else raw


def extract_doc_terms(title: str, body: str, caption_text: str = "") -> dict[str, float]:
    """Extract sublinear TF weights for exact unigrams, bigrams, and visual captions."""
    title_toks = tokenize_content(title)
    body_toks = tokenize_content(body)
    cap_toks = tokenize_content(caption_text) if caption_text else []

    tf: Counter[str] = Counter()
    for tok in title_toks:
        tf[f"w:{tok}"] += 3.5
    for i in range(len(title_toks) - 1):
        tf[f"b:{title_toks[i]}_{title_toks[i+1]}"] += 3.0

    for tok in cap_toks:
        tf[f"w:{tok}"] += 2.2
    for i in range(len(cap_toks) - 1):
        tf[f"b:{cap_toks[i]}_{cap_toks[i+1]}"] += 2.0

    for tok in body_toks:
        tf[f"w:{tok}"] += 1.0
    for i in range(len(body_toks) - 1):
        tf[f"b:{body_toks[i]}_{body_toks[i+1]}"] += 1.6

    weighted = {
        term: round(1.0 + math.log(val), 4)
        for term, val in tf.items()
        if val > 0
    }
    if len(weighted) > MAX_DOC_TERMS:
        top = sorted(weighted.items(), key=lambda kv: kv[1], reverse=True)[:MAX_DOC_TERMS]
        weighted = dict(top)
    return weighted


def rebuild_sparse_index(conn: sqlite3.Connection) -> None:
    """Recompute corpus IDF weights and L2-normalized sparse postings."""
    total_docs = conn.execute("SELECT COUNT(*) FROM doc_meta").fetchone()[0]
    if total_docs == 0:
        conn.execute("DELETE FROM idf_stats")
        conn.execute("DELETE FROM term_postings")
        return

    has_body_map = dict(conn.execute("SELECT path, has_body FROM doc_meta").fetchall())

    df_rows = conn.execute("SELECT term, COUNT(*) FROM doc_terms GROUP BY term").fetchall()
    idf_map: dict[str, float] = {}
    for term, df in df_rows:
        idf_map[term] = round(1.0 + math.log((total_docs + 1.0) / (df + 1.0)), 4)

    conn.execute("DELETE FROM idf_stats")
    conn.executemany("INSERT INTO idf_stats (term, idf) VALUES (?, ?)", list(idf_map.items()))

    doc_rows = conn.execute("SELECT path, term, tf_w FROM doc_terms ORDER BY path").fetchall()
    conn.execute("DELETE FROM term_postings")

    postings_batch: list[tuple[str, str, float]] = []
    cur_path = None
    cur_items: list[tuple[str, float]] = []

    def flush_doc(p: str, items: list[tuple[str, float]]) -> None:
        if not items:
            return
        sq_sum = sum(w * w for _, w in items)
        raw_norm = math.sqrt(sq_sum)
        min_norm = 2.5 if has_body_map.get(p, 0) else 7.0
        norm = max(raw_norm, min_norm)
        inv = 1.0 / norm
        for t, w in items:
            postings_batch.append((t, p, round(w * inv, 5)))

    for path, term, tf_w in doc_rows:
        if path != cur_path:
            if cur_path is not None:
                flush_doc(cur_path, cur_items)
            cur_path = path
            cur_items = []
        idf = idf_map.get(term, 1.0)
        cur_items.append((term, tf_w * idf))

    if cur_path is not None:
        flush_doc(cur_path, cur_items)

    conn.executemany(
        "INSERT INTO term_postings (term, path, weight) VALUES (?, ?, ?)",
        postings_batch,
    )


def extract_pdf_text(path: Path) -> str:
    try:
        proc = subprocess.run(
            ["pdftotext", "-q", "-enc", "UTF-8", str(path), "-"],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout:
            return proc.stdout[:MAX_TEXT_CHARS]
    except Exception:
        pass
    return ""


def extract_xml_zip_text(path: Path) -> str:
    try:
        chunks = []
        total = 0
        with zipfile.ZipFile(path, "r") as zf:
            for name in zf.namelist():
                if not name.endswith(".xml"):
                    continue
                data = zf.read(name)
                root = ET.fromstring(data)
                for elem in root.iter():
                    if elem.text and elem.text.strip():
                        t = elem.text.strip()
                        chunks.append(t)
                        total += len(t)
                        if total >= MAX_TEXT_CHARS:
                            return " ".join(chunks)[:MAX_TEXT_CHARS]
        return " ".join(chunks)[:MAX_TEXT_CHARS]
    except Exception:
        return ""


def extract_text(path: Path, size: int) -> str:
    if size <= 0 or size > MAX_EXTRACT_BYTES:
        return ""
    ext = path.suffix.lower()
    if ext == ".pdf":
        return extract_pdf_text(path)
    if ext in XML_ZIP_EXTS:
        return extract_xml_zip_text(path)
    if ext in TEXT_EXTS:
        try:
            return path.read_text(encoding="utf-8", errors="ignore")[:MAX_TEXT_CHARS]
        except Exception:
            return ""
    return ""


def walk_files(max_depth: int = 6, max_results: int = 5000) -> list[tuple[Path, int, int, bool]]:
    found = []
    for root in SEARCH_ROOTS:
        if not root.exists():
            continue
        base_depth = len(root.parts)
        for dirpath, dirnames, filenames in os.walk(root):
            cur = Path(dirpath)
            depth = len(cur.parts) - base_depth
            dirnames[:] = [
                d for d in dirnames
                if d not in SKIP_DIRS and not d.startswith(".")
            ]
            if depth > 0:
                try:
                    st = cur.stat()
                    found.append((cur, int(st.st_mtime), 0, True))
                except OSError:
                    pass
            if depth >= max_depth:
                dirnames[:] = []
            for fn in filenames:
                if fn.startswith("."):
                    continue
                fp = cur / fn
                try:
                    st = fp.stat()
                    found.append((fp, int(st.st_mtime), int(st.st_size), False))
                except OSError:
                    continue
                if len(found) >= max_results:
                    return found
    return found


def is_pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def is_image_sync_running() -> bool:
    if not IMG_LOCK_PATH.is_file():
        return False
    try:
        pid = int(IMG_LOCK_PATH.read_text(encoding="utf-8").strip())
        if is_pid_alive(pid):
            return True
    except Exception:
        pass
    try:
        IMG_LOCK_PATH.unlink(missing_ok=True)
    except Exception:
        pass
    return False


def spawn_background_image_sync() -> bool:
    if is_image_sync_running():
        return False
    try:
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "sync-images"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
        return True
    except Exception:
        return False


def cmd_sync(spawn_images: bool = True) -> None:
    conn = connect_db()
    entries = walk_files()

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with open(CACHE_TXT, "w", encoding="utf-8") as cf:
        for fp, _mt, _sz, is_dir in entries:
            cf.write(f"{fp}/\n" if is_dir else f"{fp}\n")

    existing = {
        row[0]: (row[1], row[2])
        for row in conn.execute("SELECT path, mtime, size FROM files")
    }
    img_cached = {
        row[0]: (row[1], row[2], row[3], row[4])
        for row in conn.execute("SELECT path, mtime, size, ocr_text, caption_text FROM image_cache")
    }
    current_paths = {str(fp) for fp, _, _, _ in entries}

    removed = [p for p in existing if p not in current_paths]
    if removed:
        conn.executemany("DELETE FROM files WHERE path = ?", [(p,) for p in removed])
        conn.executemany("DELETE FROM files_fts WHERE path = ?", [(p,) for p in removed])
        conn.executemany("DELETE FROM doc_terms WHERE path = ?", [(p,) for p in removed])
        conn.executemany("DELETE FROM term_postings WHERE path = ?", [(p,) for p in removed])
        conn.executemany("DELETE FROM doc_meta WHERE path = ?", [(p,) for p in removed])
        conn.executemany("DELETE FROM image_cache WHERE path = ?", [(p,) for p in removed])

    updated = 0
    pending_images = 0

    for fp, mtime, size, is_dir in entries:
        p_str = str(fp)
        prev = existing.get(p_str)
        is_img = (not is_dir) and is_indexable_image(fp, size)

        if is_img:
            ic = img_cached.get(p_str)
            if ic is not None and ic[0] == mtime and ic[1] == size:
                # Already OCR'd / captioned: reuse cached metadata if files table wasn't synced yet
                if prev == (mtime, size):
                    continue
                ocr_txt, cap_txt = ic[2], ic[3]
                body = compose_image_body(cap_txt, ocr_txt)
                has_body = 1 if len(body) > 0 else 0
                terms = extract_doc_terms(fp.name, ocr_txt, caption_text=cap_txt)
            else:
                pending_images += 1
                if prev == (mtime, size):
                    continue
                # Index filename immediately while queuing image for background OCR + VLM
                body = ""
                has_body = 0
                terms = extract_doc_terms(fp.name, "")
        else:
            if prev == (mtime, size):
                continue
            body = "" if is_dir else extract_text(fp, size)
            has_body = 1 if len(body.strip()) > 0 else 0
            terms = extract_doc_terms(fp.name, body)

        title = fp.name
        conn.execute("DELETE FROM files_fts WHERE path = ?", (p_str,))
        conn.execute(
            "INSERT INTO files_fts (path, title, body) VALUES (?, ?, ?)",
            (p_str, title, body),
        )
        conn.execute("DELETE FROM doc_terms WHERE path = ?", (p_str,))
        conn.executemany(
            "INSERT INTO doc_terms (path, term, tf_w) VALUES (?, ?, ?)",
            [(p_str, t, w) for t, w in terms.items()],
        )
        conn.execute(
            "INSERT OR REPLACE INTO doc_meta (path, has_body) VALUES (?, ?)",
            (p_str, has_body),
        )
        conn.execute(
            "INSERT OR REPLACE INTO files (path, mtime, size) VALUES (?, ?, ?)",
            (p_str, mtime, size),
        )
        updated += 1
        if updated % 100 == 0:
            conn.commit()

    postings_count = conn.execute("SELECT COUNT(*) FROM term_postings").fetchone()[0]
    if updated > 0 or removed or (len(entries) > 0 and postings_count == 0):
        rebuild_sparse_index(conn)

    conn.commit()
    conn.close()

    bg_spawned = False
    if spawn_images and pending_images > 0:
        bg_spawned = spawn_background_image_sync()

    print(
        json.dumps(
            {
                "total": len(entries),
                "updated": updated,
                "removed": len(removed),
                "pending_images": pending_images,
                "image_worker_started": bg_spawned,
            }
        )
    )


def run_batch_ocr(paths: list[str]) -> dict[str, str]:
    """Run RapidOCR once over a batch of image paths using the isolated rapidocr-venv."""
    if not paths or not RAPIDOCR_PYTHON.is_file():
        return {}
    worker_code = (
        "import json, sys\n"
        "from rapidocr_onnxruntime import RapidOCR\n"
        "paths = json.loads(sys.stdin.read() or '[]')\n"
        "ocr = RapidOCR()\n"
        "out = {}\n"
        "for p in paths:\n"
        "    try:\n"
        "        res, _ = ocr(p)\n"
        "        if res:\n"
        "            out[p] = ' '.join(item[1].strip() for item in res if item and len(item) >= 2 and item[1])\n"
        "    except Exception:\n"
        "        pass\n"
        "print(json.dumps(out))\n"
    )
    try:
        proc = subprocess.run(
            [str(RAPIDOCR_PYTHON), "-c", worker_code],
            input=json.dumps(paths),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            parsed = json.loads(proc.stdout)
            return parsed if isinstance(parsed, dict) else {}
    except Exception:
        pass
    return {}


def run_batch_captions(paths: list[str]) -> dict[str, str]:
    """Run offline VLM captioning over a batch of images via image_caption.py."""
    if not paths or not CAPTION_SCRIPT.is_file():
        return {}
    py_bin = str(CAPTION_PYTHON) if CAPTION_PYTHON.is_file() else sys.executable
    try:
        proc = subprocess.run(
            [py_bin, str(CAPTION_SCRIPT)],
            input=json.dumps(paths),
            capture_output=True,
            text=True,
            timeout=300,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            parsed = json.loads(proc.stdout)
            return parsed if isinstance(parsed, dict) else {}
    except Exception:
        pass
    return {}


def cmd_sync_images(retag: bool = False, limit: int = 0) -> None:
    if is_image_sync_running():
        print(json.dumps({"status": "already_running"}))
        return

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    IMG_LOCK_PATH.write_text(str(os.getpid()), encoding="utf-8")

    try:
        try:
            os.nice(19)
        except Exception:
            pass

        conn = connect_db()
        entries = walk_files()
        img_cached = {
            row[0]: (row[1], row[2], row[3], row[4])
            for row in conn.execute("SELECT path, mtime, size, ocr_text, caption_text FROM image_cache")
        }

        queue: list[tuple[Path, int, int, bool, bool]] = []
        for fp, mtime, size, is_dir in entries:
            if is_dir or not is_indexable_image(fp, size):
                continue
            p_str = str(fp)
            ic = img_cached.get(p_str)
            if ic is None or ic[0] != mtime or ic[1] != size:
                queue.append((fp, mtime, size, True, True))
            elif retag and not ic[3].strip():
                queue.append((fp, mtime, size, False, True))

        if limit > 0:
            queue = queue[:limit]

        processed = 0
        batch_size = 8

        for i in range(0, len(queue), batch_size):
            batch = queue[i : i + batch_size]
            ocr_targets = [str(fp) for fp, _, _, need_ocr, _ in batch if need_ocr]
            cap_targets = [str(fp) for fp, _, _, _, need_cap in batch if need_cap]

            ocr_map = run_batch_ocr(ocr_targets)
            cap_map = run_batch_captions(cap_targets)

            for fp, mtime, size, need_ocr, need_cap in batch:
                p_str = str(fp)
                prev_ic = img_cached.get(p_str)
                ocr_txt = ocr_map.get(p_str, "") if need_ocr else (prev_ic[2] if prev_ic else "")
                cap_txt = cap_map.get(p_str, "") if need_cap else (prev_ic[3] if prev_ic else "")

                body = compose_image_body(cap_txt, ocr_txt)
                has_body = 1 if len(body) > 0 else 0
                terms = extract_doc_terms(fp.name, ocr_txt, caption_text=cap_txt)

                conn.execute(
                    """
                    INSERT OR REPLACE INTO image_cache (path, mtime, size, ocr_text, caption_text)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (p_str, mtime, size, ocr_txt, cap_txt),
                )
                conn.execute("DELETE FROM files_fts WHERE path = ?", (p_str,))
                conn.execute(
                    "INSERT INTO files_fts (path, title, body) VALUES (?, ?, ?)",
                    (p_str, fp.name, body),
                )
                conn.execute("DELETE FROM doc_terms WHERE path = ?", (p_str,))
                conn.executemany(
                    "INSERT INTO doc_terms (path, term, tf_w) VALUES (?, ?, ?)",
                    [(p_str, t, w) for t, w in terms.items()],
                )
                conn.execute(
                    "INSERT OR REPLACE INTO doc_meta (path, has_body) VALUES (?, ?)",
                    (p_str, has_body),
                )
                conn.execute(
                    "INSERT OR REPLACE INTO files (path, mtime, size) VALUES (?, ?, ?)",
                    (p_str, mtime, size),
                )
                processed += 1

            rebuild_sparse_index(conn)
            conn.commit()

        conn.close()
        print(json.dumps({"status": "done", "processed": processed}))
    finally:
        try:
            IMG_LOCK_PATH.unlink(missing_ok=True)
        except Exception:
            pass


def expand_query_terms(conn: sqlite3.Connection, q_tokens: list[str]) -> tuple[dict[str, float], dict[str, set[str]]]:
    """Build L2-normalized query vector over exact vocabulary terms + collision-free typo/prefix recovery."""
    raw_weights: dict[str, float] = {}
    term_slots: dict[str, set[str]] = {}

    unique_toks = list(dict.fromkeys(q_tokens))
    for tok in unique_toks:
        key = f"w:{tok}"
        row = conn.execute("SELECT idf FROM idf_stats WHERE term = ?", (key,)).fetchone()
        if row is not None:
            raw_weights[key] = float(row[0])
            term_slots.setdefault(key, set()).add(tok)
        elif len(tok) >= 4:
            prefix = tok[:2]
            cands = conn.execute(
                "SELECT term, idf FROM idf_stats WHERE term LIKE ? LIMIT 400",
                (f"w:{prefix}%",),
            ).fetchall()
            scored_cands: list[tuple[float, str, float]] = []
            for cand_term, idf in cands:
                cand_word = cand_term[2:]
                if cand_word.startswith(tok):
                    sim = 0.92
                else:
                    if abs(len(cand_word) - len(tok)) > 3:
                        continue
                    sim = difflib.SequenceMatcher(None, tok, cand_word).ratio()
                if sim >= 0.78:
                    scored_cands.append((sim, cand_term, float(idf)))
            scored_cands.sort(reverse=True)
            for sim, cand_term, idf in scored_cands[:3]:
                w = idf * 0.85 * sim
                raw_weights[cand_term] = max(raw_weights.get(cand_term, 0.0), w)
                term_slots.setdefault(cand_term, set()).add(tok)

    for i in range(len(q_tokens) - 1):
        b_key = f"b:{q_tokens[i]}_{q_tokens[i+1]}"
        row = conn.execute("SELECT idf FROM idf_stats WHERE term = ?", (b_key,)).fetchone()
        if row is not None:
            raw_weights[b_key] = float(row[0]) * 1.35

    norm = math.sqrt(sum(w * w for w in raw_weights.values()))
    if norm > 1e-12:
        inv = 1.0 / norm
        raw_weights = {t: w * inv for t, w in raw_weights.items()}

    return raw_weights, term_slots


def inspect_passage_and_phrase(
    conn: sqlite3.Connection,
    path: str,
    raw_query_norm: str,
    q_tokens: list[str],
    existing_snippet: str,
) -> tuple[bool, str]:
    """Check for contiguous phrase match and extract the highest-density passage snippet."""
    row = conn.execute("SELECT title, body FROM files_fts WHERE path = ?", (path,)).fetchone()
    if not row:
        return False, existing_snippet

    title, body = row[0] or "", row[1] or ""
    hay = f"{title}\n{body[:35000]}"
    norm_hay = re.sub(r"\s+", " ", hay).lower()

    phrase_hit = len(raw_query_norm) >= 6 and raw_query_norm in norm_hay

    if existing_snippet and not phrase_hit:
        return False, existing_snippet

    tok_set = set(q_tokens)
    best_line = existing_snippet
    best_hits = 0
    best_pos = -1

    if phrase_hit:
        idx = norm_hay.find(raw_query_norm)
        if idx >= 0:
            start = max(0, idx - 24)
            end = min(len(norm_hay), idx + len(raw_query_norm) + 56)
            orig_collapsed = re.sub(r"\s+", " ", hay)
            snippet = orig_collapsed[start:end].strip()
            if start > 0:
                snippet = "…" + snippet
            if end < len(orig_collapsed):
                snippet = snippet + "…"
            return True, snippet

    for line in body[:25000].splitlines():
        clean = re.sub(r"\s+", " ", line).strip()
        if len(clean) < 4:
            continue
        line_toks = set(TOKEN_RE.findall(clean.lower()))
        hits = len(tok_set & line_toks)
        if hits > best_hits:
            best_hits = hits
            best_line = clean[:120]
            best_pos = 1

    if best_pos < 0 and not best_line:
        for line in body[:4000].splitlines():
            clean = re.sub(r"\s+", " ", line).strip()
            if len(clean) >= 8:
                best_line = clean[:120]
                break

    return phrase_hit, best_line


def cmd_search(query: str, limit: int = 20) -> None:
    q = query.strip()
    if len(q) < 2 or not DB_PATH.exists():
        print("[]")
        return

    conn = connect_db()
    q_tokens = tokenize_content(q)
    if not q_tokens:
        conn.close()
        print("[]")
        return

    total_slots = max(1, len(set(q_tokens)))
    q_weights, term_slots = expand_query_terms(conn, q_tokens)

    cos_scores: dict[str, float] = {}
    matched_slots: dict[str, set[str]] = {}

    if q_weights:
        placeholders = ",".join("?" for _ in q_weights)
        rows = conn.execute(
            f"SELECT term, path, weight FROM term_postings WHERE term IN ({placeholders})",
            list(q_weights.keys()),
        ).fetchall()
        for term, path, doc_w in rows:
            cos_scores[path] = cos_scores.get(path, 0.0) + q_weights[term] * float(doc_w)
            slots = term_slots.get(term)
            if slots:
                matched_slots.setdefault(path, set()).update(slots)

    fts_hits: dict[str, tuple[float, str, bool]] = {}
    unique_fts_toks = list(dict.fromkeys(q_tokens))[:10]
    quoted = [f'"{t}"*' for t in unique_fts_toks]

    fts_queries: list[tuple[str, bool]] = [(" AND ".join(quoted), True)]
    if len(quoted) > 1:
        fts_queries.append((" OR ".join(quoted), False))

    for fts_q, is_and in fts_queries:
        if not is_and and len(fts_hits) >= 5:
            break
        try:
            rows = conn.execute(
                """
                SELECT path,
                       bm25(files_fts, 10.0, 1.0) AS rank,
                       snippet(files_fts, 2, '', '', '…', 18) AS snip
                FROM files_fts
                WHERE files_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """,
                (fts_q, limit * 3),
            ).fetchall()
            for path, rank, snip in rows:
                bm25_pos = max(0.0, -float(rank))
                clean_snip = re.sub(r"\s+", " ", snip or "").strip()
                prev = fts_hits.get(path)
                if prev is None or (is_and and not prev[2]) or bm25_pos > prev[0]:
                    fts_hits[path] = (bm25_pos, clean_snip, is_and)
                if is_and:
                    matched_slots.setdefault(path, set()).update(unique_fts_toks)
        except sqlite3.OperationalError:
            continue

    candidate_paths = set(cos_scores.keys()) | set(fts_hits.keys())
    scored: list[dict] = []

    for path in candidate_paths:
        cos_sim = cos_scores.get(path, 0.0)
        fts_data = fts_hits.get(path)
        n_matched = len(matched_slots.get(path, set()))
        if n_matched == 0 and fts_data is not None:
            n_matched = 1

        coverage = min(1.0, n_matched / total_slots)
        cov_mult = coverage * coverage

        if cos_sim < 0.04 and fts_data is None:
            continue

        vec_points = max(0.0, cos_sim) * 1200.0
        fts_points = min(300.0, fts_data[0] * 30.0) if fts_data else 0.0
        and_bonus = 250.0 if (fts_data and fts_data[2] and total_slots > 1) else 0.0

        total = (vec_points + fts_points + and_bonus) * cov_mult
        is_img = Path(path).suffix.lower() in IMAGE_EXTS

        scored.append(
            {
                "path": path,
                "source": "image" if is_img else "doc",
                "score": round(total, 2),
                "vec": round(cos_sim, 3),
                "fts": round(fts_data[0], 2) if fts_data else 0.0,
                "coverage": round(coverage, 2),
                "phrase": False,
                "snippet": fts_data[1] if fts_data else "",
            }
        )

    scored.sort(key=lambda x: x["score"], reverse=True)

    raw_query_norm = re.sub(r"\s+", " ", q.lower()).strip()
    top_inspect = scored[:35]
    for item in top_inspect:
        phrase_hit, best_snip = inspect_passage_and_phrase(
            conn, item["path"], raw_query_norm, q_tokens, item["snippet"]
        )
        item["phrase"] = phrase_hit
        item["snippet"] = best_snip
        if phrase_hit:
            item["score"] = round(item["score"] + 750.0, 2)

    top_inspect.sort(key=lambda x: x["score"], reverse=True)
    conn.close()
    print(json.dumps(top_inspect[:limit]))


def cmd_stats() -> None:
    if not DB_PATH.exists():
        print(json.dumps({"indexed_files": 0, "indexed_images": 0, "posting_rows": 0, "db_bytes": 0}))
        return
    conn = connect_db()
    count = conn.execute("SELECT COUNT(*) FROM files").fetchone()[0]
    img_count = conn.execute("SELECT COUNT(*) FROM image_cache").fetchone()[0]
    cap_count = conn.execute("SELECT COUNT(*) FROM image_cache WHERE LENGTH(TRIM(caption_text)) > 0").fetchone()[0]
    ocr_count = conn.execute("SELECT COUNT(*) FROM image_cache WHERE LENGTH(TRIM(ocr_text)) > 0").fetchone()[0]
    postings = conn.execute("SELECT COUNT(*) FROM term_postings").fetchone()[0]
    idf_terms = conn.execute("SELECT COUNT(*) FROM idf_stats").fetchone()[0]
    conn.close()
    print(
        json.dumps(
            {
                "indexed_files": count,
                "indexed_images": img_count,
                "captioned_images": cap_count,
                "ocr_images": ocr_count,
                "image_sync_running": is_image_sync_running(),
                "posting_rows": postings,
                "idf_terms": idf_terms,
                "db_bytes": DB_PATH.stat().st_size,
            }
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Sparse TF-IDF Vector + FTS5 + Image OCR/VLM Indexer")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sp_sync = sub.add_parser("sync", help="Fast incremental doc sync + spawn background image OCR/VLM worker")
    sp_sync.add_argument("--no-images", action="store_true", help="Skip spawning background image indexer")

    sp_img = sub.add_parser("sync-images", help="Run offline RapidOCR + VLM caption indexing on eligible images")
    sp_img.add_argument("--retag", action="store_true", help="Generate VLM captions for images that only have OCR so far")
    sp_img.add_argument("--limit", type=int, default=0, help="Max images to process in this run (0 = all)")

    sp = sub.add_parser("search", help="Hybrid sparse vector + FTS5 search")
    sp.add_argument("query", type=str)
    sp.add_argument("--limit", type=int, default=20)
    sub.add_parser("stats", help="Show index statistics")

    args = parser.parse_args()
    if args.cmd == "sync":
        cmd_sync(spawn_images=not args.no_images)
    elif args.cmd == "sync-images":
        cmd_sync_images(retag=args.retag, limit=args.limit)
    elif args.cmd == "search":
        cmd_search(args.query, args.limit)
    elif args.cmd == "stats":
        cmd_stats()


if __name__ == "__main__":
    main()