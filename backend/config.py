import os

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKEND_DIR = os.path.join(BASE_DIR, "backend")
FRONTEND_DIR = os.path.join(BASE_DIR, "frontend")
DATA_DIR = BASE_DIR

DB_PATH = os.path.join(DATA_DIR, "facevault.db")
CACHE_DIR = os.path.join(DATA_DIR, ".cache")
MODELS_DIR = os.path.join(DATA_DIR, "models", "buffalo_s")
CLIP_DIR = os.path.join(DATA_DIR, "models", "clip")
EDITOR_DIR = os.path.join(DATA_DIR, "models", "editor")

SERVER_HOST = "127.0.0.1"
SERVER_PORT = 5240
