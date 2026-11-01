import os
from PySide6.QtCore import Qt
from PySide6.QtGui import QPixmap, QImage, QPainter, QPainterPath, QImageReader
from PySide6.QtQuick import QQuickImageProvider

class ThumbnailProvider(QQuickImageProvider):
    def __init__(self, db, thumb_mgr):
        super().__init__(QQuickImageProvider.ImageType.Pixmap)
        self.db = db
        self.thumb_mgr = thumb_mgr

    def requestPixmap(self, id_str: str, size, requestedSize) -> QPixmap:
        try:
            image_id = int(id_str.split('?')[0])
            path = self.db.get_image_path(image_id)
            if not path or not os.path.exists(path):
                return QPixmap()

            thumb_path = self.thumb_mgr.get_or_generate_thumbnail(path, size=320)
            if thumb_path and os.path.exists(thumb_path):
                return QPixmap(thumb_path)
            reader = QImageReader(path)
            reader.setAutoTransform(True)
            img = reader.read()
            if not img.isNull():
                return QPixmap.fromImage(img)
            return QPixmap(path)
        except Exception as e:
            print(f"[!] ThumbnailProvider error: {e}")
            return QPixmap()


class FaceThumbnailProvider(QQuickImageProvider):
    def __init__(self, db, thumb_mgr):
        super().__init__(QQuickImageProvider.ImageType.Pixmap)
        self.db = db
        self.thumb_mgr = thumb_mgr

    def requestPixmap(self, id_str: str, size, requestedSize) -> QPixmap:
        try:
            face_id = int(id_str.split('?')[0])
            face_path = self.thumb_mgr.get_face_thumb_path(face_id)
            pix = None
            if os.path.exists(face_path):
                pix = QPixmap(face_path)
            else:
                with self.db.get_connection() as conn:
                    cur = conn.cursor()
                    cur.execute("""
                        SELECT f.bbox_x1, f.bbox_y1, f.bbox_x2, f.bbox_y2, i.path 
                        FROM faces f 
                        JOIN images i ON f.image_id = i.id 
                        WHERE f.id = ?
                    """, (face_id,))
                    row = cur.fetchone()
                    if row and row["path"] and os.path.exists(row["path"]):
                        bbox = (row["bbox_x1"], row["bbox_y1"], row["bbox_x2"], row["bbox_y2"])
                        gen = self.thumb_mgr.generate_face_crop(row["path"], face_id, bbox)
                        if gen and os.path.exists(gen):
                            pix = QPixmap(gen)

            if pix and not pix.isNull():
                return self._make_circular_pixmap(pix)
            return QPixmap()
        except Exception as e:
            print(f"[!] FaceThumbnailProvider error: {e}")
            return QPixmap()

    def _make_circular_pixmap(self, src: QPixmap) -> QPixmap:
        w = src.width()
        h = src.height()
        dim = min(w, h)
        out = QPixmap(dim, dim)
        out.fill(Qt.transparent)
        painter = QPainter(out)
        painter.setRenderHint(QPainter.Antialiasing, True)
        painter.setRenderHint(QPainter.SmoothPixmapTransform, True)
        path = QPainterPath()
        path.addEllipse(0, 0, dim, dim)
        painter.setClipPath(path)
        painter.drawPixmap((dim - w) // 2, (dim - h) // 2, src)
        painter.end()
        return out


class RawImageProvider(QQuickImageProvider):
    def __init__(self, db):
        super().__init__(QQuickImageProvider.ImageType.Pixmap)
        self.db = db

    def requestPixmap(self, id_str: str, size, requestedSize) -> QPixmap:
        try:
            image_id = int(id_str.split('?')[0])
            path = self.db.get_image_path(image_id)
            if path and os.path.exists(path):
                reader = QImageReader(path)
                reader.setAutoTransform(True)
                img = reader.read()
                if not img.isNull():
                    return QPixmap.fromImage(img)
                return QPixmap(path)
            return QPixmap()
        except Exception as e:
            print(f"[!] RawImageProvider error: {e}")
            return QPixmap()


class EditPreviewProvider(QQuickImageProvider):
    def __init__(self, editor):
        super().__init__(QQuickImageProvider.ImageType.Pixmap)
        self.editor = editor

    def requestPixmap(self, id_str: str, size, requestedSize) -> QPixmap:
        try:
            image_id = int(id_str.split('?')[0])
            preview_path = os.path.join(self.editor.editor_cache_dir, f"preview_{image_id}.jpg")
            if os.path.exists(preview_path):
                reader = QImageReader(preview_path)
                reader.setAutoTransform(True)
                img = reader.read()
                if not img.isNull():
                    return QPixmap.fromImage(img)
                return QPixmap(preview_path)
            return QPixmap()
        except Exception as e:
            print(f"[!] EditPreviewProvider error: {e}")
            return QPixmap()
