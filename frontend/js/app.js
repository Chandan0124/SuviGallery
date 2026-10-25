// Suvi Gallery Frontend Controller
const API_BASE = window.location.origin;

let state = {
  currentTab: 'photos',
  photos: [],
  page: 1,
  limit: 60,
  hasMore: true,
  isLoading: false,
  folders: [],
  activeFolder: null,
  selectedPeopleFilters: [], // array of { id, name }
  personFilterMode: 'together', // 'together', 'only', 'either'
  searchQuery: '',
  people: [],
  currentLightboxIndex: -1,
  currentPhotoFaces: [],
  showAllFaceBoxes: false,
  highlightedFaceId: null,
  selectMode: false,
  selectedPeopleIds: new Set(),
  photoSelectMode: false,
  selectedPhotoIds: new Set(),
  lastSelectedPhotoIndex: -1,
  whatsappDefaultTarget: localStorage.getItem('facevault_wa_target') || 'desktop'
};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  initStatusPolling();
  loadPhotos(true);
  loadFolders();
  loadPeople();
  setupInfiniteScroll();
  setupKeyboardShortcuts();
  updateWhatsAppBadges();
});

// Tab Switching
function switchTab(tab) {
  state.currentTab = tab;
  document.getElementById('tabPhotos').classList.toggle('active', tab === 'photos');
  document.getElementById('tabFolders').classList.toggle('active', tab === 'folders');
  document.getElementById('tabPeople').classList.toggle('active', tab === 'people');

  document.getElementById('photosView').style.display = tab === 'photos' ? 'block' : 'none';
  document.getElementById('foldersView').style.display = tab === 'folders' ? 'block' : 'none';
  document.getElementById('peopleView').style.display = tab === 'people' ? 'block' : 'none';

  if (tab === 'people') {
    loadPeople();
  } else if (tab === 'folders') {
    loadFolders();
  } else {
    cancelSelection();
  }

  if (tab !== 'photos') {
    closeShareDropdown();
    const dock = document.getElementById('floatingPhotosBar');
    if (dock) dock.style.display = 'none';
  } else if (state.selectedPhotoIds.size > 0) {
    const dock = document.getElementById('floatingPhotosBar');
    if (dock) dock.style.display = 'flex';
  }
}

// Polling AI Status & Live HUD
let pollingInterval = null;
function initStatusPolling() {
  fetchStatus();
  pollingInterval = setInterval(fetchStatus, 1500);
}

async function fetchStatus() {
  try {
    const res = await fetch(`${API_BASE}/api/status`);
    if (!res.ok) return;
    const data = await res.json();

    // HUD Text & Badges
    document.getElementById('photoCountBadge').textContent = data.total_images || 0;
    document.getElementById('peopleCountBadge').textContent = data.total_people || 0;

    const hudProcessed = document.getElementById('hudProcessedCount');
    hudProcessed.textContent = `${data.processed_images || 0} / ${data.total_images || 0}`;

    const hudSpeed = document.getElementById('hudSpeedText');
    const hudState = document.getElementById('hudStateText');
    const hudProgressWrap = document.getElementById('hudProgressContainer');
    const hudBar = document.getElementById('hudProgressBar');

    if (data.is_running && data.total_images > 0) {
      hudState.textContent = 'AI Indexing...';
      hudSpeed.textContent = `${data.speed_fps} fps`;
      hudProgressWrap.style.display = 'block';
      const pct = Math.round((data.processed_images / data.total_images) * 100);
      hudBar.style.width = `${pct}%`;
    } else if (data.is_scanning) {
      hudState.textContent = 'Scanning files...';
      hudSpeed.textContent = '';
      hudProgressWrap.style.display = 'none';
    } else {
      hudState.textContent = 'AI Ready';
      hudSpeed.textContent = '';
      hudProgressWrap.style.display = 'none';
    }
  } catch (err) {
    // Server background polling
  }
}

// Native Folder Picker
async function openFolderPicker() {
  try {
    const res = await fetch(`${API_BASE}/api/pick_folder`, { method: 'POST' });
    const data = await res.json();
    if (data.folder_path) {
      await fetch(`${API_BASE}/api/scan`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder_path: data.folder_path })
      });
      loadFolders();
      loadPhotos(true);
      loadPeople();
    }
  } catch (err) {
    alert('Folder picker failed: ' + err.message);
  }
}

// Folder Management & Album View
async function loadFolders() {
  try {
    const res = await fetch(`${API_BASE}/api/folders`);
    const data = await res.json();
    state.folders = data.folders || [];

    document.getElementById('folderCountBadge').textContent = state.folders.length;

    // Update Dropdown in Sub-bar
    const dropdown = document.getElementById('folderDropdown');
    const currentVal = state.activeFolder || '';
    dropdown.innerHTML = '<option value="">All Folders (All Photos)</option>';
    state.folders.forEach(f => {
      const opt = document.createElement('option');
      opt.value = f.directory;
      opt.textContent = `${f.name} (${f.photo_count} photos)`;
      if (f.directory === currentVal) opt.selected = true;
      dropdown.appendChild(opt);
    });

    // Render Folders Grid View
    renderFolderCards();
  } catch (err) {
    console.error('Failed to load folders:', err);
  }
}

