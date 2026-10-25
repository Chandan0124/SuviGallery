# Suvi Gallery - Private AI Photo & Face Organizer (100% Free & Offline)

**Suvi Gallery** is a private, hardware-accelerated Windows desktop application that indexes large photo libraries and external drives, automatically detects faces, clusters individuals with ArcFace embeddings, provides semantic object/scene search via OpenCLIP, and allows instant search by person, folder, and multi-person relational filters.

---

## Key Features

- **Blazing Fast Ingestion**: Scans thousands of photos across drives in seconds with hardware DCT decompression.
- **Hardware-Accelerated Face AI**: Uses **SCRFD Face Detection**, **Gender & Age estimation**, and **ArcFace Recognition** running on DirectML / NVIDIA GPU & multi-threaded Ryzen CPU.
- **Natural Language Semantic Search**: Search scenes and objects (*"cake"*, *"dog"*, *"beach sunset"*) via quantized **OpenCLIP (ViT-B/32)**.
- **Dedicated Folder View & Album Cards**: Browse and filter by folders with cover previews and quick dropdown switching.
- **Multi-Person Relational Filters**: Filter photos with multiple people using **Together (AND)**, **Strictly ONLY Them** (no photobombers), or **Either (OR)**.
- **DBSCAN Face Clustering**: Automatically groups faces into individuals without requiring manual setup.
- **WebP Thumbnail Pipeline**: Generates instant, lightweight WebP thumbnails with cache-busting so 100,000+ photos scroll smoothly at 60 FPS.
- **Multi-Photo Selection & WhatsApp Sharing**: Multi-select photos with hover checkboxes or Shift+Click range selection. Share directly via **WhatsApp Desktop** (or **WhatsApp Web**) with automatic clipboard bridging (`CF_HDROP`) so you can simply press `Ctrl+V` in any chat.
- **Native System Gallery & Explorer**: Open single or up to 5 photos directly in your Windows default Gallery viewer (`os.startfile`), or reveal large selections (>5 photos) in Windows Explorer.
- **Interactive Lightbox**: Inspect photos with sub-pixel accurate face detection boxes, gender/age badges, instant naming, and direct WhatsApp / Gallery quick buttons.
- **100% Free & Private**: No cloud APIs, no subscriptions, zero data leaves your PC. Your original files on drive `E:\` are never modified.

---

## Quick Start

1. Double-click **`SuviGallery.bat`** (or `FaceVault.bat`) to launch.
2. Click **"Add Folder"** at the top right to select any folder or external drive containing photos.
3. Browse photos in the **Photos** tab, browse albums in the **Folders** tab, or explore recognized people in the **People** tab!
