package com.suvi.gallery.data.media

import android.content.ContentUris
import android.content.Context
import android.os.Build
import android.provider.MediaStore
import com.suvi.gallery.data.local.dao.FaceVaultDao
import com.suvi.gallery.data.local.entity.PhotoEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GalleryScanner @Inject constructor(
    private val dao: FaceVaultDao
) {
    suspend fun scanDeviceImages(context: Context): Int = withContext(Dispatchers.IO) {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT
        )

        val newPhotos = mutableListOf<PhotoEntity>()
        val contentResolver = context.contentResolver

        contentResolver.query(
            collection,
            projection,
            null,
            null,
            "${MediaStore.Images.Media.DATE_TAKEN} DESC"
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val bucketCol = cursor.getColumnIndex(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
            val widthCol = cursor.getColumnIndex(MediaStore.Images.Media.WIDTH)
            val heightCol = cursor.getColumnIndex(MediaStore.Images.Media.HEIGHT)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val uri = ContentUris.withAppendedId(collection, id).toString()
                val name = cursor.getString(nameCol) ?: "IMG_$id"
                val bucket = if (bucketCol >= 0) cursor.getString(bucketCol) ?: "Default" else "Default"
                val size = cursor.getLong(sizeCol)
                val dateTaken = cursor.getLong(dateCol)
                val width = if (widthCol >= 0) cursor.getInt(widthCol) else null
                val height = if (heightCol >= 0) cursor.getInt(heightCol) else null

                newPhotos.add(
                    PhotoEntity(
                        photoId = id,
                        uri = uri,
                        displayName = name,
                        directory = bucket,
                        fileSize = size,
                        width = width,
                        height = height,
                        dateTaken = if (dateTaken > 0) dateTaken else System.currentTimeMillis()
                    )
                )

                if (newPhotos.size >= 100) {
                    dao.insertPhotos(newPhotos)
                    newPhotos.clear()
                }
            }
        }

        if (newPhotos.isNotEmpty()) {
            dao.insertPhotos(newPhotos)
        }

        return@withContext newPhotos.size
    }
}
