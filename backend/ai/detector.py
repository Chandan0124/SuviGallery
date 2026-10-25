import os
import cv2
import numpy as np
from PIL import Image, ImageOps
from typing import List, Dict, Optional, Tuple
from insightface.app import FaceAnalysis
import onnxruntime as ort

class FaceEngine:
    def __init__(self, root_dir: str):
        self.root_dir = root_dir
        providers = ort.get_available_providers()
        selected_providers = []
        if "DmlExecutionProvider" in providers:
            selected_providers.append("DmlExecutionProvider")
        selected_providers.append("CPUExecutionProvider")

        print(f"[*] Initializing FaceAnalysis (detection + genderage + recognition) with: {selected_providers}")
        self.app = FaceAnalysis(
            name="buffalo_s",
            root=self.root_dir,
            allowed_modules=["detection", "genderage", "recognition"],
            providers=selected_providers
        )
        self.app.prepare(ctx_id=0, det_size=(640, 640))
        print("[*] FaceAnalysis engine ready.")

    def process_pil_image(self, pil_img: Image.Image) -> List[Dict]:
        """
        Processes an in-memory PIL image without reading from disk.
        Accurately maps bounding box coordinates to the exact original pixel dimensions.
        """
        try:
            orig_w, orig_h = pil_img.size

            # Scale to work size (max 1280px) for SCRFD and ArcFace
            max_dim = max(orig_w, orig_h)
            if max_dim > 1280:
                scale = 1280.0 / max_dim
                work_w, work_h = int(orig_w * scale), int(orig_h * scale)
                work_img = pil_img.resize((work_w, work_h), Image.Resampling.BILINEAR)
                scale_x = float(work_w) / float(orig_w)
                scale_y = float(work_h) / float(orig_h)
            else:
                work_img = pil_img
                scale_x = 1.0
                scale_y = 1.0

            if work_img.mode != "RGB":
                work_img = work_img.convert("RGB")

            img_rgb = np.array(work_img)
            img_bgr = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR)

            raw_faces = self.app.get(img_bgr)
            results = []

            for face in raw_faces:
                # Mathematically exact mapping to original image coordinate space
                bbox = [
                    float(face.bbox[0]) / scale_x,
                    float(face.bbox[1]) / scale_y,
                    float(face.bbox[2]) / scale_x,
                    float(face.bbox[3]) / scale_y,
                ]

                if hasattr(face, "kps") and face.kps is not None:
                    landmarks = [
                        [float(pt[0]) / scale_x, float(pt[1]) / scale_y]
                        for pt in face.kps
                    ]
                else:
                    landmarks = []

                score = float(face.det_score) if hasattr(face, "det_score") else 1.0
                embedding = face.embedding
                
                # Normalize embedding
                norm = np.linalg.norm(embedding)
                if norm > 0:
                    embedding = embedding / norm

                # Gender & Age attributes
                raw_gender = getattr(face, "gender", -1)
                gender = "M" if raw_gender == 1 else ("F" if raw_gender == 0 else None)
                age = int(getattr(face, "age", 0)) if hasattr(face, "age") else None

                results.append({
                    "bbox": bbox,
                    "score": score,
                    "landmarks": landmarks,
                    "gender": gender,
                    "age": age,
                    "embedding": embedding
                })

            return results
        except Exception as e:
            print(f"[!] Error processing face image: {e}")
            return []

    def process_image(self, file_path: str) -> List[Dict]:
        """Fallback: loads from disk if PIL image is not provided."""
        if not os.path.exists(file_path):
            return []
        try:
            with Image.open(file_path) as pil_img:
                pil_img = ImageOps.exif_transpose(pil_img)
                return self.process_pil_image(pil_img)
        except Exception:
            return []
