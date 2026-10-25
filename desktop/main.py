import os
import sys

# High DPI and rendering optimizations
os.environ["QT_ENABLE_HIGHDPI_SCALING"] = "1"
os.environ["QT_AUTO_SCREEN_SCALE_FACTOR"] = "1"
os.environ["QT_QUICK_CONTROLS_STYLE"] = "Basic"

# Ensure workspace root is in sys.path
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

import PySide6
pyside_dir = os.path.dirname(PySide6.__file__)
if hasattr(os, "add_dll_directory") and os.path.isdir(pyside_dir):
    try:
        os.add_dll_directory(pyside_dir)
    except Exception as e:
        print(f"Warning adding dll directory: {e}")
os.environ["PATH"] = pyside_dir + os.pathsep + os.environ.get("PATH", "")

from PySide6.QtWidgets import QApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtGui import QIcon
from PySide6.QtQuickControls2 import QQuickStyle

from backend.config import DB_PATH, CACHE_DIR, BASE_DIR, CLIP_DIR
from backend.storage.db import Database
from backend.storage.thumbnails import ThumbnailManager
from backend.storage.scanner import DirectoryScanner
from backend.ai.detector import FaceEngine
from backend.ai.clusterer import FaceClusterer
from backend.ai.clip_engine import ClipEngine
from backend.worker import IndexingWorker

from desktop.image_providers import ThumbnailProvider, FaceThumbnailProvider, RawImageProvider
from desktop.bridge import GalleryBridge

def main():
    print("=" * 60)
    print("  Suvi Gallery - Native AI Photo & Face Organizer (Qt QML)")
    print("=" * 60)

    QQuickStyle.setStyle("Basic")
    app = QApplication(sys.argv)
    app.setApplicationName("Suvi Gallery")
    app.setOrganizationName("SuviAI")

    icon_path = os.path.join(BASE_DIR, "SuviGallery.ico")
    if os.path.exists(icon_path):
        app.setWindowIcon(QIcon(icon_path))

    # Initialize Core Offline Subsystems (Direct in-memory Python, Zero HTTP)
    print("[*] Initializing Database & Thumbnail Pipeline...")
    db = Database(DB_PATH)
    thumb_mgr = ThumbnailManager(CACHE_DIR)
    scanner = DirectoryScanner(db)

    print("[*] Loading Face Engine (InsightFace + DirectML/CPU)...")
    face_engine = FaceEngine(root_dir=BASE_DIR)
    clusterer = FaceClusterer(db)

    print("[*] Loading CLIP Semantic Engine...")
    clip_engine = ClipEngine(models_dir=CLIP_DIR)

    print("[*] Starting Background AI Indexer...")
    worker = IndexingWorker(db, thumb_mgr, face_engine, clusterer, clip_engine=clip_engine)
    worker.start()
    app.aboutToQuit.connect(worker.stop)

    # Create Native Bridge & QML Engine
    bridge = GalleryBridge(db, thumb_mgr, scanner, face_engine, clusterer, clip_engine, worker)

    engine = QQmlApplicationEngine()

    # Register Native Image Providers (Fast, in-memory textures)
    engine.addImageProvider("thumb", ThumbnailProvider(db, thumb_mgr))
    engine.addImageProvider("face", FaceThumbnailProvider(db, thumb_mgr))
    engine.addImageProvider("raw", RawImageProvider(db))

    # Expose Bridge to QML
    engine.rootContext().setContextProperty("gallery", bridge)

    # Load Main Responsive QML Window
    qml_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qml", "Main.qml")
    engine.load(qml_path)

    if not engine.rootObjects():
        print("[!] Fatal: Failed to load QML root object.")
        sys.exit(-1)

    print("[*] Native Suvi Gallery QML Desktop running successfully!")
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
