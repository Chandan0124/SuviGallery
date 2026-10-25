package com.suvi.gallery.data.ml

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.net.Uri
import android.util.Log
import com.suvi.gallery.data.local.converter.Converters
import com.suvi.gallery.data.local.dao.FaceVaultDao
import com.suvi.gallery.data.local.entity.FaceEntity
import com.suvi.gallery.data.media.AvatarManager
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.max

@Singleton
class FaceIndexer @Inject constructor(
    private val dao: FaceVaultDao,
    private val faceDetector: FaceDetectorEngine,
    private val embeddingEngine: MobileFaceNetEngine,
    private val avatarManager: AvatarManager,
    @ApplicationContext private val context: Context
) {
    private val isIndexing = AtomicBoolean(false)
    private val converters = Converters()
    private val dbscan = KotlinDBSCAN()

    suspend fun indexAll(isCancelled: () -> Boolean = { false }) = withContext(Dispatchers.Default) {
        if (!isIndexing.compareAndSet(false, true)) {
            Log.d("FaceIndexer", "Indexing is already running, skipping duplicate trigger.")
            return@withContext
        }

        try {
            Log.i("FaceIndexer", "Starting AI face indexing loop...")
            var processedSinceLastCluster = 0

            while (true) {
                if (isCancelled()) {
                    Log.i("FaceIndexer", "Indexing cancelled.")
                    break
                }

                val batch = dao.getUnprocessedPhotos(limit = 20)
                if (batch.isEmpty()) {
                    Log.i("FaceIndexer", "All photos have been processed!")
                    break
                }

                for (photo in batch) {
                    if (isCancelled()) break

                    try {
                        val bitmap = loadOptimizedBitmap(photo.uri, maxDim = 1280)
                        if (bitmap == null) {
                            dao.markPhotoProcessed(photo.photoId, 0, null)
                            continue
                        }

                        val detectedRects = faceDetector.detectFaces(bitmap)
                        val faces = mutableListOf<FaceEntity>()

                        for (rect in detectedRects) {
                            val cropped = cropFace(bitmap, rect) ?: continue
                            val embedding = embeddingEngine.getEmbedding(cropped)
                            cropped.recycle()

                            val embBytes = converters.fromFloatArray(embedding) ?: continue
                            faces.add(
                                FaceEntity(
                                    photoId = photo.photoId,
                                    bboxX1 = rect.left.toFloat(),
                                    bboxY1 = rect.top.toFloat(),
                                    bboxX2 = rect.right.toFloat(),
                                    bboxY2 = rect.bottom.toFloat(),
                                    embedding = embBytes
                                )
                            )
                        }

                        if (faces.isNotEmpty()) {
                            dao.insertFaces(faces)
                        }

                        dao.markPhotoProcessed(photo.photoId, faces.size, null)
                        bitmap.recycle()

                        processedSinceLastCluster += 1
                        if (processedSinceLastCluster >= 25) {
                            processedSinceLastCluster = 0
                            try {
                                val unassigned = dao.getUnassignedFaces()
                                dbscan.clusterAndAssign(unassigned, dao)
                                generateAvatarsForPersons()
                            } catch (e: Throwable) {
                                Log.e("FaceIndexer", "Error in incremental clustering", e)
                            }
                        }
                    } catch (e: Throwable) {
                        Log.e("FaceIndexer", "Failed to process photo ${photo.photoId}", e)
                        dao.markPhotoProcessed(photo.photoId, 0, null)
                    }
                }
            }

            // Final clustering pass
            try {
                val finalUnassigned = dao.getUnassignedFaces()
                dbscan.clusterAndAssign(finalUnassigned, dao)
                dao.refreshPersonStats()
                generateAvatarsForPersons()
                Log.i("FaceIndexer", "Final face clustering pass completed.")
            } catch (e: Throwable) {
                Log.e("FaceIndexer", "Error in final clustering pass", e)
            }
        } finally {
            isIndexing.set(false)
        }
    }

    private suspend fun generateAvatarsForPersons() {
        try {
            val persons = dao.getAllPersons().first()
            for (p in persons) {
                avatarManager.ensureAvatarExists(p.personId)
            }
        } catch (e: Throwable) {
            Log.e("FaceIndexer", "Failed to generate avatars", e)
        }
    }

    private fun loadOptimizedBitmap(uriString: String, maxDim: Int): Bitmap? {
        return try {
            val uri = Uri.parse(uriString)
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, options)
            }

            val origWidth = options.outWidth
            val origHeight = options.outHeight
            if (origWidth <= 0 || origHeight <= 0) return null

            var inSampleSize = 1
            val maxOriginal = max(origWidth, origHeight)
            while ((maxOriginal / (inSampleSize * 2)) >= maxDim) {
                inSampleSize *= 2
            }

            val decodeOptions = BitmapFactory.Options().apply {
                this.inSampleSize = inSampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }

            context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, decodeOptions)
            }
        } catch (e: Exception) {
            Log.w("FaceIndexer", "Error loading bitmap $uriString: ${e.message}")
            null
        }
    }

    private fun cropFace(bitmap: Bitmap, rect: Rect): Bitmap? {
        return try {
            val left = rect.left.coerceAtLeast(0)
            val top = rect.top.coerceAtLeast(0)
            val width = rect.width().coerceAtMost(bitmap.width - left)
            val height = rect.height().coerceAtMost(bitmap.height - top)
            if (width > 10 && height > 10 && !bitmap.isRecycled) {
                Bitmap.createBitmap(bitmap, left, top, width, height)
            } else null
        } catch (e: Exception) {
            null
        }
    }
}
