package com.suvi.gallery.ui.screens.person_detail

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Group
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.suvi.gallery.ui.theme.PrimaryBlue
import com.suvi.gallery.ui.theme.SurfaceDark
import com.suvi.gallery.ui.theme.SurfaceVariantDark
import com.suvi.gallery.ui.theme.TextSecondary

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonDetailScreen(
    viewModel: PersonDetailViewModel,
    onBackClick: () -> Unit,
    onPhotoClick: (Long) -> Unit
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    val titleText = when {
        state.persons.isEmpty() -> "Person"
        state.persons.size == 1 -> state.persons[0].name
        state.persons.size == 2 -> "${state.persons[0].name} & ${state.persons[1].name}"
        else -> "${state.persons[0].name} + ${state.persons.size - 1} more"
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            titleText,
                            fontWeight = FontWeight.Bold,
                            fontSize = 18.sp,
                            maxLines = 1
                        )
                        Text(
                            "${state.photos.size} photos found",
                            fontSize = 12.sp,
                            color = TextSecondary
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = SurfaceDark)
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // If multiple people selected, show Together vs Either toggle
            if (state.isMultiPerson) {
                Surface(
                    color = SurfaceDark,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        FilterChip(
                            selected = state.matchMode == FilterMatchMode.TOGETHER,
                            onClick = { viewModel.setMatchMode(FilterMatchMode.TOGETHER) },
                            label = { Text("Together in Photo", fontSize = 12.sp) },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Group,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                    tint = if (state.matchMode == FilterMatchMode.TOGETHER) PrimaryBlue else TextSecondary
                                )
                            }
                        )

                        FilterChip(
                            selected = state.matchMode == FilterMatchMode.EITHER,
                            onClick = { viewModel.setMatchMode(FilterMatchMode.EITHER) },
                            label = { Text("Any of Them", fontSize = 12.sp) }
                        )
                    }
                }
            }

            if (state.photos.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        if (state.matchMode == FilterMatchMode.TOGETHER)
                            "No photos found where these people appear together in the same picture."
                        else "No photos found for the selected people.",
                        color = TextSecondary,
                        fontSize = 14.sp
                    )
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(110.dp),
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(2.dp)
                ) {
                    items(state.photos, key = { it.photoId }) { photo ->
                        Box(
                            modifier = Modifier
                                .aspectRatio(1f)
                                .padding(2.dp)
                                .clip(RoundedCornerShape(4.dp))
                                .clickable { onPhotoClick(photo.photoId) }
                        ) {
                            AsyncImage(
                                model = ImageRequest.Builder(context)
                                .data(photo.uri)
                                .crossfade(true)
                                .size(320)
                                .build(),
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                    }
                }
            }
        }
    }
}
