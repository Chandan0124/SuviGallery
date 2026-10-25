import os
import hashlib
from PIL import Image, ImageOps
from typing import Optional, Tuple, List

class ThumbnailManager:
    def __init__(self, cache_dir: str):
        self.cache_dir = cache_dir
        self.thumbs_dir = os.path.join(cache_dir, "photos")
        self.faces_dir = os.path.join(cache_dir, "faces")
        os.makedirs(self.thumbs_dir, exist_ok=True)
        os.makedirs(self.faces_dir, exist_ok=True)

    def _get_photo_thumb_path(self, file_path: str, size: int = 320) -> str:
        key = f"{os.path.abspath(file_path)}:{size}"
        hash_str = hashlib.md5(key.encode("utf-8")).hexdigest()
        return os.path.join(self.thumbs_dir, f"{hash_str}.webp")

    def get_face_thumb_path(self, face_id: int) -> str:
        return os.path.join(self.faces_dir, f"face_{face_id}.webp")

    def save_thumbnail_from_image(self, pil_img: Image.Image, file_path: str, size: int = 320) -> Optional[str]:
        """Saves a WebP thumbnail directly from an in-memory PIL image (0 disk re-reads)."""
        thumb_path = self._get_photo_thumb_path(file_path, size)
        if os.path.exists(thumb_path):
            return thumb_path

        try:
            thumb = pil_img.copy()
            if thumb.mode in ("RGBA", "P"):
                thumb = thumb.convert("RGB")
            thumb.thumbnail((size, size), Image.Resampling.LANCZOS)
            thumb.save(thumb_path, "WEBP", quality=80, method=4)
            return thumb_path
        except Exception:
            return None

    def get_or_generate_thumbnail(self, file_path: str, size: int = 320) -> Optional[str]:
        """Generates a WebP thumbnail from file if not already cached."""
        if not os.path.exists(file_path):
            return None
        
        thumb_path = self._get_photo_thumb_path(file_path, size)
        if os.path.exists(thumb_path):
            return thumb_path

        try:
            with Image.open(file_path) as img:
                img = ImageOps.exif_transpose(img)
                return self.save_thumbnail_from_image(img, file_path, size)
        except Exception:
            return None

    def generate_face_crop_from_image(self, pil_img: Image.Image, face_id: int, bbox: Tuple[float, float, float, float], size: int = 140) -> Optional[str]:
        """Crops a face avatar directly from an in-memory PIL image in ~2ms (0 disk re-reads)."""
        face_path = self.get_face_thumb_path(face_id)
        if os.path.exists(face_path):
            return face_path

        try:
            w, h = pil_img.size
            x1, y1, x2, y2 = bbox
            
            bw = x2 - x1
            bh = y2 - y1
            mx = bw * 0.25
            my = bh * 0.25
            
            crop_x1 = max(0, int(x1 - mx))
            crop_y1 = max(0, int(y1 - my))
            crop_x2 = min(w, int(x2 + mx))
            crop_y2 = min(h, int(y2 + my))
            
            cropped = pil_img.crop((crop_x1, crop_y1, crop_x2, crop_y2))
            if cropped.mode in ("RGBA", "P"):
                cropped = cropped.convert("RGB")
            cropped.thumbnail((size, size), Image.Resampling.LANCZOS)
            cropped.save(face_path, "WEBP", quality=85)
            return face_path
        except Exception:
            return None

    def generate_face_crop(self, file_path: str, face_id: int, bbox: Tuple[float, float, float, float], size: int = 140) -> Optional[str]:
        """Fallback to read from file if in-memory image is not supplied."""
        face_path = self.get_face_thumb_path(face_id)
        if os.path.exists(face_path):
            return face_path

        if not os.path.exists(file_path):
            return None

        try:
            with Image.open(file_path) as img:
                img = ImageOps.exif_transpose(img)
                return self.generate_face_crop_from_image(img, face_id, bbox, size)
        except Exception:
            return None

    def remove_thumbnails(self, image_ids: List[int], face_ids: Optional[List[int]] = None):
        """Removes cached thumbnail files for deleted images and faces."""
        for img_id in image_ids:
            p = self.get_thumb_path(img_id)
            if os.path.exists(p):
                try:
                    os.remove(p)
                except Exception:
                    pass
        if face_ids:
            for f_id in face_ids:
                fp = self.get_face_thumb_path(f_id)
                if os.path.exists(fp):
                    try:
                        os.remove(fp)
                    except Exception:
                        pass
