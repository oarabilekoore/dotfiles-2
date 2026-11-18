#!/home/oarabile/.local/share/caption-venv/bin/python
"""
Offline batch image captioner for Quickshell Launcher.
Supports both ultra-lightweight ViT-GPT2 models (e.g. cnmoro/tiny-image-captioning, ~105 MB)
and compact multimodal VLMs (e.g. HuggingFaceTB/SmolVLM-256M-Instruct, ~512 MB).

Reads a JSON array of image file paths from stdin (or CLI args) and prints a JSON
object mapping `{path: caption}` to stdout.
"""
import json
import os
import sys
from pathlib import Path

CONFIG_PATH = Path.home() / ".config/quickshell/image_indexer.json"
DEFAULT_MODEL = "HuggingFaceTB/SmolVLM-256M-Instruct"
CAPTION_PROMPT = (
    "Describe this image concisely in one sentence, naming the main subjects, "
    "setting, colors, objects, and visual style."
)


def resolve_model_id() -> str:
    env_model = os.environ.get("QS_CAPTION_MODEL", "").strip()
    if env_model:
        return env_model
    if CONFIG_PATH.is_file():
        try:
            data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            cfg_model = str(data.get("model", "")).strip()
            if cfg_model:
                return cfg_model
        except Exception:
            pass
    return DEFAULT_MODEL


def load_rgb_image(path_str: str, max_side: int = 512):
    from PIL import Image

    with Image.open(path_str) as im:
        rgb = im.convert("RGB")
        w, h = rgb.size
        longest = max(w, h)
        if longest > max_side:
            scale = max_side / float(longest)
            rgb = rgb.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.Resampling.BILINEAR)
        return rgb


def caption_with_smolvlm(model_id: str, paths: list[str]) -> dict[str, str]:
    import torch
    from transformers import AutoModelForImageTextToText, AutoProcessor

    processor = AutoProcessor.from_pretrained(model_id)
    model = AutoModelForImageTextToText.from_pretrained(
        model_id,
        torch_dtype=torch.float32,
    )
    model.eval()

    messages = [
        {
            "role": "user",
            "content": [
                {"type": "image"},
                {"type": "text", "text": CAPTION_PROMPT},
            ],
        }
    ]
    prompt_text = processor.apply_chat_template(messages, add_generation_prompt=True)

    results: dict[str, str] = {}
    for p in paths:
        try:
            img = load_rgb_image(p, max_side=512)
            inputs = processor(text=prompt_text, images=[img], return_tensors="pt")
            with torch.inference_mode():
                generated = model.generate(
                    **inputs,
                    max_new_tokens=48,
                    do_sample=False,
                )
            prompt_len = inputs["input_ids"].shape[1]
            caption = processor.decode(generated[0][prompt_len:], skip_special_tokens=True).strip()
            if caption:
                results[p] = caption
        except Exception as exc:
            sys.stderr.write(f"image_caption: failed on {p}: {exc}\n")
    return results


def caption_with_vit_gpt2(model_id: str, paths: list[str]) -> dict[str, str]:
    import torch
    from transformers import AutoTokenizer, ViTImageProcessor, VisionEncoderDecoderModel

    processor = ViTImageProcessor.from_pretrained(model_id)
    tokenizer = AutoTokenizer.from_pretrained(model_id)
    model = VisionEncoderDecoderModel.from_pretrained(model_id)
    model.eval()

    results: dict[str, str] = {}
    for p in paths:
        try:
            img = load_rgb_image(p, max_side=384)
            pixel_values = processor(images=img, return_tensors="pt").pixel_values
            with torch.inference_mode():
                out_ids = model.generate(
                    pixel_values,
                    max_new_tokens=32,
                    num_beams=1,
                    do_sample=False,
                )
            caption = tokenizer.decode(out_ids[0], skip_special_tokens=True).strip()
            if caption:
                results[p] = caption
        except Exception as exc:
            sys.stderr.write(f"image_caption: failed on {p}: {exc}\n")
    return results


def main() -> None:
    if len(sys.argv) > 1:
        paths = [a for a in sys.argv[1:] if os.path.isfile(a)]
    else:
        raw = sys.stdin.read().strip()
        paths = json.loads(raw) if raw else []
        paths = [p for p in paths if isinstance(p, str) and os.path.isfile(p)]

    if not paths:
        print("{}")
        return

    try:
        import torch  # noqa: F401
        import transformers  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError as exc:
        sys.stderr.write(f"image_caption: missing dependency ({exc}); skipping captions\n")
        print("{}")
        return

    model_id = resolve_model_id()
    lower_id = model_id.lower()

    if "vit-gpt2" in lower_id or "tiny-image-captioning" in lower_id:
        out = caption_with_vit_gpt2(model_id, paths)
    else:
        out = caption_with_smolvlm(model_id, paths)

    print(json.dumps(out))


if __name__ == "__main__":
    main()