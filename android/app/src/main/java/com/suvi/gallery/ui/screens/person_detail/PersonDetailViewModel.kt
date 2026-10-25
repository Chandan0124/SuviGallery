package com.suvi.gallery.ui.screens.person_detail

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.suvi.gallery.data.local.dao.FaceVaultDao
import com.suvi.gallery.data.local.entity.PersonEntity
import com.suvi.gallery.data.local.entity.PhotoEntity
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.*
import javax.inject.Inject

enum class FilterMatchMode {
    EITHER,   // Photos with ANY of the selected people
    TOGETHER  // Photos with ALL of the selected people together
}

data class PersonDetailUiState(
    val persons: List<PersonEntity> = emptyList(),
    val photos: List<PhotoEntity> = emptyList(),
    val matchMode: FilterMatchMode = FilterMatchMode.EITHER,
    val isMultiPerson: Boolean = false
)

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class PersonDetailViewModel @Inject constructor(
    private val dao: FaceVaultDao,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val personIdsArg: String = checkNotNull(savedStateHandle["personIds"])
    private val personIdList: List<Long> = personIdsArg.split(",")
        .mapNotNull { it.trim().toLongOrNull() }

    private val _matchMode = MutableStateFlow(FilterMatchMode.EITHER)

    val uiState: StateFlow<PersonDetailUiState> = _matchMode.flatMapLatest { mode ->
        val photosFlow = when {
            personIdList.isEmpty() -> flowOf(emptyList())
            personIdList.size == 1 -> dao.getPhotosForPerson(personIdList[0])
            mode == FilterMatchMode.TOGETHER && personIdList.size >= 2 -> {
                dao.getPhotosWithBoth(personIdList[0], personIdList[1])
            }
            else -> dao.getPhotosWithEither(personIdList)
        }

        photosFlow.map { photos ->
            val persons = dao.getPersonsByIds(personIdList)
            PersonDetailUiState(
                persons = persons,
                photos = photos,
                matchMode = mode,
                isMultiPerson = personIdList.size > 1
            )
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), PersonDetailUiState())

    fun setMatchMode(mode: FilterMatchMode) {
        _matchMode.value = mode
    }
}
