package com.suvi.gallery.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "photos",
    indices = [
        Index("directory"),
        Index("dateTaken"),
        Index("isProcessed")
    ]
)
data class PhotoEntity(
    @PrimaryKey val photoId: Long,
    val uri: String,
    val displayName: String,
    val directory: String,
    val fileSize: Long,
    val width: Int? = null,
    val height: Int? = null,
    val dateTaken: Long? = null,
    val isProcessed: Boolean = false,
    val faceCount: Int = 0,
    @ColumnInfo(typeAffinity = ColumnInfo.BLOB)
    val clipEmbedding: ByteArray? = null,
    val createdAt: Long = System.currentTimeMillis()
)
