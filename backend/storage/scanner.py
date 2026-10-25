import os
import time
from typing import Callable, Optional, Set
from PIL import Image
from PIL.ExifTags import TAGS
from .db import Database

SUPPORTED_EXTENSIONS: Set[str] = {
    ".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tiff"
}

def extract_exif_date_and_dimensions(file_path: str):
    try:
        with Image.open(file_path) as img:
            w, h = img.size
            date_str = None
            exif = img._getexif()
            if exif:
                for tag_id, value in exif.items():
                    tag = TAGS.get(tag_id, tag_id)
                    if tag in ("DateTimeOriginal", "DateTime"):
                        date_str = str(value)
                        break
            return w, h, date_str
    except Exception:
        return None, None, None

class DirectoryScanner:
    def __init__(self, db: Database):
        self.db = db
        self.is_scanning = False
        self.stop_requested = False

    def scan_directory(self, root_dir: str, progress_callback: Optional[Callable[[int, int, str], None]] = None) -> int:
        """
        Recursively scans root_dir, adds/updates images in database.
        progress_callback(scanned_count, added_count, current_file)
        """
        self.is_scanning = True
        self.stop_requested = False
        scanned_count = 0
        added_count = 0

        abs_root = os.path.abspath(root_dir)
        if not os.path.isdir(abs_root):
            self.is_scanning = False
            return 0

        self.db.set_setting("current_folder", abs_root)

        for dirpath, dirnames, filenames in os.walk(abs_root):
            if self.stop_requested:
                break
            
            # Skip hidden / system folders
            dirnames[:] = [d for d in dirnames if not d.startswith(".") and not d.startswith("$")]

            for filename in filenames:
                if self.stop_requested:
                    break

                ext = os.path.splitext(filename)[1].lower()
                if ext in SUPPORTED_EXTENSIONS:
                    scanned_count += 1
                    file_path = os.path.join(dirpath, filename)

                    try:
                        stat = os.stat(file_path)
                        file_size = stat.st_size
                        modified_time = stat.st_mtime
                        
                        # Add image metadata to db
                        img_id = self.db.add_or_update_image(
                            path=file_path,
                            filename=filename,
                            directory=dirpath,
                            file_size=file_size,
                            modified_time=modified_time
                        )
                        added_count += 1

                        if progress_callback and scanned_count % 25 == 0:
                            progress_callback(scanned_count, added_count, filename)

                    except Exception as err:
                        continue

        if progress_callback:
            progress_callback(scanned_count, added_count, "Done")

        self.is_scanning = False
        self.db.set_setting("last_scan_time", str(time.time()))
        return added_count

    def stop(self):
        self.stop_requested = True
