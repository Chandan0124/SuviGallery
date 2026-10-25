package com.suvi.gallery.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.suvi.gallery.data.local.converter.Converters
import com.suvi.gallery.data.local.dao.FaceVaultDao
import com.suvi.gallery.data.local.entity.*

@Database(
    entities = [
        PhotoEntity::class,
        PersonEntity::class,
        FaceEntity::class
    ],
    version = 1,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun faceVaultDao(): FaceVaultDao
}
