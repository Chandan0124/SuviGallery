package com.suvi.gallery.ui.screens.people

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.suvi.gallery.data.local.dao.FaceVaultDao
import com.suvi.gallery.data.local.entity.PersonEntity
import com.suvi.gallery.data.media.AvatarManager
import com.suvi.gallery.data.ml.KotlinDBSCAN
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

@HiltViewModel
class PeopleViewModel @Inject constructor(
    private val dao: FaceVaultDao,
    private val avatarManager: AvatarManager
) : ViewModel() {

    val people: StateFlow<List<PersonEntity>> = dao.getAllPersons()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val _selectedIds = MutableStateFlow<Set<Long>>(emptySet())
    val selectedIds: StateFlow<Set<Long>> = _selectedIds.asStateFlow()

    private val _isSelectionMode = MutableStateFlow(false)
    val isSelectionMode: StateFlow<Boolean> = _isSelectionMode.asStateFlow()

    init {
        viewModelScope.launch(Dispatchers.IO) {
            people.collect { list ->
                for (person in list) {
                    avatarManager.ensureAvatarExists(person.personId)
                }
            }
        }
    }

    fun getAvatarFile(personId: Long): File {
        return avatarManager.getAvatarFile(personId)
    }

    fun toggleSelection(personId: Long) {
        val current = _selectedIds.value.toMutableSet()
        if (current.contains(personId)) {
            current.remove(personId)
        } else {
            current.add(personId)
        }
        _selectedIds.value = current
        if (current.isEmpty()) {
            _isSelectionMode.value = false
        } else {
            _isSelectionMode.value = true
        }
    }

    fun startSelection(personId: Long) {
        _isSelectionMode.value = true
        _selectedIds.value = setOf(personId)
    }

    fun selectAll() {
        _selectedIds.value = people.value.map { it.personId }.toSet()
        _isSelectionMode.value = true
    }

    fun clearSelection() {
        _selectedIds.value = emptySet()
        _isSelectionMode.value = false
    }

    fun renamePerson(personId: Long, newName: String) {
        viewModelScope.launch {
            if (newName.isNotBlank()) {
                dao.renamePerson(personId, newName.trim())
            }
        }
    }

    fun mergeMultiple(targetPersonId: Long, finalName: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val sources = _selectedIds.value.filter { it != targetPersonId }
            for (sourceId in sources) {
                dao.mergePersons(sourceId, targetPersonId)
                dao.deletePerson(sourceId)
                avatarManager.deleteAvatar(sourceId)
            }
            if (finalName.isNotBlank()) {
                dao.renamePerson(targetPersonId, finalName.trim())
            }
            dao.refreshPersonStats()
            avatarManager.ensureAvatarExists(targetPersonId)
            clearSelection()
        }
    }

    fun reclusterNow() {
        viewModelScope.launch(Dispatchers.Default) {
            val unassigned = dao.getUnassignedFaces()
            KotlinDBSCAN().clusterAndAssign(unassigned, dao)
            dao.refreshPersonStats()
            for (p in people.value) {
                avatarManager.ensureAvatarExists(p.personId)
            }
        }
    }
}
