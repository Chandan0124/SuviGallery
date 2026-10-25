import os
import numpy as np
from PIL import Image
import onnxruntime as ort
from tokenizers import Tokenizer
from typing import List, Dict, Tuple, Optional

CLIP_MEAN = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
CLIP_STD = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)

class ClipEngine:
    def __init__(self, models_dir: str):
        self.models_dir = models_dir
        self.vision_path = os.path.join(models_dir, "vision_model_quantized.onnx")
        self.text_path = os.path.join(models_dir, "text_model_quantized.onnx")
        self.tok_path = os.path.join(models_dir, "tokenizer.json")

        self.is_ready = os.path.exists(self.vision_path) and os.path.exists(self.text_path) and os.path.exists(self.tok_path)
        if not self.is_ready:
            print("[!] CLIP model files not found. CLIP search disabled.")
            return

        # Quantized INT8 models run with AVX2 acceleration on CPUExecutionProvider
        print("[*] Initializing quantized CLIP semantic engine on multi-threaded CPU...")
        self.tokenizer = Tokenizer.from_file(self.tok_path)
        # Enable truncation to max length 77
        self.tokenizer.enable_truncation(max_length=77)
        self.tokenizer.enable_padding(length=77, pad_id=0)

        self.vision_sess = ort.InferenceSession(self.vision_path, providers=["CPUExecutionProvider"])
        self.text_sess = ort.InferenceSession(self.text_path, providers=["CPUExecutionProvider"])
        print("[*] CLIP semantic engine ready.")

    def embed_image(self, pil_img: Image.Image) -> Optional[np.ndarray]:
        if not self.is_ready:
            return None
        try:
            # If high-res, quickly downsample to thumbnail scale to avoid large CPU copies
            if max(pil_img.size) > 380:
                img = pil_img.copy()
                img.thumbnail((320, 320), Image.Resampling.BILINEAR)
            else:
                img = pil_img

            img = img.convert("RGB")
            # Preserve aspect ratio then center crop to 224x224
            w, h = img.size
            scale = 224.0 / min(w, h)
            new_w, new_h = int(w * scale), int(h * scale)
            img = img.resize((new_w, new_h), Image.Resampling.BILINEAR)

            left = (new_w - 224) // 2
            top = (new_h - 224) // 2
            img = img.crop((left, top, left + 224, top + 224))

            arr = np.array(img).astype(np.float32) / 255.0
            arr = (arr - CLIP_MEAN) / CLIP_STD
            arr = np.transpose(arr, (2, 0, 1)) # [3, 224, 224]
            pixel_values = np.expand_dims(arr, 0) # [1, 3, 224, 224]

            out = self.vision_sess.run(None, {"pixel_values": pixel_values})[0]
            vec = out[0].astype(np.float32)
            norm = np.linalg.norm(vec)
            if norm > 0:
                vec /= norm
            return vec
        except Exception as e:
            return None

    def embed_text(self, text: str) -> Optional[np.ndarray]:
        if not self.is_ready:
            return None
        try:
            # Add prompt wrapping if simple query
            prompt = f"a photo of {text.strip()}" if not text.startswith("a photo") else text.strip()
            enc = self.tokenizer.encode(prompt)
            input_ids = np.array([enc.ids], dtype=np.int64)

            out = self.text_sess.run(None, {"input_ids": input_ids})[0]
            vec = out[0].astype(np.float32)
            norm = np.linalg.norm(vec)
            if norm > 0:
                vec /= norm
            return vec
        except Exception:
            return None

    def search(self, query_text: str, photo_items: List[Dict], top_k: int = 100, threshold: float = 0.22) -> List[int]:
        """
        photo_items: list of dicts with 'image_id' and 'embedding' (numpy array)
        Returns list of matching image_ids ranked by similarity.
        """
        if not photo_items or not query_text:
            return []

        q_vec = self.embed_text(query_text)
        if q_vec is None:
            return []

        # Stack image embeddings matrix [N, 512]
        img_matrix = np.stack([p["embedding"] for p in photo_items])
        # Dot product with unit vectors gives cosine similarities
        scores = np.dot(img_matrix, q_vec)

        # Filter by threshold and rank
        results = []
        for idx, score in enumerate(scores):
            if score >= threshold:
                results.append((photo_items[idx]["image_id"], float(score)))

        results.sort(key=lambda x: x[1], reverse=True)
        return [r[0] for r in results[:top_k]]