function renderFolderCards() {
  const grid = document.getElementById('foldersGrid');
  const empty = document.getElementById('emptyFoldersState');
  grid.innerHTML = '';

  if (state.folders.length === 0) {
    empty.style.display = 'flex';
    return;
  }
  empty.style.display = 'none';

  const fragment = document.createDocumentFragment();
  state.folders.forEach(f => {
    const card = document.createElement('div');
    card.className = 'folder-card';
    card.onclick = () => filterByFolder(f.directory);

    const coverHtml = f.cover_image_id
      ? `<img src="${API_BASE}/api/thumbnail/photo/${f.cover_image_id}?v=${encodeURIComponent(f.directory)}" loading="lazy" alt="${escapeHtml(f.name)}" />`
      : `<div class="folder-card-cover-empty">📁</div>`;

    card.innerHTML = `
      <div class="folder-card-cover">
        ${coverHtml}
      </div>
      <div class="folder-card-meta">
        <div class="folder-card-title" title="${escapeHtml(f.name)}">📁 ${escapeHtml(f.name)}</div>
        <div class="folder-card-path" title="${escapeHtml(f.directory)}">${escapeHtml(f.directory)}</div>
        <div class="folder-card-stats">
          <span>🖼️ ${f.photo_count} photos</span>
          <span>👤 ${f.face_count} faces</span>
        </div>
      </div>
    `;
    fragment.appendChild(card);
  });
  grid.appendChild(fragment);
}

function handleFolderDropdownChange(folderPath) {
  filterByFolder(folderPath || null);
}

function filterByFolder(folderPath) {
  state.activeFolder = folderPath;
  const dropdown = document.getElementById('folderDropdown');
  if (dropdown) dropdown.value = folderPath || '';

  updateFilterBanner();
  switchTab('photos');
  loadPhotos(true);
}

function clearFolderFilter() {
  state.activeFolder = null;
  const dropdown = document.getElementById('folderDropdown');
  if (dropdown) dropdown.value = '';
  updateFilterBanner();
  loadPhotos(true);
}

// Search
let searchDebounceTimer = null;
function handleSearch(val) {
  clearTimeout(searchDebounceTimer);
  document.getElementById('clearSearchBtn').style.display = val ? 'block' : 'none';
  searchDebounceTimer = setTimeout(() => {
    state.searchQuery = val.trim();
    loadPhotos(true);
  }, 300);
}

function clearSearch() {
  const input = document.getElementById('searchInput');
  input.value = '';
  document.getElementById('clearSearchBtn').style.display = 'none';
  state.searchQuery = '';
  loadPhotos(true);
}

// Photos Ingestion & Rendering
async function loadPhotos(reset = false) {
  if (state.isLoading) return;
  if (reset) {
    state.page = 1;
    state.photos = [];
    state.hasMore = true;
    document.getElementById('photoGrid').innerHTML = '';
    clearPhotoSelection();
  }
  if (!state.hasMore) return;

  state.isLoading = true;
  try {
    let url = `${API_BASE}/api/photos?page=${state.page}&limit=${state.limit}`;
    
    // Multi-person filter & mode
    if (state.selectedPeopleFilters.length > 0) {
      const ids = state.selectedPeopleFilters.map(p => p.id).join(',');
      url += `&person_ids=${ids}&person_mode=${encodeURIComponent(state.personFilterMode)}`;
    }

    // Folder filter
    if (state.activeFolder) {
      url += `&folder=${encodeURIComponent(state.activeFolder)}`;
    }

    // Search query
    if (state.searchQuery) {
      url += `&search=${encodeURIComponent(state.searchQuery)}`;
    }

    const res = await fetch(url);
    const data = await res.json();

    const grid = document.getElementById('photoGrid');
    const emptyState = document.getElementById('emptyPhotosState');

    if (reset && data.items.length === 0) {
      emptyState.style.display = 'flex';
    } else {
      emptyState.style.display = 'none';
    }

    const startIndex = state.photos.length;
    state.photos.push(...data.items);
    renderPhotoCards(data.items, startIndex);

    if (state.photos.length >= data.total || data.items.length < state.limit) {
      state.hasMore = false;
    } else {
      state.page += 1;
    }
  } catch (err) {
    console.error('Failed to load photos:', err);
  } finally {
    state.isLoading = false;
  }
}

