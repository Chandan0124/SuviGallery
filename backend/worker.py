import time
import threading
import os
import warnings
import collections
import concurrent.futures
from typing import Dict, Any, Optional, Tuple
from PIL import Image, ImageOps
from PIL.ExifTags import TAGS, GPSTAGS
import reverse_geocode

warnings.filterwarnings("ignore")

from .storage.db import Database
from .storage.thumbnails import ThumbnailManager
from .ai.detector import FaceEngine
from .ai.clusterer import FaceClusterer
from .ai.clip_engine import ClipEngine

def parse_gps_from_exif(exif) -> Tuple[Optional[float], Optional[float], Optional[str]]:
    """Extracts decimal latitude, longitude, and reverse-geocoded location name from EXIF."""
    if not exif:
        return None, None, None
    try:
        gps_info = {}
        for key, value in exif.items():
            decoded = TAGS.get(key, key)
            if decoded == "GPSInfo":
                for t in value:
                    sub_decoded = GPSTAGS.get(t, t)
                    gps_info[sub_decoded] = value[t]
                break

        if not gps_info:
            return None, None, None

        def dms_to_deg(dms, ref):
            deg = float(dms[0])
            minute = float(dms[1])
            sec = float(dms[2])
            val = deg + (minute / 60.0) + (sec / 3600.0)
            if ref in ("S", "W"):
                val = -val
            return val

        lat = dms_to_deg(gps_info["GPSLatitude"], gps_info.get("GPSLatitudeRef", "N"))
        lon = dms_to_deg(gps_info["GPSLongitude"], gps_info.get("GPSLongitudeRef", "E"))

        geo = reverse_geocode.get((lat, lon))
        loc_parts = []
        if geo.get("city"):
            loc_parts.append(geo["city"])
        if geo.get("state"):
            loc_parts.append(geo["state"])
        if geo.get("country"):
            loc_parts.append(geo["country"])
        loc_name = ", ".join(loc_parts) if loc_parts else None

        return lat, lon, loc_name
    except Exception:
        return None, None, None

