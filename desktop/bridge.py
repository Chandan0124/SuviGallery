import os
import sys
import subprocess
import threading
from typing import List, Optional

from PySide6.QtCore import QObject, Signal, Slot, Property, QUrl, QPoint, Qt, QTimer, QMimeData
from PySide6.QtGui import QDesktopServices, QGuiApplication, QDrag, QPixmap
from PySide6.QtWidgets import QFileDialog

class GalleryBridge(QObject):
    # Signals to QML
    statusChanged = Signal(dict)
    photosLoaded = Signal(list, int, int, int) # items, total, page, total_pages
    foldersLoaded = Signal(list)
    peopleLoaded = Signal(list)
    personFacesLoaded = Signal(int, list) # person_id, faces
    photoFacesLoaded = Signal(int, list) # image_id, faces
    photoLocationUpdated = Signal(int, str) # image_id, new_location
    toastNotification = Signal(str, str) # message, type ('success', 'info', 'warning')

    def __init__(self, db, thumb_mgr, scanner, face_engine, clusterer, clip_engine, worker):
        super().__init__()
        self.db = db
        self.thumb_mgr = thumb_mgr
        self.scanner = scanner
        self.face_engine = face_engine
        self.clusterer = clusterer
        self.clip_engine = clip_engine
        self.worker = worker

        # Status polling timer
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.poll_status)
        self.timer.start(1200)

    @Slot()
    def poll_status(self):
        try:
            status = self.worker.get_status()
            status["current_folder"] = self.db.get_setting("current_folder", "")
            status["is_scanning"] = self.scanner.is_scanning
            self.statusChanged.emit(status)
        except Exception as e:
            print(f"[!] poll_status error: {e}")

    @Slot()
    def pickFolder(self):
        folder = QFileDialog.getExistingDirectory(
            None,
            "Select Photo Folder or Drive to Organize",
            "",
            QFileDialog.ShowDirsOnly
        )
        if folder and os.path.isdir(folder):
            self.scanFolder(folder)

    @Slot(str)
    def scanFolder(self, folder_path: str):
        folder = folder_path.strip()
        if not os.path.isdir(folder):
            self.toastNotification.emit("Folder does not exist", "warning")
            return

        def run():
            self.scanner.scan_directory(folder)
            self.loadFolders()
            self.loadPeople()

        threading.Thread(target=run, daemon=True).start()
        self.toastNotification.emit(f"Scanning started: {os.path.basename(folder) or folder}", "info")

    @Slot(int, int, str, str, str, str)
    def loadPhotos(self, page=1, limit=60, folder="", person_ids="", person_mode="together", search=""):
        offset = (page - 1) * limit
        params = []
        where_clauses = []

        # Multi-person filter logic (Together / Only / Either)
        p_ids = []
        if person_ids:
            p_ids = [int(x.strip()) for x in person_ids.split(",") if x.strip().isdigit()]

        if p_ids:
            mode = (person_mode or "together").lower()
            if mode == "together":
                for pid in p_ids:
                    where_clauses.append("id IN (SELECT image_id FROM faces WHERE person_id = ?)")
                    params.append(pid)
            elif mode == "only":
                for pid in p_ids:
                    where_clauses.append("id IN (SELECT image_id FROM faces WHERE person_id = ?)")
                    params.append(pid)
                placeholders = ",".join("?" for _ in p_ids)
                where_clauses.append(f"id NOT IN (SELECT image_id FROM faces WHERE person_id IS NULL OR person_id NOT IN ({placeholders}))")
                params.extend(p_ids)
            elif mode == "either":
                placeholders = ",".join("?" for _ in p_ids)
                where_clauses.append(f"id IN (SELECT image_id FROM faces WHERE person_id IN ({placeholders}))")
                params.extend(p_ids)

        # Folder filter
        if folder:
            f_clean = folder.strip()
            f_prefix_fwd = f_clean.rstrip("/\\") + "/%"
            f_prefix_win = f_clean.rstrip("/\\") + "\\%"
            where_clauses.append("(directory = ? OR directory LIKE ? OR directory LIKE ?)")
            params.extend([f_clean, f_prefix_fwd, f_prefix_win])

        # Search query (Hybrid Keyword + OpenCLIP Semantic)
        if search and search.strip():
            search_term = search.strip()
            s = f"%{search_term}%"

            clip_matching_ids = []
            if self.clip_engine and self.clip_engine.is_ready:
                all_clips = self.db.get_all_clip_embeddings()
                if all_clips:
                    clip_matching_ids = self.clip_engine.search(search_term, all_clips, top_k=200, threshold=0.20)

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

        with self.db.get_connection() as conn:
            cur = conn.cursor()
            cur.execute(f"SELECT COUNT(*) FROM images {where_sql}", params)
            total = cur.fetchone()[0]

            query_sql = f"""
                SELECT id, path, filename, directory, file_size, width, height, date_taken, location_name, face_count, modified_time
                FROM images
                {where_sql}
                ORDER BY id DESC
                LIMIT ? OFFSET ?
            """
            cur.execute(query_sql, params + [limit, offset])
            items = [dict(r) for r in cur.fetchall()]

        total_pages = (total + limit - 1) // limit if total > 0 else 1
        self.photosLoaded.emit(items, total, page, total_pages)

    @Slot()
    def loadFolders(self):
        with self.db.get_connection() as conn:
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
            self.foldersLoaded.emit(folders)

    @Slot()
    def loadPeople(self):
        with self.db.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("""
                SELECT id, name, avatar_face_id, face_count, photo_count
                FROM people
                WHERE face_count > 0
                ORDER BY photo_count DESC, face_count DESC
            """)
            self.peopleLoaded.emit([dict(r) for r in cur.fetchall()])

    @Slot(int)
    def loadPhotoFaces(self, image_id: int):
        with self.db.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("""
                SELECT f.id, f.bbox_x1, f.bbox_y1, f.bbox_x2, f.bbox_y2, f.confidence, f.gender, f.age, f.person_id, p.name as person_name
                FROM faces f
                LEFT JOIN people p ON f.person_id = p.id
                WHERE f.image_id = ?
                ORDER BY (f.person_id IS NOT NULL) DESC, f.id ASC
            """, (image_id,))
            raw_faces = [dict(r) for r in cur.fetchall()]

            # Runtime deduplication safeguard against overlapping duplicate bounding boxes
            unique_faces = []
            for f in raw_faces:
                is_dup = False
                for uf in unique_faces:
                    inter_x1 = max(f["bbox_x1"], uf["bbox_x1"])
                    inter_y1 = max(f["bbox_y1"], uf["bbox_y1"])
                    inter_x2 = min(f["bbox_x2"], uf["bbox_x2"])
                    inter_y2 = min(f["bbox_y2"], uf["bbox_y2"])
                    if inter_x2 > inter_x1 and inter_y2 > inter_y1:
                        inter_area = (inter_x2 - inter_x1) * (inter_y2 - inter_y1)
                        f_area = (f["bbox_x2"] - f["bbox_x1"]) * (f["bbox_y2"] - f["bbox_y1"])
                        uf_area = (uf["bbox_x2"] - uf["bbox_x1"]) * (uf["bbox_y2"] - uf["bbox_y1"])
                        if f_area > 0 and uf_area > 0:
                            iou = inter_area / float(f_area + uf_area - inter_area)
                            if iou > 0.80:
                                is_dup = True
                                break
                if not is_dup:
                    unique_faces.append(f)

            self.photoFacesLoaded.emit(image_id, unique_faces)

    @Slot(int, str)
    def renamePerson(self, person_id: int, new_name: str):
        trimmed = new_name.strip()
        if not trimmed:
            return
        self.db.update_person_name(person_id, trimmed)
        self.loadPeople()
        self.toastNotification.emit(f"Renamed person to '{trimmed}'", "success")

    @Slot(int)
    def loadPersonFaces(self, person_id: int):
        faces = self.db.get_person_faces(person_id, limit=80)
        self.personFacesLoaded.emit(person_id, faces)

    @Slot(int, int)
    def setPersonAvatar(self, person_id: int, face_id: int):
        self.db.update_person_avatar(person_id, face_id)
        self.loadPeople()
        self.toastNotification.emit("Default profile picture updated!", "success")

    @Slot(int, int)
    def mergePeople(self, source_id: int, target_id: int):
        if source_id == target_id:
            return
        self.db.merge_people(source_id, target_id)
        self.loadPeople()
        self.toastNotification.emit("Merged person successfully", "success")

    @Slot(list, str)
    def combinePeople(self, source_ids: list, target_name: str):
        trimmed = target_name.strip()
        if not trimmed or not source_ids:
            return
        self.db.combine_multiple_people(source_ids, trimmed)
        self.loadPeople()
        self.toastNotification.emit(f"Combined {len(source_ids)} groups into '{trimmed}'", "success")

    @Slot(int, str)
    def tagFace(self, face_id: int, person_name: str):
        trimmed = person_name.strip()
        if not trimmed:
            return
        person_id = self.db.create_or_get_person(trimmed, avatar_face_id=face_id)
        self.db.assign_faces_to_person([face_id], person_id)
        self.loadPeople()
        self.toastNotification.emit(f"Tagged as '{trimmed}'", "success")

    @Slot(int, str)
    def updatePhotoLocation(self, image_id: int, new_location: str):
        trimmed = new_location.strip()
        self.db.update_photo_location(image_id, trimmed)
        self.photoLocationUpdated.emit(image_id, trimmed)
        if trimmed:
            self.toastNotification.emit(f"Location updated to '{trimmed}'", "info")
        else:
            self.toastNotification.emit("Location cleared", "info")

    @Slot()
    def runClustering(self):
        res = self.clusterer.cluster_all_unassigned_faces()
        self.loadPeople()
        self.toastNotification.emit(f"Clustering complete: {res.get('assigned_clusters', 0)} groups identified", "success")

    # ========================================================
    # Library Catalog Removal (Keeps disk files intact)
    # ========================================================
    @Slot(list)
    def removePhotosFromLibrary(self, image_ids: list):
        if not image_ids:
            return
        clean_ids = [int(x) for x in image_ids if str(x).isdigit()]
        if not clean_ids:
            return

        def run():
            count, face_ids = self.db.remove_images(clean_ids)
            self.thumb_mgr.remove_thumbnails(clean_ids, face_ids)
            self.toastNotification.emit(f"Removed {count} photo{'s' if count != 1 else ''} from library", "info")
            self.loadFolders()
            self.loadPeople()
            self.poll_status()

        threading.Thread(target=run, daemon=True).start()

    @Slot(str)
    def removeFolderFromLibrary(self, folder_path: str):
        if not folder_path or not folder_path.strip():
            return
        folder_clean = folder_path.strip()

        def run():
            count, face_ids = self.db.remove_folder(folder_clean)
            folder_name = os.path.basename(folder_clean) or folder_clean
            self.toastNotification.emit(f"Removed folder '{folder_name}' ({count} photos) from library", "info")
            self.loadFolders()
            self.loadPeople()
            self.poll_status()

        threading.Thread(target=run, daemon=True).start()

    # ========================================================
    # Native Win32 OLE Multi-File Drag & Drop (CF_HDROP)
    # ========================================================
    @Slot(list)
    def startNativeDrag(self, image_ids: list):
        if not image_ids:
            return

        paths = self.db.get_image_paths(image_ids)
        if not paths:
            return

        # Prepare OLE MIME data with local file URLs
        mime_data = QMimeData()
        urls = [QUrl.fromLocalFile(p) for p in paths]
        mime_data.setUrls(urls)

        drag = QDrag(QGuiApplication.instance())
        drag.setMimeData(mime_data)

        # Set visual drag thumbnail preview
        first_path = paths[0]
        thumb_path = self.thumb_mgr.get_or_generate_thumbnail(first_path, size=240)
        if thumb_path and os.path.exists(thumb_path):
            pixmap = QPixmap(thumb_path).scaled(100, 100, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            drag.setPixmap(pixmap)
            drag.setHotSpot(QPoint(pixmap.width() // 2, pixmap.height() // 2))

        # Executes true native Windows OLE drag drop across applications
        drag.exec(Qt.DropAction.CopyAction)

    # ========================================================
    # Native "Open in Gallery" (QDesktopServices)
    # ========================================================
    @Slot(list)
    def openInGallery(self, image_ids: list):
        if not image_ids:
            return

        paths = self.db.get_image_paths(image_ids)
        if not paths:
            self.toastNotification.emit("Photos not found on disk", "warning")
            return

        if len(paths) <= 5:
            opened = 0
            for p in paths:
                # QDesktopServices runs in the interactive GUI thread with full foreground focus rights
                success = QDesktopServices.openUrl(QUrl.fromLocalFile(p))
                if success:
                    opened += 1
            self.toastNotification.emit(f"Opened {opened} photo{'s' if opened > 1 else ''} in default Gallery viewer.", "success")
        else:
            # Over 5 items: reveal in Windows File Explorer
            first_resolved = os.path.abspath(paths[0])
            subprocess.Popen(f'explorer.exe /select,"{first_resolved}"', shell=True)
            self.toastNotification.emit(f"Selected {len(paths)} photos (exceeds 5 limit). Opened in Windows Explorer.", "info")

    # ========================================================
    # Native WhatsApp Share & Clipboard Bridge
    # ========================================================
    @Slot(list, str)
    def shareViaWhatsApp(self, image_ids: list, target="desktop"):
        if not image_ids:
            return

        paths = self.db.get_image_paths(image_ids)
        if not paths:
            self.toastNotification.emit("Photos not found on disk", "warning")
            return

        # 1. Native Windows Clipboard copy (CF_HDROP)
        mime_data = QMimeData()
        mime_data.setUrls([QUrl.fromLocalFile(p) for p in paths])
        QGuiApplication.clipboard().setMimeData(mime_data)

        # 2. Launch WhatsApp Desktop or Web
        target_name = "WhatsApp Desktop"
        if target == "web":
            target_name = "WhatsApp Web"
            QDesktopServices.openUrl(QUrl("https://web.whatsapp.com"))
        else:
            try:
                os.startfile("whatsapp://")
            except Exception:
                target_name = "WhatsApp Web"
                QDesktopServices.openUrl(QUrl("https://web.whatsapp.com"))

        count = len(paths)
        self.toastNotification.emit(
            f"Copied {count} photo{'s' if count > 1 else ''} to clipboard! Opening {target_name}... Press Ctrl+V in your chat.",
            "success"
        )

    @Slot(list)
    def copyToClipboard(self, image_ids: list):
        if not image_ids:
            return

        paths = self.db.get_image_paths(image_ids)
        if not paths:
            return

        mime_data = QMimeData()
        mime_data.setUrls([QUrl.fromLocalFile(p) for p in paths])
        QGuiApplication.clipboard().setMimeData(mime_data)

        count = len(paths)
        self.toastNotification.emit(f"Copied {count} photo{'s' if count > 1 else ''} to clipboard! Paste (Ctrl+V) anywhere.", "success")

    @Slot(list)
    def copyFileNames(self, image_ids: list):
        if not image_ids:
            return
        filenames = self.db.get_image_filenames(image_ids)
        if not filenames:
            return
        text = "\n".join(filenames)
        QGuiApplication.clipboard().setText(text)
        count = len(filenames)
        if count == 1:
            self.toastNotification.emit(f"Copied filename: '{filenames[0]}'", "info")
        else:
            self.toastNotification.emit(f"Copied {count} filenames to clipboard!", "info")

    @Slot(list)
    def copyFilePaths(self, image_ids: list):
        if not image_ids:
            return
        paths = self.db.get_image_paths(image_ids)
        if not paths:
            return
        text = "\n".join(paths)
        QGuiApplication.clipboard().setText(text)
        count = len(paths)
        if count == 1:
            self.toastNotification.emit(f"Copied path: '{paths[0]}'", "info")
        else:
            self.toastNotification.emit(f"Copied {count} full paths to clipboard!", "info")

    @Slot(str)
    def copyText(self, text: str):
        if text:
            clean = text.strip()
            QGuiApplication.clipboard().setText(clean)
            self.toastNotification.emit(f"Copied to clipboard: '{clean}'", "info")

    @Slot(str)
    def setWhatsAppMode(self, mode: str):
        mode_clean = "web" if mode == "web" else "desktop"
        self.db.set_setting("whatsapp_mode", mode_clean)
        self.toastNotification.emit(f"WhatsApp mode set to {mode_clean.title()}", "info")

    @Slot(result=str)
    def getWhatsAppMode(self):
        return self.db.get_setting("whatsapp_mode", "desktop")

    @Slot(int)
    def revealInExplorer(self, image_id: int):
        path = self.db.get_image_path(image_id)
        if path and os.path.exists(path):
            resolved = os.path.abspath(path)
            subprocess.Popen(f'explorer.exe /select,"{resolved}"', shell=True)