function renderPhotoCards(items, startIndex) {
  const grid = document.getElementById('photoGrid');
  const fragment = document.createDocumentFragment();

  items.forEach((item, idx) => {
    const photoIndex = startIndex + idx;
    const isSelected = state.selectedPhotoIds.has(item.id);
    const card = document.createElement('div');
    card.className = `photo-card ${isSelected ? 'selected' : ''}`;
    card.id = `photoCard_${item.id}`;
    card.onclick = (e) => handlePhotoCardClick(photoIndex, item.id, e);
    card.ondragstart = (e) => handlePhotoDragStart(item.id, e);

    const faceBadge = item.face_count > 0 ? `<div class="face-badge">👤 ${item.face_count}</div>` : '';
    const locPill = item.location_name ? `<div class="location-pill" title="${escapeHtml(item.location_name)}">📍 ${escapeHtml(item.location_name.split(',')[0])}</div>` : '';
    const thumbVersion = item.modified_time || item.id;

    card.innerHTML = `
      <div class="photo-select-check" title="Select photo" onclick="handlePhotoCheckboxClick(${photoIndex}, ${item.id}, event)">
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3">
          <polyline points="20 6 9 17 4 12"/>
        </svg>
      </div>
      <img src="${API_BASE}/api/thumbnail/photo/${item.id}?v=${thumbVersion}" loading="lazy" alt="${escapeHtml(item.filename)}" />
      ${faceBadge}
      ${locPill}
      <div class="photo-card-info">${escapeHtml(item.filename)}</div>
    `;
    fragment.appendChild(card);
  });

  grid.appendChild(fragment);
}

function setupInfiniteScroll() {
  const sentinel = document.getElementById('loadMoreTrigger');
  const observer = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting && state.hasMore && !state.isLoading && state.currentTab === 'photos') {
      loadPhotos(false);
    }
  }, { rootMargin: '300px' });

  observer.observe(sentinel);
}

// Multi-person Relational Filtering
function filterByPerson(personId, personName) {
  // If not already in active person filters, add
  const exists = state.selectedPeopleFilters.some(p => p.id === personId);
  if (!exists) {
    state.selectedPeopleFilters.push({ id: personId, name: personName });
  }
  updateFilterBanner();
  switchTab('photos');
  loadPhotos(true);
}

function removePersonFilter(personId) {
  state.selectedPeopleFilters = state.selectedPeopleFilters.filter(p => p.id !== personId);
  updateFilterBanner();
  loadPhotos(true);
}

function setPersonMode(mode) {
  state.personFilterMode = mode;
  document.getElementById('modeBtnTogether').classList.toggle('active', mode === 'together');
  document.getElementById('modeBtnOnly').classList.toggle('active', mode === 'only');
  document.getElementById('modeBtnEither').classList.toggle('active', mode === 'either');
  loadPhotos(true);
}

function viewSelectedPeopleTogether() {
  const selectedIds = Array.from(state.selectedPeopleIds);
  if (selectedIds.length === 0) return;

  state.selectedPeopleFilters = state.people
    .filter(p => selectedIds.includes(p.id))
    .map(p => ({ id: p.id, name: p.name }));

  cancelSelection();
  updateFilterBanner();
  switchTab('photos');
  loadPhotos(true);
}

function clearAllFilters() {
  state.activeFolder = null;
  state.selectedPeopleFilters = [];
  state.searchQuery = '';
  document.getElementById('searchInput').value = '';
  document.getElementById('clearSearchBtn').style.display = 'none';
  const dropdown = document.getElementById('folderDropdown');
  if (dropdown) dropdown.value = '';

  updateFilterBanner();
  loadPhotos(true);
}

function updateFilterBanner() {
  const banner = document.getElementById('activeFilterBanner');
  const chipsList = document.getElementById('activeFilterTags');
  const relationalWrap = document.getElementById('relationalModeWrap');

  const hasFolder = !!state.activeFolder;
  const hasPeople = state.selectedPeopleFilters.length > 0;

  if (!hasFolder && !hasPeople) {
    banner.style.display = 'none';
    return;
  }

  banner.style.display = 'flex';
  chipsList.innerHTML = '';

  // Folder Chip
  if (hasFolder) {
    const fName = state.activeFolder.split(/[\\/]/).filter(Boolean).pop() || state.activeFolder;
    const fChip = document.createElement('span');
    fChip.className = 'filter-chip-tag';
    fChip.innerHTML = `📁 ${escapeHtml(fName)} <button onclick="clearFolderFilter()">&times;</button>`;
    chipsList.appendChild(fChip);
  }

  // People Chips
  state.selectedPeopleFilters.forEach(p => {
    const pChip = document.createElement('span');
    pChip.className = 'filter-chip-tag';
    pChip.innerHTML = `👤 ${escapeHtml(p.name)} <button onclick="removePersonFilter(${p.id})">&times;</button>`;
    chipsList.appendChild(pChip);
  });

  // Relational Mode Switcher (Together / Only / Either) shown when 2+ people selected
  if (state.selectedPeopleFilters.length >= 2) {
    relationalWrap.style.display = 'flex';
    document.getElementById('modeBtnTogether').classList.toggle('active', state.personFilterMode === 'together');
    document.getElementById('modeBtnOnly').classList.toggle('active', state.personFilterMode === 'only');
    document.getElementById('modeBtnEither').classList.toggle('active', state.personFilterMode === 'either');
  } else {
    relationalWrap.style.display = 'none';
  }
}

