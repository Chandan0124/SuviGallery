package com.suvi.gallery.data.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import com.suvi.gallery.data.local.dao.FaceVaultDao
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AvatarManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val dao: FaceVaultDao
) {
    private val avatarDir = File(context.filesDir, "avatars").apply {
        if (!exists()) mkdirs()
    }

    fun getAvatarFile(personId: Long): File {
        return File(avatarDir, "person_${personId}.jpg")
    }

    suspend fun ensureAvatarExists(personId: Long): File? = withContext(Dispatchers.IO) {
        val file = getAvatarFile(personId)
        if (file.exists() && file.length() > 0) {
            return@withContext file
        }

        val avatarInfo = dao.getAvatarFaceForPerson(personId) ?: return@withContext null
        return@withContext try {
            val uri = Uri.parse(avatarInfo.photoUri)

            // Read dimensions
            val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, boundsOptions)
            }

            val origW = boundsOptions.outWidth
            val origH = boundsOptions.outHeight
            if (origW <= 0 || origH <= 0) return@withContext null

            // Downsample if huge
            var sampleSize = 1
            while ((origW / sampleSize) > 2000 || (origH / sampleSize) > 2000) {
                sampleSize *= 2
            }

            val decodeOptions = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }

            val bitmap = context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, decodeOptions)
            } ?: return@withContext null

            // Scale bounding box if subsampled
            val scale = 1.0f / sampleSize
            val x1 = avatarInfo.bboxX1 * scale
            val y1 = avatarInfo.bboxY1 * scale
            val x2 = avatarInfo.bboxX2 * scale
            val y2 = avatarInfo.bboxY2 * scale

            val w = x2 - x1
            val h = y2 - y1
            val marginX = (w * 0.25f).toInt()
            val marginY = (h * 0.25f).toInt()

            val left = (x1 - marginX).toInt().coerceIn(0, bitmap.width - 1)
            val top = (y1 - marginY).toInt().coerceIn(0, bitmap.height - 1)
            val right = (x2 + marginX).toInt().coerceIn(left + 1, bitmap.width)
            val bottom = (y2 + marginY).toInt().coerceIn(top + 1, bitmap.height)

            val cropW = right - left
            val cropH = bottom - top

            if (cropW > 10 && cropH > 10) {
                val cropped = Bitmap.createBitmap(bitmap, left, top, cropW, cropH)
                val avatar = Bitmap.createScaledBitmap(cropped, 180, 180, true)

                FileOutputStream(file).use { out ->
                    avatar.compress(Bitmap.CompressFormat.JPEG, 90, out)
                }

                if (cropped != avatar) cropped.recycle()
                avatar.recycle()
                bitmap.recycle()
                file
            } else {
                bitmap.recycle()
                null
            }
        } catch (e: Throwable) {
            Log.e("AvatarManager", "Error generating avatar for person $personId", e)
            null
        }
    }

    suspend fun generateMissingAvatars() = withContext(Dispatchers.IO) {
        dao.getAllPersons().collect { persons ->
            for (p in persons) {
                ensureAvatarExists(p.personId)
            }
        }
    }

    fun deleteAvatar(personId: Long) {
        val file = getAvatarFile(personId)
        if (file.exists()) file.delete()
    }
}
