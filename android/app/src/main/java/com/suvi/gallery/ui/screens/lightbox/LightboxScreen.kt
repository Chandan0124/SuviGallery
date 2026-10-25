package com.suvi.gallery.ui.screens.lightbox

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Face
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import coil.request.ImageRequest
import com.suvi.gallery.data.local.dao.FaceVaultDao
import com.suvi.gallery.data.local.entity.FaceEntity
import com.suvi.gallery.data.local.entity.PersonEntity
import com.suvi.gallery.data.local.entity.PhotoEntity
import com.suvi.gallery.ui.theme.AccentGreen
import com.suvi.gallery.ui.theme.PrimaryBlue
import com.suvi.gallery.ui.theme.SurfaceDark
import com.suvi.gallery.ui.theme.SurfaceVariantDark
import com.suvi.gallery.ui.theme.TextSecondary
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun LightboxScreen(
    initialPhotoId: Long,
    dao: FaceVaultDao,
    onBackClick: () -> Unit
) {
    val allPhotos by dao.getAllPhotos().collectAsState(initial = emptyList())
    val allPersons by dao.getAllPersons().collectAsState(initial = emptyList())
    val personMap = remember(allPersons) { allPersons.associateBy { it.personId } }

    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    // Immersive mode: Controls & labels are hidden by default per user request
    var isControlsVisible by remember { mutableStateOf(false) }
    var showFaceBoxes by remember { mutableStateOf(true) }

    var taggingFace by remember { mutableStateOf<FaceEntity?>(null) }
    var tagNameText by remember { mutableStateOf("") }

    if (allPhotos.isEmpty()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator(color = PrimaryBlue)
        }
        return
    }

    val initialIndex = remember(allPhotos) {
        val found = allPhotos.indexOfFirst { it.photoId == initialPhotoId }
        if (found >= 0) found else 0
    }

    val pagerState = rememberPagerState(
        initialPage = initialIndex,
        pageCount = { allPhotos.size }
    )

    val currentPhoto = allPhotos.getOrNull(pagerState.currentPage)
    val currentFaces by dao.getFacesForPhotoFlow(currentPhoto?.photoId ?: 0L)
        .collectAsState(initial = emptyList())

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) {
                // Tapping on photo toggles controls & face tags on and off
                isControlsVisible = !isControlsVisible
            }
    ) {
        // Swipable photo pager
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize()
        ) { page ->
            val photo = allPhotos.getOrNull(page)
            if (photo != null) {
                val facesForPage by dao.getFacesForPhotoFlow(photo.photoId)
                    .collectAsState(initial = emptyList())

                PhotoPageView(
                    photo = photo,
                    faces = facesForPage,
                    personMap = personMap,
                    showFaceBoxes = isControlsVisible && showFaceBoxes,
                    onFaceClick = { face ->
                        taggingFace = face
                        val existingName = face.personId?.let { personMap[it]?.name } ?: ""
                        tagNameText = if (existingName.startsWith("Person #")) "" else existingName
                    }
                )
            }
        }

        // Top App Bar (Overlaid on top, shown when controls are visible)
        AnimatedVisibility(
            visible = isControlsVisible,
            enter = fadeIn() + slideInVertically { -it },
            exit = fadeOut() + slideOutVertically { -it },
            modifier = Modifier.align(Alignment.TopCenter)
        ) {
            Surface(
                color = SurfaceDark.copy(alpha = 0.9f),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .statusBarsPadding()
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = onBackClick) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "Back",
                                tint = Color.White
                            )
                        }
                        Spacer(modifier = Modifier.width(6.dp))
                        Column {
                            Text(
                                text = currentPhoto?.displayName ?: "Photo",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White,
                                maxLines = 1
                            )
                            Text(
                                text = "${pagerState.currentPage + 1} of ${allPhotos.size}",
                                fontSize = 11.sp,
                                color = TextSecondary
                            )
                        }
                    }

                    Row {
                        IconButton(onClick = { showFaceBoxes = !showFaceBoxes }) {
                            Icon(
                                Icons.Default.Face,
                                contentDescription = "Toggle Face Boxes",
                                tint = if (showFaceBoxes) AccentGreen else TextSecondary
                            )
                        }
                        IconButton(onClick = {
                            currentPhoto?.let { sharePhoto(context, it.uri) }
                        }) {
                            Icon(
                                Icons.Default.Share,
                                contentDescription = "Share",
                                tint = Color.White
                            )
                        }
                    }
                }
            }
        }

        // Bottom Bar (Overlaid on bottom, shown when controls are visible)
        AnimatedVisibility(
            visible = isControlsVisible && currentFaces.isNotEmpty(),
            enter = fadeIn() + slideInVertically { it },
            exit = fadeOut() + slideOutVertically { it },
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            Surface(
                color = SurfaceDark.copy(alpha = 0.9f),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 10.dp)
                ) {
                    Text(
                        text = "${currentFaces.size} face${if (currentFaces.size > 1) "s" else ""} detected — tap to tag:",
                        fontSize = 11.sp,
                        color = TextSecondary,
                        fontWeight = FontWeight.Medium
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        currentFaces.forEach { face ->
                            val pName = face.personId?.let { personMap[it]?.name } ?: "Untagged Face"
                            AssistChip(
                                onClick = {
                                    taggingFace = face
                                    tagNameText = if (pName.startsWith("Person #")) "" else pName
                                },
                                label = { Text(pName, fontSize = 12.sp) },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Face,
                                        contentDescription = null,
                                        tint = if (face.personId != null) AccentGreen else PrimaryBlue,
                                        modifier = Modifier.size(14.dp)
                                    )
                                },
                                colors = AssistChipDefaults.assistChipColors(containerColor = SurfaceVariantDark)
                            )
                        }
                    }
                }
            }
        }
    }

    // Tag Face Dialog
    if (taggingFace != null) {
        val faceToTag = taggingFace!!
        AlertDialog(
            onDismissRequest = { taggingFace = null },
            title = { Text("Name Person", fontSize = 18.sp, fontWeight = FontWeight.Bold) },
            text = {
                Column {
                    Text("Tag this face to recognize them across your gallery:", fontSize = 12.sp, color = TextSecondary)
                    Spacer(modifier = Modifier.height(10.dp))
                    OutlinedTextField(
                        value = tagNameText,
                        onValueChange = { tagNameText = it },
                        placeholder = { Text("Enter name (e.g. Dad, Sarah)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )

                    if (allPersons.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(12.dp))
                        Text("Or choose existing person:", fontSize = 11.sp, color = TextSecondary)
                        Spacer(modifier = Modifier.height(6.dp))
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            allPersons.filter { !it.name.startsWith("Person #") }.take(3).forEach { existing ->
                                AssistChip(
                                    onClick = { tagNameText = existing.name },
                                    label = { Text(existing.name, fontSize = 11.sp) }
                                )
                            }
                        }
                    }
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (tagNameText.isNotBlank()) {
                            coroutineScope.launch {
                                val trimmed = tagNameText.trim()
                                val existing = dao.findPersonByName(trimmed)
                                val personId = existing?.personId ?: dao.insertPerson(
                                    PersonEntity(name = trimmed, avatarFaceId = faceToTag.faceId)
                                )
                                dao.assignFacesToPerson(listOf(faceToTag.faceId), personId)
                                dao.refreshPersonStats()
                                taggingFace = null
                            }
                        }
                    }
                ) {
                    Text("Save Tag")
                }
            },
            dismissButton = {
                TextButton(onClick = { taggingFace = null }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
fun PhotoPageView(
    photo: PhotoEntity,
    faces: List<FaceEntity>,
    personMap: Map<Long, PersonEntity>,
    showFaceBoxes: Boolean,
    onFaceClick: (FaceEntity) -> Unit
) {
    val context = LocalContext.current
    var originalWidth by remember { mutableFloatStateOf(photo.width?.toFloat() ?: 0f) }
    var originalHeight by remember { mutableFloatStateOf(photo.height?.toFloat() ?: 0f) }

    BoxWithConstraints(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        val boxWidth = constraints.maxWidth.toFloat()
        val boxHeight = constraints.maxHeight.toFloat()

        SubcomposeAsyncImage(
            model = ImageRequest.Builder(context)
                .data(photo.uri)
                .crossfade(true)
                .build(),
            contentDescription = photo.displayName,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize(),
            onSuccess = { state ->
                val painter = state.painter
                if (originalWidth <= 0f || originalHeight <= 0f) {
                    originalWidth = painter.intrinsicSize.width
                    originalHeight = painter.intrinsicSize.height
                }
            }
        )

        // Draw interactive face bounding boxes scaled to the image inside ContentScale.Fit
        if (showFaceBoxes && originalWidth > 0f && originalHeight > 0f && faces.isNotEmpty()) {
            val scale = minOf(boxWidth / originalWidth, boxHeight / originalHeight)
            val renderedWidth = originalWidth * scale
            val renderedHeight = originalHeight * scale
            val offsetX = (boxWidth - renderedWidth) / 2f
            val offsetY = (boxHeight - renderedHeight) / 2f

            val density = LocalDensity.current
            faces.forEach { face ->
                val x1 = offsetX + face.bboxX1 * scale
                val y1 = offsetY + face.bboxY1 * scale
                val boxW = ((face.bboxX2 - face.bboxX1) * scale).coerceAtLeast(30f)
                val boxH = ((face.bboxY2 - face.bboxY1) * scale).coerceAtLeast(30f)

                val boxWdp = with(density) { boxW.toDp() }
                val boxHdp = with(density) { boxH.toDp() }

                val person = face.personId?.let { personMap[it] }
                val personName = person?.name ?: "Untagged Face"

                Box(
                    modifier = Modifier
                        .offset { IntOffset(x1.roundToInt(), y1.roundToInt()) }
                        .size(boxWdp, boxHdp)
                        .border(2.dp, AccentGreen, RoundedCornerShape(8.dp))
                        .clickable { onFaceClick(face) }
                ) {
                    // Small label below or above the face
                    Surface(
                        color = Color.Black.copy(alpha = 0.75f),
                        shape = RoundedCornerShape(4.dp),
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .offset(y = 20.dp)
                    ) {
                        Text(
                            text = personName,
                            color = Color.White,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                            maxLines = 1
                        )
                    }
                }
            }
        }
    }
}

fun sharePhoto(context: Context, uriString: String) {
    try {
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "image/*"
            putExtra(Intent.EXTRA_STREAM, Uri.parse(uriString))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(shareIntent, "Share Photo via"))
    } catch (_: Exception) {}
}