// People Hub Management & Multi-Select
function toggleSelectMode() {
  state.selectMode = !state.selectMode;
  document.getElementById('selectModeBtnText').textContent = state.selectMode ? 'Done Selecting' : 'Select Multiple';
  if (!state.selectMode) {
    cancelSelection();
  }
  loadPeople();
}

function cancelSelection() {
  state.selectedPeopleIds.clear();
  document.getElementById('floatingCombineBar').style.display = 'none';
  document.querySelectorAll('.person-select-checkbox').forEach(cb => cb.checked = false);
  document.querySelectorAll('.person-card').forEach(card => card.classList.remove('selected'));
}

function handlePersonCheck(personId, checked) {
  if (checked) {
    state.selectedPeopleIds.add(personId);
  } else {
    state.selectedPeopleIds.delete(personId);
  }

  const card = document.getElementById(`personCard_${personId}`);
  if (card) {
    card.classList.toggle('selected', checked);
  }

  const bar = document.getElementById('floatingCombineBar');
  const countText = document.getElementById('selectedPeopleCountText');
  const count = state.selectedPeopleIds.size;

  if (count >= 1) {
    countText.textContent = `${count} ${count === 1 ? 'person' : 'people'} selected`;
    bar.style.display = 'flex';
  } else {
    bar.style.display = 'none';
  }
}

async function loadPeople() {
  try {
    const res = await fetch(`${API_BASE}/api/people`);
    const data = await res.json();
    state.people = data.people || [];

    const grid = document.getElementById('peopleGrid');
    const emptyState = document.getElementById('emptyPeopleState');
    grid.innerHTML = '';

    if (state.people.length === 0) {
      emptyState.style.display = 'flex';
      return;
    }
    emptyState.style.display = 'none';

    state.people.forEach((person) => {
      const card = document.createElement('div');
      card.className = `person-card ${state.selectedPeopleIds.has(person.id) ? 'selected' : ''}`;
      card.id = `personCard_${person.id}`;

      const avatarSrc = person.avatar_face_id
        ? `${API_BASE}/api/thumbnail/face/${person.avatar_face_id}?v=${person.avatar_face_id}`
        : 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg"/>';

      const checkbox = state.selectMode ? `
        <input type="checkbox" class="person-select-checkbox" 
               ${state.selectedPeopleIds.has(person.id) ? 'checked' : ''} 
               onclick="event.stopPropagation(); handlePersonCheck(${person.id}, this.checked)" />
      ` : '';

      card.innerHTML = `
        ${checkbox}
        <div class="person-avatar-wrap" title="View all photos of this person" onclick="filterByPerson(${person.id}, '${escapeHtml(person.name)}')">
          <img src="${avatarSrc}" onerror="this.src=''" alt="${escapeHtml(person.name)}" />
        </div>
        <input type="text" class="person-name-input" value="${escapeHtml(person.name)}" onblur="updatePersonName(${person.id}, this.value)" onkeydown="if(event.key==='Enter')this.blur()" />
        <span class="person-meta">${person.photo_count} photos • ${person.face_count} faces</span>
        <div class="person-actions">
          <button class="btn-secondary" style="font-size:0.75rem; padding:4px 8px;" onclick="openMergeModal(${person.id}, '${escapeHtml(person.name)}')">Merge</button>
        </div>
      `;
      grid.appendChild(card);
    });
  } catch (err) {
    console.error('Failed to load people:', err);
  }
}

async function updatePersonName(personId, newName) {
  const trimmed = newName.trim();
  if (!trimmed) return;
  try {
    await fetch(`${API_BASE}/api/people/${personId}/name`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: trimmed })
    });
  } catch (err) {
    console.error('Failed to rename person:', err);
  }
}

async function triggerClusteringNow() {
  try {
    await fetch(`${API_BASE}/api/cluster/run`, { method: 'POST' });
    loadPeople();
  } catch (err) {
    console.error('Failed to run clusterer:', err);
  }
}

// Combine Modal
function openCombineSelectedModal() {
  const selectedIds = Array.from(state.selectedPeopleIds);
  if (!selectedIds.length) return;

  const selectElem = document.getElementById('combineExistingNameSelect');
  selectElem.innerHTML = '';

  const selectedPeople = state.people.filter(p => selectedIds.includes(p.id));
  selectedPeople.forEach((p, idx) => {
    const opt = document.createElement('option');
    opt.value = p.name;
    opt.textContent = `${p.name} (${p.photo_count} photos)`;
    selectElem.appendChild(opt);
    if (idx === 0) {
      document.getElementById('combineTargetNameInput').value = p.name;
    }
  });

  document.getElementById('combineModal').style.display = 'flex';
}

function closeCombineModal() {
  document.getElementById('combineModal').style.display = 'none';
}

async function confirmCombineSelected() {
  const name = document.getElementById('combineTargetNameInput').value.trim();
  const selectedIds = Array.from(state.selectedPeopleIds);
  if (!name || !selectedIds.length) {
    alert('Please provide a name for the combined person.');
    return;
  }

  try {
    await fetch(`${API_BASE}/api/people/combine`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ source_ids: selectedIds, target_name: name })
    });
    closeCombineModal();
    cancelSelection();
    loadPeople();
    loadPhotos(true);
  } catch (err) {
    alert('Failed to combine people: ' + err.message);
  }
}

