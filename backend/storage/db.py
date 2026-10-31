import sqlite3
import os
import json
import numpy as np
from typing import List, Dict, Optional, Tuple

class Database:
    def __init__(self, db_path: str):
        self.db_path = db_path
        os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
        self.init_db()

    def get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30.0)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = NORMAL")
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

    def init_db(self):
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """)
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS images (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT UNIQUE NOT NULL,
                filename TEXT NOT NULL,
                directory TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                modified_time REAL NOT NULL,
                width INTEGER,
                height INTEGER,
                date_taken TEXT,
                latitude REAL,
                longitude REAL,
                location_name TEXT,
                clip_embedding BLOB,
                thumb_ready INTEGER DEFAULT 0,
                ai_processed INTEGER DEFAULT 0,
                face_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """)
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS people (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                avatar_face_id INTEGER,
                face_count INTEGER DEFAULT 0,
                photo_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """)
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS faces (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
                person_id INTEGER REFERENCES people(id) ON DELETE SET NULL,
                bbox_x1 REAL NOT NULL,
                bbox_y1 REAL NOT NULL,
                bbox_x2 REAL NOT NULL,
                bbox_y2 REAL NOT NULL,
                confidence REAL NOT NULL,
                landmarks TEXT,
                gender TEXT,
                age INTEGER,
                embedding BLOB NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """)

            # Safe migrations for existing databases
            try:
                cursor.execute("ALTER TABLE faces ADD COLUMN gender TEXT")
            except Exception:
                pass
            try:
                cursor.execute("ALTER TABLE faces ADD COLUMN age INTEGER")
            except Exception:
                pass
            try:
                cursor.execute("ALTER TABLE images ADD COLUMN latitude REAL")
            except Exception:
                pass
            try:
                cursor.execute("ALTER TABLE images ADD COLUMN longitude REAL")
            except Exception:
                pass
            try:
                cursor.execute("ALTER TABLE images ADD COLUMN location_name TEXT")
            except Exception:
                pass
            try:
                cursor.execute("ALTER TABLE images ADD COLUMN clip_embedding BLOB")
            except Exception:
                pass

            # Indices for lightning queries
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_images_path ON images(path)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_images_dir ON images(directory)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_images_date ON images(date_taken)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_images_ai_processed ON images(ai_processed)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_images_loc ON images(location_name)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_faces_image_id ON faces(image_id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_faces_person_id ON faces(person_id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_people_name ON people(name)")
            conn.commit()

    def get_setting(self, key: str, default: Optional[str] = None) -> Optional[str]:
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT value FROM settings WHERE key = ?", (key,))
            row = cur.fetchone()
            return row["value"] if row else default

    def get_image_path(self, image_id: int) -> Optional[str]:
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT path, filename, directory FROM images WHERE id = ?", (image_id,))
            row = cur.fetchone()
            if not row or not row["path"]:
                return None
            path = row["path"]
            if os.path.exists(path):
                return path

            # Resilient auto-healing fallback if folder was moved or drive letter changed
            filename = row["filename"]
            cur.execute("SELECT DISTINCT directory FROM images WHERE directory != ?", (row["directory"],))
            for alt_dir_row in cur.fetchall():
                alt_dir = alt_dir_row["directory"]
                alt_path = os.path.join(alt_dir, filename)
                if os.path.exists(alt_path):
                    try:
                        cur.execute("UPDATE images SET path = ?, directory = ? WHERE id = ?", (alt_path, alt_dir, image_id))
                        conn.commit()
                    except Exception:
                        pass
                    return alt_path
            return None

    def get_image_paths(self, image_ids: List[int]) -> List[str]:
        if not image_ids:
            return []
        resolved_paths = []
        for iid in image_ids:
            p = self.get_image_path(iid)
            if p and os.path.exists(p):
                resolved_paths.append(p)
        return resolved_paths

    def get_image_filenames(self, image_ids: List[int]) -> List[str]:
        if not image_ids:
            return []
        with self.get_connection() as conn:
            cur = conn.cursor()
            placeholders = ",".join("?" for _ in image_ids)
            cur.execute(f"SELECT filename FROM images WHERE id IN ({placeholders})", image_ids)
            return [r["filename"] for r in cur.fetchall() if r["filename"]]

    def set_setting(self, key: str, value: str):
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (key, str(value)))
            conn.commit()

    def add_or_update_image(self, path: str, filename: str, directory: str, file_size: int, modified_time: float, width: Optional[int] = None, height: Optional[int] = None, date_taken: Optional[str] = None) -> int:
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT id, modified_time FROM images WHERE path = ?", (path,))
            existing = cur.fetchone()
            if existing:
                if abs(existing["modified_time"] - modified_time) > 0.01:
                    cur.execute("DELETE FROM faces WHERE image_id = ?", (existing["id"],))
                    cur.execute("""
                        UPDATE images 
                        SET file_size = ?, modified_time = ?, width = ?, height = ?, date_taken = ?, thumb_ready = 0, ai_processed = 0, face_count = 0
                        WHERE id = ?
                    """, (file_size, modified_time, width, height, date_taken, existing["id"]))
                    conn.commit()
                return existing["id"]
            else:
                cur.execute("""
                    INSERT INTO images (path, filename, directory, file_size, modified_time, width, height, date_taken)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (path, filename, directory, file_size, modified_time, width, height, date_taken))
                conn.commit()
                return cur.lastrowid

    def mark_thumbnail_ready(self, image_id: int):
        with self.get_connection() as conn:
            conn.execute("UPDATE images SET thumb_ready = 1 WHERE id = ?", (image_id,))
            conn.commit()

    def get_unprocessed_images(self, limit: int = 50) -> List[Dict]:
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT * FROM images WHERE ai_processed = 0 ORDER BY id ASC LIMIT ?", (limit,))
            return [dict(row) for row in cur.fetchall()]

    def mark_image_ai_processed(self, image_id: int, face_count: int, width: Optional[int] = None, height: Optional[int] = None, lat: Optional[float] = None, lon: Optional[float] = None, loc_name: Optional[str] = None, clip_emb: Optional[np.ndarray] = None):
        with self.get_connection() as conn:
            clip_bytes = clip_emb.astype(np.float32).tobytes() if clip_emb is not None else None
            conn.execute("""
                UPDATE images 
                SET ai_processed = 1, face_count = ?, 
                    width = COALESCE(?, width), height = COALESCE(?, height),
                    latitude = COALESCE(?, latitude), 
                    longitude = COALESCE(?, longitude), location_name = COALESCE(?, location_name),
                    clip_embedding = COALESCE(?, clip_embedding)
                WHERE id = ?
            """, (face_count, width, height, lat, lon, loc_name, clip_bytes, image_id))
            conn.commit()

    def insert_faces(self, image_id: int, detected_faces: List[Dict]) -> List[int]:
        """
        detected_faces: list of dicts with keys: bbox, score, landmarks, gender, age, embedding
        Returns list of inserted face IDs.
        Guarantees idempotency by clearing any previous face records for this image.
        """
        inserted_ids = []
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("DELETE FROM faces WHERE image_id = ?", (image_id,))
            for face in detected_faces:
                emb_bytes = face["embedding"].astype(np.float32).tobytes()
                landmarks_json = json.dumps(face.get("landmarks", []))
                x1, y1, x2, y2 = face["bbox"]
                gender = face.get("gender", None)
                age = face.get("age", None)
                cur.execute("""
                    INSERT INTO faces (image_id, bbox_x1, bbox_y1, bbox_x2, bbox_y2, confidence, landmarks, gender, age, embedding)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (image_id, float(x1), float(y1), float(x2), float(y2), float(face["score"]), landmarks_json, gender, age, emb_bytes))
                inserted_ids.append(cur.lastrowid)
            conn.commit()
        return inserted_ids

    def get_all_face_embeddings(self) -> List[Dict]:
        """Returns face_id, person_id, and 512-d embedding as numpy float32 array"""
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT id, image_id, person_id, embedding FROM faces")
            results = []
            for row in cur.fetchall():
                emb = np.frombuffer(row["embedding"], dtype=np.float32)
                results.append({
                    "id": row["id"],
                    "image_id": row["image_id"],
                    "person_id": row["person_id"],
                    "embedding": emb
                })
            return results

    def get_all_clip_embeddings(self) -> List[Dict]:
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT id, clip_embedding FROM images WHERE clip_embedding IS NOT NULL")
            results = []
            for row in cur.fetchall():
                emb = np.frombuffer(row["clip_embedding"], dtype=np.float32)
                results.append({"image_id": row["id"], "embedding": emb})
            return results

    def create_or_get_person(self, name: str, avatar_face_id: Optional[int] = None) -> int:
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT id FROM people WHERE name = ?", (name,))
            row = cur.fetchone()
            if row:
                return row["id"]
            cur.execute("INSERT INTO people (name, avatar_face_id) VALUES (?, ?)", (name, avatar_face_id))
            conn.commit()
            return cur.lastrowid

    def update_person_name(self, person_id: int, new_name: str):
        with self.get_connection() as conn:
            conn.execute("UPDATE people SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", (new_name.strip(), person_id))
            conn.commit()

    def update_person_avatar(self, person_id: int, face_id: int):
        with self.get_connection() as conn:
            conn.execute("UPDATE people SET avatar_face_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", (face_id, person_id))
            conn.commit()

    def get_person_faces(self, person_id: int, limit: int = 100) -> List[Dict]:
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("""
                SELECT id, image_id, bbox_x1, bbox_y1, bbox_x2, bbox_y2, confidence, gender, age
                FROM faces
                WHERE person_id = ?
                ORDER BY confidence DESC, id DESC
                LIMIT ?
            """, (person_id, limit))
            return [dict(r) for r in cur.fetchall()]

    def update_photo_location(self, image_id: int, new_location: str):
        with self.get_connection() as conn:
            val = new_location.strip() if new_location and new_location.strip() else None
            conn.execute("UPDATE images SET location_name = ? WHERE id = ?", (val, image_id))
            conn.commit()

    def assign_faces_to_person(self, face_ids: List[int], person_id: int):
        with self.get_connection() as conn:
            placeholders = ",".join("?" for _ in face_ids)
            conn.execute(f"UPDATE faces SET person_id = ? WHERE id IN ({placeholders})", [person_id] + face_ids)
            self._refresh_people_counts(conn)
            conn.commit()

    def merge_people(self, source_person_id: int, target_person_id: int):
        with self.get_connection() as conn:
            conn.execute("UPDATE faces SET person_id = ? WHERE person_id = ?", (target_person_id, source_person_id))
            conn.execute("DELETE FROM people WHERE id = ?", (source_person_id,))
            self._refresh_people_counts(conn)
            conn.commit()

    def combine_multiple_people(self, person_ids: List[int], target_name: str) -> int:
        """Combines multiple person clusters into a single person."""
        if not person_ids:
            return 0
        with self.get_connection() as conn:
            cur = conn.cursor()
            target_name = target_name.strip()
            # Check if person with target_name already exists
            cur.execute("SELECT id FROM people WHERE name = ?", (target_name,))
            row = cur.fetchone()
            if row:
                target_id = row["id"]
            else:
                cur.execute("INSERT INTO people (name) VALUES (?)", (target_name,))
                target_id = cur.lastrowid

            placeholders = ",".join("?" for _ in person_ids)
            cur.execute(f"UPDATE faces SET person_id = ? WHERE person_id IN ({placeholders})", [target_id] + person_ids)

            delete_ids = [pid for pid in person_ids if pid != target_id]
            if delete_ids:
                del_placeholders = ",".join("?" for _ in delete_ids)
                cur.execute(f"DELETE FROM people WHERE id IN ({del_placeholders})", delete_ids)

            self._refresh_people_counts(conn)
            conn.commit()
            return target_id

    def _refresh_people_counts(self, conn: sqlite3.Connection):
        conn.execute("""
            UPDATE people 
            SET face_count = (SELECT COUNT(*) FROM faces WHERE faces.person_id = people.id),
                photo_count = (SELECT COUNT(DISTINCT image_id) FROM faces WHERE faces.person_id = people.id)
        """)
        conn.execute("""
            UPDATE people
            SET avatar_face_id = (
                SELECT id FROM faces 
                WHERE faces.person_id = people.id 
                ORDER BY confidence DESC LIMIT 1
            )
            WHERE avatar_face_id IS NULL OR avatar_face_id NOT IN (SELECT id FROM faces WHERE person_id = people.id)
        """)

    def remove_images(self, image_ids: List[int]) -> Tuple[int, List[int]]:
        """Removes images and their faces from database, refreshes people counts and purges empty people."""
        if not image_ids:
            return 0, []
        with self.get_connection() as conn:
            cur = conn.cursor()
            placeholders = ",".join("?" for _ in image_ids)
            
            # Find face_ids to return for thumbnail cache cleanup
            cur.execute(f"SELECT id FROM faces WHERE image_id IN ({placeholders})", image_ids)
            face_ids = [row[0] for row in cur.fetchall()]

            # Delete faces
            cur.execute(f"DELETE FROM faces WHERE image_id IN ({placeholders})", image_ids)

            # Delete images
            cur.execute(f"DELETE FROM images WHERE id IN ({placeholders})", image_ids)
            deleted_count = cur.rowcount

            # Recalculate people counts
            self._refresh_people_counts(conn)

            # Clean up people with 0 faces
            cur.execute("DELETE FROM people WHERE face_count = 0 OR photo_count = 0")
            conn.commit()

            return deleted_count, face_ids

    def remove_folder(self, folder_path: str) -> Tuple[int, List[int]]:
        """Removes all images belonging to folder_path (and its subdirectories) from database."""
        f_clean = folder_path.strip()
        f_prefix_fwd = f_clean.rstrip("/\\") + "/%"
        f_prefix_win = f_clean.rstrip("/\\") + "\\%"
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("""
                SELECT id FROM images 
                WHERE directory = ? OR directory LIKE ? OR directory LIKE ?
            """, (f_clean, f_prefix_fwd, f_prefix_win))
            image_ids = [row[0] for row in cur.fetchall()]

        if not image_ids:
            return 0, []
        return self.remove_images(image_ids)

    def get_stats(self) -> Dict:
        with self.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM images")
            total_images = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM images WHERE ai_processed = 1")
            processed_images = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM faces")
            total_faces = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM people")
            total_people = cur.fetchone()[0]
            return {
                "total_images": total_images,
                "processed_images": processed_images,
                "total_faces": total_faces,
                "total_people": total_people
            }
