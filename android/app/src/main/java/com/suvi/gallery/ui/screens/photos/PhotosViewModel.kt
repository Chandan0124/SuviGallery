package com.suvi.gallery.ui.screens.photos

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.suvi.gallery.data.local.dao.FaceVaultDao
import com.suvi.gallery.data.local.entity.PersonEntity
import com.suvi.gallery.data.local.entity.PhotoEntity
import com.suvi.gallery.data.media.AvatarManager
import com.suvi.gallery.data.media.GalleryScanner
import com.suvi.gallery.data.ml.FaceIndexer
import com.suvi.gallery.worker.GalleryIndexingWorker
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

data class GalleryUiState(
    val photos: List<PhotoEntity> = emptyList(),
    val people: List<PersonEntity> = emptyList(),
    val selectedPersonId: Long? = null,
    val totalPhotos: Int = 0,
    val processedPhotos: Int = 0,
    val totalPeople: Int = 0,
    val searchQuery: String = "",
    val isScanning: Boolean = false
)

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class PhotosViewModel @Inject constructor(
    private val dao: FaceVaultDao,
    private val scanner: GalleryScanner,
    private val faceIndexer: FaceIndexer,
    private val avatarManager: AvatarManager
) : ViewModel() {

    private val _searchQuery = MutableStateFlow("")
    private val _isScanning = MutableStateFlow(false)
    private val _selectedPersonId = MutableStateFlow<Long?>(null)

    init {
        // Immediately start indexing any existing unprocessed photos in background coroutine
        viewModelScope.launch(Dispatchers.Default) {
            faceIndexer.indexAll()
        }
    }

    fun getAvatarFile(personId: Long): File = avatarManager.getAvatarFile(personId)

    fun togglePersonFilter(personId: Long) {
        _selectedPersonId.value = if (_selectedPersonId.value == personId) null else personId
    }

    fun clearPersonFilter() {
        _selectedPersonId.value = null
    }

    private val statsFlow = combine(
        dao.getTotalPhotoCount(),
        dao.getProcessedPhotoCount(),
        dao.getTotalPeopleCount()
    ) { total, processed, people ->
        Triple(total, processed, people)
    }

    private val photosFlow = _selectedPersonId.flatMapLatest { personId ->
        if (personId != null) {
            dao.getPhotosForPerson(personId)
        } else {
            dao.getAllPhotos()
        }
    }

    private val filterStateFlow = combine(
        _selectedPersonId,
        _searchQuery,
        _isScanning
    ) { selectedPerson, query, scanning ->
        Triple(selectedPerson, query, scanning)
    }

    val uiState: StateFlow<GalleryUiState> = combine(
        photosFlow,
        dao.getAllPersons(),
        statsFlow,
        filterStateFlow
    ) { photos, people, stats, filter ->
        val selectedPerson = filter.first
        val query = filter.second
        val scanning = filter.third

        val filtered = if (query.isBlank()) {
            photos
        } else {
            photos.filter {
                it.displayName.contains(query, ignoreCase = true) ||
                it.directory.contains(query, ignoreCase = true)
            }
        }
        GalleryUiState(
            photos = filtered,
            people = people,
            selectedPersonId = selectedPerson,
            totalPhotos = stats.first,
            processedPhotos = stats.second,
            totalPeople = stats.third,
            searchQuery = query,
            isScanning = scanning
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), GalleryUiState())

    fun onSearchQueryChanged(query: String) {
        _searchQuery.value = query
    }

    fun syncGallery(context: Context) {
        viewModelScope.launch {
            _isScanning.value = true
            try {
                scanner.scanDeviceImages(context)
                val request = OneTimeWorkRequestBuilder<GalleryIndexingWorker>()
                    .setConstraints(Constraints.NONE)
                    .build()
                WorkManager.getInstance(context).enqueueUniqueWork(
                    "face_indexing",
                    ExistingWorkPolicy.REPLACE,
                    request
                )
                // Also trigger immediate processing without waiting for WorkManager scheduler
                launch(Dispatchers.Default) {
                    faceIndexer.indexAll()
                }
            } finally {
                _isScanning.value = false
            }
        }
    }
}