// Lightbox & Face Overlay
async function openLightbox(index) {
  state.currentLightboxIndex = index;
  const photo = state.photos[index];
  if (!photo) return;

  const modal = document.getElementById('lightboxModal');
  const img = document.getElementById('lightboxImg');
  const title = document.getElementById('lightboxFilename');
  const locBadge = document.getElementById('lightboxLocationBadge');

  title.textContent = photo.filename;
  if (photo.location_name) {
    locBadge.textContent = `📍 ${photo.location_name}`;
    locBadge.style.display = 'inline-block';
  } else {
    locBadge.style.display = 'none';
  }

  img.src = `${API_BASE}/api/raw_image/${photo.id}`;
  modal.style.display = 'flex';

  try {
    const res = await fetch(`${API_BASE}/api/photos/${photo.id}/faces`);
    const data = await res.json();
    state.currentPhotoFaces = data.faces || [];
    renderFaceChips();
  } catch (err) {
    state.currentPhotoFaces = [];
  }
}

function closeLightbox() {
  document.getElementById('lightboxModal').style.display = 'none';
  document.getElementById('faceBoxesContainer').innerHTML = '';
  state.currentPhotoFaces = [];
  state.currentLightboxIndex = -1;
  state.highlightedFaceId = null;
  state.showAllFaceBoxes = false;
  const btn = document.getElementById('toggleFaceBoxesBtn');
  const txt = document.getElementById('toggleFaceBoxesText');
  if (btn) btn.classList.remove('active');
  if (txt) txt.textContent = 'Show Faces';
}

function prevPhoto() {
  if (state.currentLightboxIndex > 0) {
    openLightbox(state.currentLightboxIndex - 1);
  }
}

function nextPhoto() {
  if (state.currentLightboxIndex < state.photos.length - 1) {
    openLightbox(state.currentLightboxIndex + 1);
  }
}

function toggleAllFaceBoxes() {
  state.showAllFaceBoxes = !state.showAllFaceBoxes;
  const btn = document.getElementById('toggleFaceBoxesBtn');
  const txt = document.getElementById('toggleFaceBoxesText');
  if (btn) btn.classList.toggle('active', state.showAllFaceBoxes);
  if (txt) txt.textContent = state.showAllFaceBoxes ? 'Hide Faces' : 'Show Faces';
  applyFaceBoxVisibility();
}

function highlightFace(faceId) {
  state.highlightedFaceId = faceId;
  applyFaceBoxVisibility();
}

function unhighlightFace(faceId) {
  if (state.highlightedFaceId === faceId) {
    state.highlightedFaceId = null;
  }
  applyFaceBoxVisibility();
}

function toggleFacePin(faceId) {
  if (state.highlightedFaceId === faceId) {
    state.highlightedFaceId = null;
  } else {
    state.highlightedFaceId = faceId;
  }
  applyFaceBoxVisibility();
}

function applyFaceBoxVisibility() {
  state.currentPhotoFaces.forEach(face => {
    const box = document.getElementById(`faceBox_${face.id}`);
    const chip = document.getElementById(`faceChip_${face.id}`);
    if (!box) return;

    const isHighlighted = state.highlightedFaceId === face.id;
    const isVisible = state.showAllFaceBoxes || isHighlighted;

    box.classList.toggle('visible', isVisible);
    box.classList.toggle('highlighted', isHighlighted);
    if (chip) chip.classList.toggle('active', isHighlighted);
  });
}

function renderFaceOverlays() {
  const container = document.getElementById('faceBoxesContainer');
  const img = document.getElementById('lightboxImg');
  container.innerHTML = '';

  if (!state.currentPhotoFaces.length || !img.naturalWidth) return;

  const renderedWidth = img.clientWidth;
  const renderedHeight = img.clientHeight;
  const scaleX = renderedWidth / img.naturalWidth;
  const scaleY = renderedHeight / img.naturalHeight;

  container.style.width = `${renderedWidth}px`;
  container.style.height = `${renderedHeight}px`;

  state.currentPhotoFaces.forEach((face) => {
    const box = document.createElement('div');
    box.className = 'face-box-rect';
    box.id = `faceBox_${face.id}`;

    const x = face.bbox_x1 * scaleX;
    const y = face.bbox_y1 * scaleY;
    const w = (face.bbox_x2 - face.bbox_x1) * scaleX;
    const h = (face.bbox_y2 - face.bbox_y1) * scaleY;

    box.style.left = `${x}px`;
    box.style.top = `${y}px`;
    box.style.width = `${w}px`;
    box.style.height = `${h}px`;

    const label = document.createElement('div');
    label.className = 'face-box-label';
    let attrStr = '';
    if (face.gender || face.age) {
      attrStr = ` (${face.gender || ''}${face.gender && face.age ? ', ' : ''}${face.age ? '~' + face.age : ''})`;
    }
    label.textContent = (face.person_name || 'Untagged') + attrStr;
    box.appendChild(label);

    box.onclick = (e) => {
      e.stopPropagation();
      promptTagFace(face.id, face.person_name);
    };

    container.appendChild(box);
  });

  applyFaceBoxVisibility();
}

