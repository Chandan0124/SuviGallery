package com.suvi.gallery.ui.screens.people

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import coil.request.ImageRequest
import com.suvi.gallery.data.local.entity.PersonEntity
import com.suvi.gallery.ui.theme.AccentGreen
import com.suvi.gallery.ui.theme.PrimaryBlue
import com.suvi.gallery.ui.theme.SurfaceDark
import com.suvi.gallery.ui.theme.SurfaceVariantDark
import com.suvi.gallery.ui.theme.TextSecondary
import java.io.File

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun PeopleScreen(
    viewModel: PeopleViewModel,
    onPersonClick: (Long) -> Unit,
    onViewCombinedPhotos: (List<Long>) -> Unit = {}
) {
    val people by viewModel.people.collectAsState()
    val selectedIds by viewModel.selectedIds.collectAsState()
    val isSelectionMode by viewModel.isSelectionMode.collectAsState()

    var renamingPerson by remember { mutableStateOf<PersonEntity?>(null) }
    var renameText by remember { mutableStateOf("") }
    var showMergeDialog by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            if (isSelectionMode) {
                TopAppBar(
                    title = {
                        Text(
                            "${selectedIds.size} selected",
                            fontWeight = FontWeight.Bold,
                            fontSize = 18.sp
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = { viewModel.clearSelection() }) {
                            Icon(Icons.Default.Close, contentDescription = "Cancel Selection")
                        }
                    },
                    actions = {
                        if (selectedIds.size >= 2) {
                            TextButton(onClick = { showMergeDialog = true }) {
                                Icon(
                                    Icons.Default.MergeType,
                                    contentDescription = null,
                                    tint = PrimaryBlue,
                                    modifier = Modifier.size(18.dp)
                                )
                                Spacer(modifier = Modifier.width(4.dp))
                                Text("Merge", color = PrimaryBlue, fontWeight = FontWeight.Bold)
                            }
                        }
                        if (selectedIds.isNotEmpty()) {
                            IconButton(onClick = {
                                onViewCombinedPhotos(selectedIds.toList())
                            }) {
                                Icon(
                                    Icons.Default.PhotoLibrary,
                                    contentDescription = "View Photos",
                                    tint = PrimaryBlue
                                )
                            }
                        }
                        IconButton(onClick = { viewModel.selectAll() }) {
                            Icon(Icons.Default.SelectAll, contentDescription = "Select All")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = SurfaceDark)
                )
            } else {
                TopAppBar(
                    title = {
                        Column {
                            Text("People", fontWeight = FontWeight.Bold, fontSize = 20.sp)
                            Text(
                                "${people.size} people recognized",
                                fontSize = 12.sp,
                                color = TextSecondary
                            )
                        }
                    },
                    actions = {
                        TextButton(onClick = { viewModel.reclusterNow() }) {
                            Icon(
                                Icons.Default.AutoAwesome,
                                contentDescription = null,
                                tint = PrimaryBlue,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Re-cluster", color = PrimaryBlue, fontSize = 13.sp)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = SurfaceDark)
                )
            }
        }
    ) { paddingValues ->
        if (people.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.Person,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = SurfaceVariantDark
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        "No people discovered yet",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        "Face recognition runs automatically as photos are scanned.",
                        fontSize = 13.sp,
                        color = TextSecondary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 32.dp, vertical = 6.dp)
                    )
                }
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(110.dp),
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues),
                contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(people, key = { it.personId }) { person ->
                    val isSelected = selectedIds.contains(person.personId)
                    val avatarFile = viewModel.getAvatarFile(person.personId)

                    PersonCard(
                        person = person,
                        avatarFile = avatarFile,
                        isSelected = isSelected,
                        isSelectionMode = isSelectionMode,
                        onClick = {
                            if (isSelectionMode) {
                                viewModel.toggleSelection(person.personId)
                            } else {
                                onPersonClick(person.personId)
                            }
                        },
                        onLongClick = {
                            if (!isSelectionMode) {
                                viewModel.startSelection(person.personId)
                            } else {
                                viewModel.toggleSelection(person.personId)
                            }
                        },
                        onRenameClick = {
                            renamingPerson = person
                            renameText = person.name
                        }
                    )
                }
            }
        }
    }

    // Rename Dialog
    if (renamingPerson != null) {
        AlertDialog(
            onDismissRequest = { renamingPerson = null },
            title = { Text("Name Person", fontSize = 18.sp, fontWeight = FontWeight.Bold) },
            text = {
                OutlinedTextField(
                    value = renameText,
                    onValueChange = { renameText = it },
                    placeholder = { Text("Enter name (e.g. Mom, Alex)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        renamingPerson?.let { viewModel.renamePerson(it.personId, renameText) }
                        renamingPerson = null
                    }
                ) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(onClick = { renamingPerson = null }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Multi-Person Merge Dialog
    if (showMergeDialog && selectedIds.size >= 2) {
        val selectedPeople = people.filter { selectedIds.contains(it.personId) }
        var targetId by remember { mutableStateOf(selectedPeople.first().personId) }
        var mergeName by remember {
            val bestName = selectedPeople.firstOrNull { !it.name.startsWith("Person #") }?.name
                ?: selectedPeople.first().name
            mutableStateOf(bestName)
        }

        AlertDialog(
            onDismissRequest = { showMergeDialog = false },
            title = { Text("Merge ${selectedIds.size} People", fontSize = 18.sp, fontWeight = FontWeight.Bold) },
            text = {
                Column {
                    Text(
                        "Combine photos of these people into a single person:",
                        fontSize = 13.sp,
                        color = TextSecondary
                    )
                    Spacer(modifier = Modifier.height(10.dp))

                    OutlinedTextField(
                        value = mergeName,
                        onValueChange = { mergeName = it },
                        label = { Text("Combined Person Name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )

                    Spacer(modifier = Modifier.height(12.dp))
                    Text("Select primary avatar / person:", fontSize = 12.sp, color = TextSecondary)
                    Spacer(modifier = Modifier.height(6.dp))

                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        selectedPeople.take(4).forEach { p ->
                            val avatarFile = viewModel.getAvatarFile(p.personId)
                            val isTarget = p.personId == targetId

                            Box(
                                modifier = Modifier
                                    .size(54.dp)
                                    .clip(CircleShape)
                                    .border(
                                        width = if (isTarget) 3.dp else 1.dp,
                                        color = if (isTarget) PrimaryBlue else Color.Gray,
                                        shape = CircleShape
                                    )
                                    .clickable {
                                        targetId = p.personId
                                        if (mergeName.isBlank() || mergeName.startsWith("Person #")) {
                                            mergeName = p.name
                                        }
                                    },
                                contentAlignment = Alignment.Center
                            ) {
                                SubcomposeAsyncImage(
                                    model = ImageRequest.Builder(LocalContext.current)
                                        .data(avatarFile)
                                        .crossfade(true)
                                        .build(),
                                    contentDescription = p.name,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize(),
                                    error = {
                                        Box(
                                            modifier = Modifier
                                                .fillMaxSize()
                                                .background(PrimaryBlue.copy(alpha = 0.2f)),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Text(
                                                text = p.name.take(1).uppercase(),
                                                fontWeight = FontWeight.Bold,
                                                color = PrimaryBlue
                                            )
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        viewModel.mergeMultiple(targetId, mergeName)
                        showMergeDialog = false
                    }
                ) {
                    Text("Merge All")
                }
            },
            dismissButton = {
                TextButton(onClick = { showMergeDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PersonCard(
    person: PersonEntity,
    avatarFile: File,
    isSelected: Boolean,
    isSelectionMode: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onRenameClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(
                width = if (isSelected) 2.dp else 0.dp,
                color = if (isSelected) PrimaryBlue else Color.Transparent,
                shape = RoundedCornerShape(12.dp)
            )
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick
            ),
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) SurfaceVariantDark.copy(alpha = 0.7f) else SurfaceVariantDark
        ),
        shape = RoundedCornerShape(12.dp)
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Real Face Avatar Image (with SubcomposeAsyncImage fallback)
                Box(
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .background(PrimaryBlue.copy(alpha = 0.2f)),
                    contentAlignment = Alignment.Center
                ) {
                    SubcomposeAsyncImage(
                        model = ImageRequest.Builder(LocalContext.current)
                            .data(avatarFile)
                            .crossfade(true)
                            .build(),
                        contentDescription = person.name,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(CircleShape),
                        error = {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(PrimaryBlue.copy(alpha = 0.2f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = person.name.take(1).uppercase(),
                                    fontSize = 26.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = PrimaryBlue
                                )
                            }
                        }
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = person.name,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    if (!isSelectionMode) {
                        Spacer(modifier = Modifier.width(4.dp))
                        Icon(
                            Icons.Default.Edit,
                            contentDescription = "Rename",
                            modifier = Modifier
                                .size(14.dp)
                                .clickable { onRenameClick() },
                            tint = TextSecondary
                        )
                    }
                }

                Text(
                    text = "${person.photoCount} photos",
                    fontSize = 11.sp,
                    color = TextSecondary
                )
            }

            // Selection Checkbox Badge
            if (isSelectionMode) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                ) {
                    if (isSelected) {
                        Icon(
                            Icons.Default.CheckCircle,
                            contentDescription = "Selected",
                            tint = PrimaryBlue,
                            modifier = Modifier.size(22.dp)
                        )
                    } else {
                        Box(
                            modifier = Modifier
                                .size(20.dp)
                                .clip(CircleShape)
                                .border(1.5.dp, Color.White.copy(alpha = 0.6f), CircleShape)
                        )
                    }
                }
            }
        }
    }
}