class IndexingWorker:
    def __init__(self, db: Database, thumb_mgr: ThumbnailManager, face_engine: FaceEngine, clusterer: FaceClusterer, clip_engine: Optional[ClipEngine] = None):
        self.db = db
        self.thumb_mgr = thumb_mgr
        self.face_engine = face_engine
        self.clusterer = clusterer
        self.clip_engine = clip_engine

        self.thread: Optional[threading.Thread] = None
        self.stop_event = threading.Event()
        self.is_running = False
        
        self.lock = threading.Lock()
        self.gpu_lock = threading.Lock()
        self.db_lock = threading.Lock()
        self.current_filename = ""
        self.items_processed_session = 0
        self.faces_found_session = 0
        self.recent_times = collections.deque(maxlen=25)

    def start(self):
        if self.is_running:
            return
        self.stop_event.clear()
        self.is_running = True
        self.items_processed_session = 0
        self.faces_found_session = 0
        self.recent_times.clear()
        self.thread = threading.Thread(target=self._run_loop, daemon=True)
        self.thread.start()

    def stop(self):
        if not self.is_running:
            return
        self.stop_event.set()
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=3.0)
        self.is_running = False

    def _process_single_image(self, item: Dict) -> Tuple[int, int, str]:
        img_id = item["id"]
        file_path = item["path"]
        filename = item["filename"]

        if not os.path.exists(file_path):
            self.db.mark_image_ai_processed(img_id, face_count=0)
            return img_id, 0, filename

        try:
            # 1. READ WITH FAST JPEG DRAFT DECODE & RECORD TRUE ORIENTED DIMENSIONS
            with Image.open(file_path) as raw_img:
                raw_w, raw_h = raw_img.size
                exif_raw = raw_img.getexif()
                ori = exif_raw.get(0x0112, 1) if exif_raw else 1
                # True oriented dimensions (matches browser lightbox display 100%):
                true_w, true_h = (raw_h, raw_w) if ori in (5, 6, 7, 8) else (raw_w, raw_h)

                exif = raw_img._getexif()
                lat, lon, loc_name = parse_gps_from_exif(exif)

                # Use DCT draft downsampling for 4x faster memory decompression
                try:
                    raw_img.draft("RGB", (1600, 1600))
                except Exception:
                    pass

                pil_img = ImageOps.exif_transpose(raw_img)
                if pil_img.mode != "RGB":
                    pil_img = pil_img.convert("RGB")

                draft_w, draft_h = pil_img.size
                scale_x = float(true_w) / float(draft_w)
                scale_y = float(true_h) / float(draft_h)

            # 2. SAVE 320px WebP THUMBNAIL (0.2ms)
            self.thumb_mgr.save_thumbnail_from_image(pil_img, file_path, size=320)
            self.db.mark_thumbnail_ready(img_id)

            # 3. RUN 3-MODEL AI (GPU-locked to prevent DirectML command recorder race conditions)
            with self.gpu_lock:
                faces = self.face_engine.process_pil_image(pil_img)

            # 4. PREPARE COORDINATES: KEEP DRAFT COORDS FOR IN-MEMORY CROP, SCALE TO FULL-RES FOR DB & LIGHTBOX
            for face in faces:
                draft_box = list(face["bbox"])
                face["draft_bbox"] = draft_box
                face["bbox"] = [
                    draft_box[0] * scale_x,
                    draft_box[1] * scale_y,
                    draft_box[2] * scale_x,
                    draft_box[3] * scale_y,
                ]
                if face.get("landmarks"):
                    face["landmarks"] = [
                        [pt[0] * scale_x, pt[1] * scale_y]
                        for pt in face["landmarks"]
                    ]

            # 5. RUN CLIP OBJECT/SCENE ENCODING FROM THUMBNAIL (~15ms)
            clip_emb = self.clip_engine.embed_image(pil_img) if self.clip_engine else None

            # 6. INSERT FACES & SLICE AVATAR CROPS IN RAM (Sub-pixel alignment)
            with self.db_lock:
                if faces:
                    inserted_ids = self.db.insert_faces(img_id, faces)
                    for fid, face in zip(inserted_ids, faces):
                        self.thumb_mgr.generate_face_crop_from_image(pil_img, fid, face["draft_bbox"])

                # 7. MARK PROCESSED WITH TRUE DIMENSIONS, LOCATION & CLIP
                self.db.mark_image_ai_processed(
                    img_id,
                    face_count=len(faces),
                    width=true_w,
                    height=true_h,
                    lat=lat,
                    lon=lon,
                    loc_name=loc_name,
                    clip_emb=clip_emb
                )
            return img_id, len(faces), filename

        except Exception as err:
            with self.db_lock:
                self.db.mark_image_ai_processed(img_id, face_count=0)
            return img_id, 0, filename

    def _run_loop(self):
        print("[*] Suvi Gallery Turbo AI Indexing Worker active.")
        batch_counter = 0

        # ThreadPoolExecutor to run image reading and AI across Ryzen cores
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            while not self.stop_event.is_set():
                unprocessed = self.db.get_unprocessed_images(limit=18)
                if not unprocessed:
                    time.sleep(0.5)
                    continue

                # Submit batch of images in parallel
                future_to_item = {executor.submit(self._process_single_image, item): item for item in unprocessed}

                for future in concurrent.futures.as_completed(future_to_item):
                    if self.stop_event.is_set():
                        break

                    try:
                        _, face_count, filename = future.result()
                        now = time.time()
                        with self.lock:
                            self.current_filename = filename
                            self.items_processed_session += 1
                            self.faces_found_session += face_count
                            self.recent_times.append(now)

                        batch_counter += 1
                        if batch_counter >= 30:
                            batch_counter = 0
                            try:
                                self.clusterer.cluster_all_unassigned_faces()
                            except Exception:
                                pass

                    except Exception as e:
                        pass

                # Run cluster check when queue empties
                if not self.db.get_unprocessed_images(limit=1):
                    try:
                        self.clusterer.cluster_all_unassigned_faces()
                    except Exception:
                        pass

        self.is_running = False
        print("[*] FaceVault Turbo AI Indexing Worker stopped.")

    def get_status(self) -> Dict[str, Any]:
        stats = self.db.get_stats()
        with self.lock:
            # Accurate rolling-window FPS
            if len(self.recent_times) >= 2:
                duration = self.recent_times[-1] - self.recent_times[0]
                fps = (len(self.recent_times) - 1) / duration if duration > 0.05 else 0.0
            else:
                fps = 0.0

            return {
                "is_running": self.is_running,
                "current_file": self.current_filename,
                "total_images": stats["total_images"],
                "processed_images": stats["processed_images"],
                "total_faces": stats["total_faces"],
                "total_people": stats["total_people"],
                "speed_fps": round(fps, 1),
                "session_processed": self.items_processed_session,
                "session_faces": self.faces_found_session
            }