function renderFaceChips() {
  const container = document.getElementById('lightboxFacesList');
  container.innerHTML = '';

  if (!state.currentPhotoFaces.length) {
    container.innerHTML = '<span style="color:var(--text-dim); font-size:0.8rem;">No faces detected in this photo</span>';
    return;
  }

  state.currentPhotoFaces.forEach((face) => {
    const chip = document.createElement('div');
    chip.className = 'face-chip';
    chip.id = `faceChip_${face.id}`;
    chip.title = 'Hover or click to locate face on photo';

    // Hover or click to highlight face on photo
    chip.onmouseenter = () => highlightFace(face.id);
    chip.onmouseleave = () => unhighlightFace(face.id);
    chip.onclick = () => toggleFacePin(face.id);

    let attrBadge = '';
    if (face.gender || face.age) {
      attrBadge = `<span class="face-attr-tag">${face.gender || ''}${face.gender && face.age ? ' • ' : ''}${face.age ? '~' + face.age : ''}</span>`;
    }

    chip.innerHTML = `
      <img class="face-chip-avatar" src="${API_BASE}/api/thumbnail/face/${face.id}?v=${face.id}" onerror="this.style.display='none'" />
      <span>${escapeHtml(face.person_name || 'Untagged')}</span>
      ${attrBadge}
      <span class="face-chip-edit-icon" title="Rename or tag person" onclick="event.stopPropagation(); promptTagFace(${face.id}, '${escapeHtml(face.person_name || '')}')">✏️</span>
    `;
    container.appendChild(chip);
  });

  applyFaceBoxVisibility();
}

async function promptTagFace(faceId, currentName) {
  const newName = prompt('Who is this person?', currentName || '');
  if (newName && newName.trim()) {
    try {
      await fetch(`${API_BASE}/api/faces/tag`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ face_id: faceId, person_name: newName.trim() })
      });
      if (state.currentLightboxIndex >= 0) {
        const photo = state.photos[state.currentLightboxIndex];
        const res = await fetch(`${API_BASE}/api/photos/${photo.id}/faces`);
        const data = await res.json();
        state.currentPhotoFaces = data.faces || [];
        renderFaceOverlays();
        renderFaceChips();
      }
      loadPeople();
    } catch (err) {
      alert('Failed to tag face: ' + err.message);
    }
  }
}

async function revealCurrentPhoto() {
  if (state.currentLightboxIndex < 0) return;
  const photo = state.photos[state.currentLightboxIndex];
  if (!photo) return;
  try {
    await fetch(`${API_BASE}/api/reveal?image_id=${photo.id}`, { method: 'POST' });
  } catch (err) {
    console.error('Failed to reveal photo:', err);
  }
}

// Merge Dialog
let activeMergeSourceId = null;
function openMergeModal(sourceId, sourceName) {
  activeMergeSourceId = sourceId;
  document.getElementById('mergeSourcePersonName').textContent = sourceName;
  const select = document.getElementById('mergeTargetSelect');
  select.innerHTML = '';

  state.people.forEach((p) => {
    if (p.id !== sourceId) {
      const opt = document.createElement('option');
      opt.value = p.id;
      opt.textContent = `${p.name} (${p.photo_count} photos)`;
      select.appendChild(opt);
    }
  });

  document.getElementById('mergeModal').style.display = 'flex';
}

function closeMergeModal() {
  document.getElementById('mergeModal').style.display = 'none';
  activeMergeSourceId = null;
}

async function confirmMerge() {
  const targetId = parseInt(document.getElementById('mergeTargetSelect').value, 10);
  if (!targetId || !activeMergeSourceId) return;

  try {
    await fetch(`${API_BASE}/api/people/merge`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ source_id: activeMergeSourceId, target_id: targetId })
    });
    closeMergeModal();
    loadPeople();
    loadPhotos(true);
  } catch (err) {
    alert('Merge failed: ' + err.message);
  }
}

