import os
import sys
import subprocess
import threading
import webbrowser
from typing import Optional, List
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, Response, JSONResponse
from pydantic import BaseModel

from .config import DB_PATH, CACHE_DIR, BASE_DIR, FRONTEND_DIR, CLIP_DIR, SERVER_HOST, SERVER_PORT
from .storage.db import Database
from .storage.thumbnails import ThumbnailManager
from .storage.scanner import DirectoryScanner
from .ai.detector import FaceEngine
from .ai.clusterer import FaceClusterer
from .ai.clip_engine import ClipEngine
from .worker import IndexingWorker

app = FastAPI(title="Suvi Gallery Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def add_no_cache_headers(request, call_next):
    response = await call_next(request)
    if request.url.path.endswith((".html", ".js", ".css")) or request.url.path in ("/", ""):
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
    return response

# Initialize subsystems
db = Database(DB_PATH)
thumb_mgr = ThumbnailManager(CACHE_DIR)
scanner = DirectoryScanner(db)

print("[*] Loading Face Engine (InsightFace + DirectML/CPU)...")
face_engine = FaceEngine(root_dir=BASE_DIR)
clusterer = FaceClusterer(db)

print("[*] Loading CLIP Semantic Engine...")
clip_engine = ClipEngine(models_dir=CLIP_DIR)

worker = IndexingWorker(db, thumb_mgr, face_engine, clusterer, clip_engine=clip_engine)

# Start background worker automatically
worker.start()

class ScanRequest(BaseModel):
    folder_path: str

class RenamePersonRequest(BaseModel):
    name: str

class MergePeopleRequest(BaseModel):
    source_id: int
    target_id: int

class CombinePeopleRequest(BaseModel):
    source_ids: List[int]
    target_name: str

class TagFaceRequest(BaseModel):
    face_id: int
    person_name: str

class ImageBatchRequest(BaseModel):
    image_ids: List[int]
    target: Optional[str] = "desktop"

@app.get("/api/status")
def get_status():
    status = worker.get_status()
    status["current_folder"] = db.get_setting("current_folder", "")
    status["is_scanning"] = scanner.is_scanning
    return status

@app.post("/api/pick_folder")
def pick_folder():
    """Opens native Windows folder picker dialog and returns selected path."""
    try:
        cmd = [
            sys.executable,
            "-c",
            "import tkinter as tk, tkinter.filedialog as fd; root = tk.Tk(); root.withdraw(); root.wm_attributes('-topmost', 1); path = fd.askdirectory(); print(path)"
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        selected_path = result.stdout.strip()
        if selected_path and os.path.isdir(selected_path):
            return {"folder_path": selected_path}
        return {"folder_path": None}
    except Exception as e:
        return {"error": str(e), "folder_path": None}

@app.post("/api/scan")
def start_scan(req: ScanRequest):
    folder = req.folder_path.strip()
    if not os.path.isdir(folder):
        raise HTTPException(status_code=400, detail="Directory does not exist")

    def run_scan():
        scanner.scan_directory(folder)

    thread = threading.Thread(target=run_scan, daemon=True)
    thread.start()
    return {"status": "started", "folder": folder}

@app.post("/api/scan/stop")
def stop_scan():
    scanner.stop()
    return {"status": "stopped"}

@app.get("/api/folders")
def list_folders():
    with db.get_connection() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT 
                directory,
                COUNT(*) as photo_count,
                SUM(face_count) as face_count,
                MAX(id) as cover_image_id
            FROM images
            GROUP BY directory
            ORDER BY photo_count DESC
        """)
        rows = cur.fetchall()
        folders = []
        for r in rows:
            dir_path = r["directory"]
            name = os.path.basename(dir_path) or dir_path
            folders.append({
                "directory": dir_path,
                "name": name,
                "photo_count": r["photo_count"],
                "face_count": r["face_count"] or 0,
                "cover_image_id": r["cover_image_id"]
            })
        return {"folders": folders}

@app.post("/api/library/reset")
def reset_library():
    """Wipes the database and thumbnail cache to start indexing 100% fresh."""
    with db.get_connection() as conn:
        conn.execute("DELETE FROM faces")
        conn.execute("DELETE FROM people")
        conn.execute("DELETE FROM images")
        conn.execute("DELETE FROM sqlite_sequence WHERE name IN ('faces', 'people', 'images')")
        conn.commit()
    for folder in [thumb_mgr.thumbs_dir, thumb_mgr.faces_dir]:
        if os.path.exists(folder):
            for f in os.listdir(folder):
                try:
                    os.remove(os.path.join(folder, f))
                except Exception:
                    pass
    return {"status": "ok", "message": "Library reset successfully"}

@app.get("/api/photos")
def list_photos(
    page: int = Query(1, ge=1),
    limit: int = Query(60, ge=1, le=500),
    person_id: Optional[int] = None,
    person_ids: Optional[str] = None,
    person_mode: Optional[str] = "together",
    folder: Optional[str] = None,
    search: Optional[str] = None
):
    offset = (page - 1) * limit
    params = []
    where_clauses = []

    # Multi-person filter logic (Together / Strictly ONLY Them / Either)
    p_ids = []
    if person_ids:
        p_ids = [int(x.strip()) for x in person_ids.split(",") if x.strip().isdigit()]
    elif person_id is not None:
        p_ids = [person_id]

    if p_ids:
        mode = (person_mode or "together").lower()
        if mode == "together":
            # Photo must contain ALL selected people (plus anyone else)
            for pid in p_ids:
                where_clauses.append("id IN (SELECT image_id FROM faces WHERE person_id = ?)")
                params.append(pid)
        elif mode == "only":
            # Strictly ONLY the selected people (no untagged faces, no other recognized people)
            for pid in p_ids:
                where_clauses.append("id IN (SELECT image_id FROM faces WHERE person_id = ?)")
                params.append(pid)
            placeholders = ",".join("?" for _ in p_ids)
            where_clauses.append(f"id NOT IN (SELECT image_id FROM faces WHERE person_id IS NULL OR person_id NOT IN ({placeholders}))")
            params.extend(p_ids)
        elif mode == "either":
            # Photo contains AT LEAST ONE of the selected people
            placeholders = ",".join("?" for _ in p_ids)
            where_clauses.append(f"id IN (SELECT image_id FROM faces WHERE person_id IN ({placeholders}))")
            params.extend(p_ids)

    # Folder filter logic
    if folder:
        f_clean = folder.strip()
        f_prefix_fwd = f_clean.rstrip("/\\") + "/%"
        f_prefix_win = f_clean.rstrip("/\\") + "\\%"
        where_clauses.append("(directory = ? OR directory LIKE ? OR directory LIKE ?)")
        params.extend([f_clean, f_prefix_fwd, f_prefix_win])

    if search:
        search_term = search.strip()
        s = f"%{search_term}%"

        # 1. Run CLIP Semantic Object & Scene Search
        clip_matching_ids = []
        if clip_engine and clip_engine.is_ready:
            all_clips = db.get_all_clip_embeddings()
            if all_clips:
                clip_matching_ids = clip_engine.search(search_term, all_clips, top_k=200, threshold=0.20)

        # 2. Hybrid SQL match (Keyword + Location + Date + Person + CLIP semantic match)
        if clip_matching_ids:
            placeholders = ",".join("?" for _ in clip_matching_ids)
            where_clauses.append(f"""(
                filename LIKE ? OR directory LIKE ? OR date_taken LIKE ? OR location_name LIKE ? 
                OR id IN ({placeholders})
                OR id IN (
                    SELECT f.image_id FROM faces f 
                    JOIN people p ON f.person_id = p.id 
                    WHERE p.name LIKE ?
                )
            )""")
            params.extend([s, s, s, s] + clip_matching_ids + [s])
        else:
            where_clauses.append("""(
                filename LIKE ? OR directory LIKE ? OR date_taken LIKE ? OR location_name LIKE ? OR id IN (
                    SELECT f.image_id FROM faces f 
                    JOIN people p ON f.person_id = p.id 
                    WHERE p.name LIKE ?
                )
            )""")
            params.extend([s, s, s, s, s])

    where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

    with db.get_connection() as conn:
        cur = conn.cursor()
        count_sql = f"SELECT COUNT(*) FROM images {where_sql}"
        cur.execute(count_sql, params)
        total_items = cur.fetchone()[0]

        query_sql = f"""
            SELECT id, path, filename, directory, file_size, width, height, date_taken, latitude, longitude, location_name, thumb_ready, ai_processed, face_count
            FROM images
            {where_sql}
            ORDER BY id DESC
            LIMIT ? OFFSET ?
        """
        cur.execute(query_sql, params + [limit, offset])
        items = [dict(r) for r in cur.fetchall()]

    return {
        "items": items,
        "page": page,
        "limit": limit,
        "total": total_items,
        "total_pages": (total_items + limit - 1) // limit if total_items > 0 else 1
    }

@app.get("/api/photos/{image_id}/faces")
def get_photo_faces(image_id: int):
    with db.get_connection() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT f.id, f.bbox_x1, f.bbox_y1, f.bbox_x2, f.bbox_y2, f.confidence, f.gender, f.age, f.person_id, p.name as person_name
            FROM faces f
            LEFT JOIN people p ON f.person_id = p.id
            WHERE f.image_id = ?
        """, (image_id,))
        faces = [dict(r) for r in cur.fetchall()]
        return {"faces": faces}

@app.get("/api/people")
def list_people():
    with db.get_connection() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT id, name, avatar_face_id, face_count, photo_count, created_at, updated_at
            FROM people
            WHERE face_count > 0
            ORDER BY photo_count DESC, face_count DESC
        """)
        return {"people": [dict(r) for r in cur.fetchall()]}

@app.post("/api/people/{person_id}/name")
def rename_person(person_id: int, req: RenamePersonRequest):
    new_name = req.name.strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="Name cannot be empty")
    db.update_person_name(person_id, new_name)
    return {"status": "ok", "person_id": person_id, "name": new_name}

@app.post("/api/people/merge")
def merge_people(req: MergePeopleRequest):
    if req.source_id == req.target_id:
        raise HTTPException(status_code=400, detail="Source and target must be different")
    db.merge_people(req.source_id, req.target_id)
    return {"status": "ok", "merged_into": req.target_id}

@app.post("/api/people/combine")
def combine_people(req: CombinePeopleRequest):
    if not req.source_ids:
        raise HTTPException(status_code=400, detail="No people selected to combine")
    name = req.target_name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name cannot be empty")
    target_id = db.combine_multiple_people(req.source_ids, name)
    return {"status": "ok", "target_id": target_id, "name": name}

@app.post("/api/faces/tag")
def tag_face(req: TagFaceRequest):
    name = req.person_name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name cannot be empty")
    person_id = db.create_or_get_person(name, avatar_face_id=req.face_id)
    db.assign_faces_to_person([req.face_id], person_id)
    return {"status": "ok", "person_id": person_id, "face_id": req.face_id}

@app.post("/api/cluster/run")
def trigger_cluster():
    res = clusterer.cluster_all_unassigned_faces()
    return {"status": "ok", "result": res}

@app.get("/api/thumbnail/photo/{image_id}")
def get_photo_thumbnail(image_id: int):
    with db.get_connection() as conn:
        cur = conn.cursor()
        cur.execute("SELECT path FROM images WHERE id = ?", (image_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Image not found")
        file_path = row["path"]

    thumb_path = thumb_mgr.get_or_generate_thumbnail(file_path, size=320)
    if thumb_path and os.path.exists(thumb_path):
        return FileResponse(thumb_path, media_type="image/webp", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    
    if os.path.exists(file_path):
        return FileResponse(file_path, headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    raise HTTPException(status_code=404, detail="File missing")

@app.get("/api/thumbnail/face/{face_id}")
def get_face_thumbnail(face_id: int):
    face_path = thumb_mgr.get_face_thumb_path(face_id)
    if os.path.exists(face_path):
        return FileResponse(face_path, media_type="image/webp", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})

    with db.get_connection() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT f.bbox_x1, f.bbox_y1, f.bbox_x2, f.bbox_y2, i.path 
            FROM faces f 
            JOIN images i ON f.image_id = i.id 
            WHERE f.id = ?
        """, (face_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Face not found")
        bbox = (row["bbox_x1"], row["bbox_y1"], row["bbox_x2"], row["bbox_y2"])
        generated = thumb_mgr.generate_face_crop(row["path"], face_id, bbox)
        if generated and os.path.exists(generated):
            return FileResponse(generated, media_type="image/webp", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})

    raise HTTPException(status_code=404, detail="Face thumbnail unavailable")

@app.get("/api/raw_image/{image_id}")
def get_raw_image(image_id: int):
    with db.get_connection() as conn:
        cur = conn.cursor()
        cur.execute("SELECT path FROM images WHERE id = ?", (image_id,))
        row = cur.fetchone()
        if not row or not os.path.exists(row["path"]):
            raise HTTPException(status_code=404, detail="Image not found")
        return FileResponse(row["path"])

@app.post("/api/reveal")
def reveal_file(image_id: int = Query(...)):
    with db.get_connection() as conn:
        cur = conn.cursor()
        cur.execute("SELECT path FROM images WHERE id = ?", (image_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Image not found")
        resolved = os.path.abspath(row["path"])
        subprocess.Popen(f'explorer.exe /select,"{resolved}"', shell=True)
        return {"status": "revealed", "path": resolved}

def set_windows_clipboard_files(file_paths: List[str]) -> bool:
    valid_paths = [os.path.abspath(p) for p in file_paths if os.path.exists(p)]
    if not valid_paths:
        return False
    ps_paths = ", ".join([f"'{p.replace(chr(39), chr(39)+chr(39))}'" for p in valid_paths])
    ps_cmd = (
        f"Add-Type -AssemblyName System.Windows.Forms; "
        f"$col = New-Object System.Collections.Specialized.StringCollection; "
        f"$paths = @({ps_paths}); "
        f"foreach ($p in $paths) {{ $col.Add($p) }}; "
        f"[System.Windows.Forms.Clipboard]::SetFileDropList($col);"
    )
    res = subprocess.run(["powershell", "-Sta", "-Command", ps_cmd], capture_output=True, text=True)
    return res.returncode == 0

def open_whatsapp_app_or_web(target: str = "desktop") -> str:
    if target == "web":
        webbrowser.open("https://web.whatsapp.com")
        return "web"
    else:
        try:
            os.startfile("whatsapp://")
            return "desktop"
        except Exception:
            webbrowser.open("https://web.whatsapp.com")
            return "web"

@app.post("/api/photos/share/whatsapp")
def share_photos_whatsapp(req: ImageBatchRequest):
    if not req.image_ids:
        raise HTTPException(status_code=400, detail="No image IDs provided")

    with db.get_connection() as conn:
        cur = conn.cursor()
        placeholders = ",".join("?" for _ in req.image_ids)
        cur.execute(f"SELECT id, path FROM images WHERE id IN ({placeholders})", req.image_ids)
        rows = cur.fetchall()

    if not rows:
        raise HTTPException(status_code=404, detail="No valid images found")

    paths = [r["path"] for r in rows if os.path.exists(r["path"])]
    if not paths:
        raise HTTPException(status_code=404, detail="Image files do not exist on disk")

    success = set_windows_clipboard_files(paths)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to copy files to Windows clipboard")

    target = req.target or "desktop"
    launched = open_whatsapp_app_or_web(target)
    target_name = "WhatsApp Desktop" if launched == "desktop" else "WhatsApp Web"

    return {
        "status": "ok",
        "action": "whatsapp",
        "target": launched,
        "count": len(paths),
        "message": f"Copied {len(paths)} photo{'s' if len(paths) > 1 else ''} to clipboard! Opening {target_name}... Press Ctrl+V in your chat."
    }

@app.post("/api/photos/open_gallery")
def open_photos_in_gallery(req: ImageBatchRequest):
    if not req.image_ids:
        raise HTTPException(status_code=400, detail="No image IDs provided")

    with db.get_connection() as conn:
        cur = conn.cursor()
        placeholders = ",".join("?" for _ in req.image_ids)
        cur.execute(f"SELECT id, path FROM images WHERE id IN ({placeholders})", req.image_ids)
        rows = cur.fetchall()

    if not rows:
        raise HTTPException(status_code=404, detail="No valid images found")

    paths = [r["path"] for r in rows if os.path.exists(r["path"])]
    if not paths:
        raise HTTPException(status_code=404, detail="Image files do not exist on disk")

    # If 5 or fewer, open in default system gallery viewer via Windows Desktop Shell
    if len(paths) <= 5:
        # Clear any zombie suspended Windows Photos instances without window handles
        try:
            subprocess.run(
                ["powershell", "-NoProfile", "-Command", "if ((Get-Process Photos -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -eq 0 }).Count -gt 0) { Stop-Process -Name Photos -Force -ErrorAction SilentlyContinue }"],
                capture_output=True,
                timeout=2
            )
        except Exception:
            pass

        opened = 0
        for p in paths:
            try:
                resolved = os.path.abspath(p)
                # Launching via explorer.exe delegates directly to the interactive desktop shell,
                # ensuring the default viewer (Microsoft Photos / Gallery) opens with a full foreground window.
                subprocess.Popen(f'explorer.exe "{resolved}"', shell=True)
                opened += 1
            except Exception as e:
                print(f"[!] Failed to open file in gallery {p}: {e}")

        return {
            "status": "ok",
            "action": "gallery",
            "count": opened,
            "message": f"Opened {opened} photo{'s' if opened > 1 else ''} in default Gallery viewer."
        }
    else:
        # If more than 5, open in Windows Explorer as requested
        resolved = os.path.abspath(paths[0])
        subprocess.Popen(f'explorer.exe /select,"{resolved}"', shell=True)
        return {
            "status": "ok",
            "action": "explorer",
            "count": len(paths),
            "message": f"{len(paths)} photos selected (exceeds 5). Opened in Windows Explorer."
        }

@app.post("/api/photos/clipboard")
def copy_photos_to_clipboard(req: ImageBatchRequest):
    if not req.image_ids:
        raise HTTPException(status_code=400, detail="No image IDs provided")

    with db.get_connection() as conn:
        cur = conn.cursor()
        placeholders = ",".join("?" for _ in req.image_ids)
        cur.execute(f"SELECT id, path FROM images WHERE id IN ({placeholders})", req.image_ids)
        rows = cur.fetchall()

    if not rows:
        raise HTTPException(status_code=404, detail="No valid images found")

    paths = [r["path"] for r in rows if os.path.exists(r["path"])]
    if not paths:
        raise HTTPException(status_code=404, detail="Image files do not exist on disk")

    success = set_windows_clipboard_files(paths)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to copy files to Windows clipboard")

    return {
        "status": "ok",
        "count": len(paths),
        "message": f"Copied {len(paths)} photo{'s' if len(paths) > 1 else ''} to clipboard! Paste (Ctrl+V) anywhere."
    }

if os.path.exists(FRONTEND_DIR):
    app.mount("/", StaticFiles(directory=FRONTEND_DIR, html=True), name="frontend")
