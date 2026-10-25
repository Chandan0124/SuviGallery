package com.suvi.gallery.di

import android.content.Context
import androidx.room.Room
import com.suvi.gallery.data.local.AppDatabase
import com.suvi.gallery.data.local.dao.FaceVaultDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            "suvi_gallery.db"
        ).fallbackToDestructiveMigration().build()
    }

    @Provides
    fun provideFaceVaultDao(db: AppDatabase): FaceVaultDao {
        return db.faceVaultDao()
    }
}