// Keyboard navigation
function setupKeyboardShortcuts() {
  window.addEventListener('keydown', (e) => {
    if (document.getElementById('lightboxModal').style.display === 'flex') {
      if (e.key === 'Escape') closeLightbox();
      if (e.key === 'ArrowLeft') prevPhoto();
      if (e.key === 'ArrowRight') nextPhoto();
    }
  });
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/* ========================================================
   Photo Multi-Selection, WhatsApp Share & System Gallery
   ======================================================== */

function handleToolbarShareClick() {
  if (state.photoSelectMode) {
    if (state.selectedPhotoIds.size > 0) {
      toggleShareDropdown();
    } else {
      togglePhotoSelectMode(false);
    }
  } else {
    togglePhotoSelectMode(true);
    showToast('Selection mode active! Click photos to select, then share via WhatsApp or Gallery below.', 'info', 4500);
  }
}

function togglePhotoSelectMode(forceState) {
  state.photoSelectMode = forceState !== undefined ? forceState : !state.photoSelectMode;
  const btn = document.getElementById('togglePhotoSelectBtn');
  const txt = document.getElementById('photoSelectBtnText');
  const grid = document.getElementById('photoGrid');

  if (btn) btn.classList.toggle('active', state.photoSelectMode);
  if (txt) txt.textContent = state.photoSelectMode ? 'Done Selecting' : 'Share Photos';
  if (grid) grid.classList.toggle('select-mode-active', state.photoSelectMode);

  if (!state.photoSelectMode) {
    clearPhotoSelection();
  } else {
    updatePhotoSelectionUI();
  }
}

function handlePhotoCheckboxClick(index, photoId, event) {
  event.stopPropagation();
  if (!state.photoSelectMode) {
    togglePhotoSelectMode(true);
  }
  togglePhotoSelected(index, photoId, event.shiftKey);
}

function handlePhotoCardClick(index, photoId, event) {
  if (state.photoSelectMode) {
    togglePhotoSelected(index, photoId, event.shiftKey);
  } else {
    openLightbox(index);
  }
}

function togglePhotoSelected(index, photoId, isShift) {
  if (isShift && state.lastSelectedPhotoIndex !== -1 && state.lastSelectedPhotoIndex !== index) {
    const start = Math.min(state.lastSelectedPhotoIndex, index);
    const end = Math.max(state.lastSelectedPhotoIndex, index);
    for (let i = start; i <= end; i++) {
      if (state.photos[i]) {
        state.selectedPhotoIds.add(state.photos[i].id);
        const card = document.getElementById(`photoCard_${state.photos[i].id}`);
        if (card) card.classList.add('selected');
      }
    }
  } else {
    if (state.selectedPhotoIds.has(photoId)) {
      state.selectedPhotoIds.delete(photoId);
      const card = document.getElementById(`photoCard_${photoId}`);
      if (card) card.classList.remove('selected');
    } else {
      state.selectedPhotoIds.add(photoId);
      const card = document.getElementById(`photoCard_${photoId}`);
      if (card) card.classList.add('selected');
    }
    state.lastSelectedPhotoIndex = index;
  }
  updatePhotoSelectionUI();
}

function toggleSelectAllVisiblePhotos() {
  const allSelected = state.photos.length > 0 && state.photos.every(p => state.selectedPhotoIds.has(p.id));
  if (allSelected) {
    state.selectedPhotoIds.clear();
    document.querySelectorAll('.photo-card.selected').forEach(card => card.classList.remove('selected'));
  } else {
    if (!state.photoSelectMode) {
      togglePhotoSelectMode(true);
    }
    state.photos.forEach(p => {
      state.selectedPhotoIds.add(p.id);
      const card = document.getElementById(`photoCard_${p.id}`);
      if (card) card.classList.add('selected');
    });
  }
  updatePhotoSelectionUI();
}

function clearPhotoSelection() {
  state.selectedPhotoIds.clear();
  state.lastSelectedPhotoIndex = -1;
  document.querySelectorAll('.photo-card.selected').forEach(card => card.classList.remove('selected'));
  closeShareDropdown();
  if (state.photoSelectMode) {
    state.photoSelectMode = false;
    const btn = document.getElementById('togglePhotoSelectBtn');
    const txt = document.getElementById('photoSelectBtnText');
    const grid = document.getElementById('photoGrid');
    if (btn) btn.classList.remove('active');
    if (txt) txt.textContent = 'Share Photos';
    if (grid) grid.classList.remove('select-mode-active');
  }
  updatePhotoSelectionUI();
}

function updatePhotoSelectionUI() {
  const count = state.selectedPhotoIds.size;
  const dock = document.getElementById('floatingPhotosBar');
  const countText = document.getElementById('selectedPhotosCountText');
  const selectAllBtn = document.getElementById('selectAllPhotosBtn');

  if (state.photoSelectMode || count > 0) {
    if (dock) dock.style.display = 'flex';
    if (countText) {
      countText.textContent = count > 0 
        ? `${count} photo${count === 1 ? '' : 's'} selected` 
        : 'Click photos to select';
    }
    if (selectAllBtn) {
      const allSelected = state.photos.length > 0 && state.photos.every(p => state.selectedPhotoIds.has(p.id));
      selectAllBtn.textContent = allSelected ? 'Deselect All' : 'Select All';
    }
  } else {
    if (dock) dock.style.display = 'none';
    closeShareDropdown();
  }
}

// Share dropdown handling
function toggleShareDropdown(event) {
  if (event) event.stopPropagation();
  const menu = document.getElementById('shareDropdownMenu');
  if (!menu) return;
  const isHidden = menu.style.display === 'none' || !menu.style.display;
  menu.style.display = isHidden ? 'block' : 'none';
}

function closeShareDropdown() {
  const menu = document.getElementById('shareDropdownMenu');
  if (menu) menu.style.display = 'none';
}

// Close dropdown on click outside
document.addEventListener('click', (e) => {
  const wrap = document.getElementById('shareDropdownWrap');
  if (wrap && !wrap.contains(e.target)) {
    closeShareDropdown();
  }
});

function setWhatsAppDefaultTarget(target) {
  state.whatsappDefaultTarget = target;
  localStorage.setItem('facevault_wa_target', target);
  updateWhatsAppBadges();
  showToast(`Default WhatsApp set to ${target === 'desktop' ? 'Desktop App' : 'Web'}.`, 'info');
}

function updateWhatsAppBadges() {
  const isDesktop = state.whatsappDefaultTarget === 'desktop';
  const badgeDesk = document.getElementById('waDesktopBadge');
  const badgeWeb = document.getElementById('waWebBadge');
  const radioDesk = document.getElementById('prefWaDesktop');
  const radioWeb = document.getElementById('prefWaWeb');

  if (badgeDesk) badgeDesk.style.display = isDesktop ? 'inline-block' : 'none';
  if (badgeWeb) badgeWeb.style.display = !isDesktop ? 'inline-block' : 'none';
  if (radioDesk) radioDesk.checked = isDesktop;
  if (radioWeb) radioWeb.checked = !isDesktop;
}

async function shareSelectedPhotosWhatsApp(target) {
  const ids = Array.from(state.selectedPhotoIds);
  if (!ids.length) return;
  const chosenTarget = target || state.whatsappDefaultTarget || 'desktop';
  closeShareDropdown();

  try {
    const res = await fetch(`${API_BASE}/api/photos/share/whatsapp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image_ids: ids, target: chosenTarget })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Failed to share to WhatsApp');

    showToast(data.message, 'success', 5000);
  } catch (err) {
    showToast(`WhatsApp share error: ${err.message}`, 'warning', 4000);
  }
}

async function openSelectedPhotosInGallery() {
  const ids = Array.from(state.selectedPhotoIds);
  if (!ids.length) return;

  try {
    const res = await fetch(`${API_BASE}/api/photos/open_gallery`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image_ids: ids })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Failed to open gallery');

    showToast(data.message, data.action === 'gallery' ? 'success' : 'info', 4000);
  } catch (err) {
    showToast(`Gallery open error: ${err.message}`, 'warning', 4000);
  }
}

function handlePhotoDragStart(photoId, event) {
  if (state.selectedPhotoIds.size > 1 && state.selectedPhotoIds.has(photoId)) {
    // Windows webview limitation: dragging out of browser to external apps only grabs 1 item.
    // So we automatically copy all selected photos to the clipboard for instant Ctrl+V!
    copySelectedPhotosClipboard(true);
    showToast(
      `Windows limits dragging to 1 photo at a time, but all ${state.selectedPhotoIds.size} selected photos are copied to your clipboard! Press Ctrl+V in WhatsApp to paste all of them.`,
      'info',
      6000
    );
  }
}

async function copySelectedPhotosClipboard(silent = false) {
  const ids = Array.from(state.selectedPhotoIds);
  if (!ids.length) return;
  closeShareDropdown();

  try {
    const res = await fetch(`${API_BASE}/api/photos/clipboard`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image_ids: ids })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Failed to copy to clipboard');

    if (!silent) {
      showToast(data.message, 'success', 4000);
    }
  } catch (err) {
    if (!silent) {
      showToast(`Clipboard error: ${err.message}`, 'warning', 4000);
    }
  }
}

// Single Photo Lightbox Handlers
async function shareCurrentPhotoWhatsApp() {
  if (state.currentLightboxIndex < 0) return;
  const photo = state.photos[state.currentLightboxIndex];
  if (!photo) return;
  const target = state.whatsappDefaultTarget || 'desktop';

  try {
    const res = await fetch(`${API_BASE}/api/photos/share/whatsapp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image_ids: [photo.id], target: target })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Failed to share to WhatsApp');

    showToast(data.message, 'success', 5000);
  } catch (err) {
    showToast(`WhatsApp share error: ${err.message}`, 'warning', 4000);
  }
}

async function openCurrentPhotoInGallery() {
  if (state.currentLightboxIndex < 0) return;
  const photo = state.photos[state.currentLightboxIndex];
  if (!photo) return;

  try {
    const res = await fetch(`${API_BASE}/api/photos/open_gallery`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image_ids: [photo.id] })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Failed to open in gallery');

    showToast(data.message, 'success', 3500);
  } catch (err) {
    showToast(`Gallery open error: ${err.message}`, 'warning', 4000);
  }
}

// Toast notification helper
function showToast(message, type = 'info', duration = 4000) {
  const container = document.getElementById('toastContainer');
  if (!container) return;

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;

  let icon = 'ℹ️';
  if (type === 'success') icon = '✅';
  if (type === 'warning') icon = '⚠️';

  toast.innerHTML = `
    <span class="toast-icon">${icon}</span>
    <div class="toast-msg">${escapeHtml(message)}</div>
  `;

  container.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(10px)';
    setTimeout(() => {
      if (toast.parentNode) toast.parentNode.removeChild(toast);
    }, 200);
  }, duration);
}
