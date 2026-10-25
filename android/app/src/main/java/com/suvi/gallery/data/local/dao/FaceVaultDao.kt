package com.suvi.gallery.data.local.dao

import androidx.room.*
import com.suvi.gallery.data.local.entity.*
import kotlinx.coroutines.flow.Flow

@Dao
interface FaceVaultDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertPhotos(photos: List<PhotoEntity>)

    @Query("SELECT * FROM photos WHERE isProcessed = 0 ORDER BY photoId ASC LIMIT :limit")
    suspend fun getUnprocessedPhotos(limit: Int = 50): List<PhotoEntity>

    @Query("UPDATE photos SET isProcessed = 1, faceCount = :faceCount, clipEmbedding = :clipEmb WHERE photoId = :photoId")
    suspend fun markPhotoProcessed(photoId: Long, faceCount: Int, clipEmb: ByteArray?)

    @Query("SELECT * FROM photos ORDER BY dateTaken DESC")
    fun getAllPhotos(): Flow<List<PhotoEntity>>

    @Query("SELECT * FROM photos WHERE photoId = :photoId LIMIT 1")
    suspend fun getPhotoById(photoId: Long): PhotoEntity?

    @Query("SELECT * FROM photos WHERE directory = :directory ORDER BY dateTaken DESC")
    fun getPhotosByFolder(directory: String): Flow<List<PhotoEntity>>

    @Query("SELECT DISTINCT directory FROM photos ORDER BY directory ASC")
    fun getFolders(): Flow<List<String>>

    @Insert
    suspend fun insertFaces(faces: List<FaceEntity>): List<Long>

    @Query("SELECT * FROM faces WHERE photoId = :photoId")
    fun getFacesForPhotoFlow(photoId: Long): Flow<List<FaceEntity>>

    @Query("SELECT * FROM faces WHERE photoId = :photoId")
    suspend fun getFacesForPhoto(photoId: Long): List<FaceEntity>

    @Query("SELECT * FROM faces")
    suspend fun getAllFaces(): List<FaceEntity>

    @Query("SELECT * FROM faces WHERE personId IS NULL")
    suspend fun getUnassignedFaces(): List<FaceEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPerson(person: PersonEntity): Long

    @Query("SELECT * FROM persons WHERE faceCount > 0 ORDER BY photoCount DESC, faceCount DESC")
    fun getAllPersons(): Flow<List<PersonEntity>>

    @Query("SELECT * FROM persons WHERE personId = :personId LIMIT 1")
    suspend fun getPersonById(personId: Long): PersonEntity?

    @Query("SELECT * FROM persons WHERE name = :name LIMIT 1")
    suspend fun findPersonByName(name: String): PersonEntity?

    @Query("UPDATE persons SET name = :name, updatedAt = :timestamp WHERE personId = :personId")
    suspend fun renamePerson(personId: Long, name: String, timestamp: Long = System.currentTimeMillis())

    @Query("UPDATE faces SET personId = :personId WHERE faceId IN (:faceIds)")
    suspend fun assignFacesToPerson(faceIds: List<Long>, personId: Long)

    @Query("UPDATE faces SET personId = :targetPersonId WHERE personId = :sourcePersonId")
    suspend fun mergePersons(sourcePersonId: Long, targetPersonId: Long)

    @Query("DELETE FROM persons WHERE personId = :personId")
    suspend fun deletePerson(personId: Long)

    @Query("""
        UPDATE persons SET
            faceCount = (SELECT COUNT(*) FROM faces WHERE faces.personId = persons.personId),
            photoCount = (SELECT COUNT(DISTINCT photoId) FROM faces WHERE faces.personId = persons.personId),
            avatarFaceId = (SELECT faceId FROM faces WHERE faces.personId = persons.personId LIMIT 1)
    """)
    suspend fun refreshPersonStats()

    @Query("""
        SELECT DISTINCT p.* FROM photos p
        INNER JOIN faces f ON p.photoId = f.photoId
        WHERE f.personId = :personId
        ORDER BY p.dateTaken DESC
    """)
    fun getPhotosForPerson(personId: Long): Flow<List<PhotoEntity>>

    @Query("""
        SELECT DISTINCT p.* FROM photos p
        WHERE p.photoId IN (SELECT photoId FROM faces WHERE personId = :p1)
          AND p.photoId IN (SELECT photoId FROM faces WHERE personId = :p2)
        ORDER BY p.dateTaken DESC
    """)
    fun getPhotosWithBoth(p1: Long, p2: Long): Flow<List<PhotoEntity>>

    @Query("""
        SELECT DISTINCT p.* FROM photos p
        WHERE p.photoId IN (SELECT photoId FROM faces WHERE personId IN (:personIds))
        ORDER BY p.dateTaken DESC
    """)
    fun getPhotosWithEither(personIds: List<Long>): Flow<List<PhotoEntity>>

    @Query("SELECT photoId, clipEmbedding FROM photos WHERE clipEmbedding IS NOT NULL")
    suspend fun getAllClipEmbeddings(): List<PhotoClipProjection>

    @Query("SELECT COUNT(*) FROM photos")
    fun getTotalPhotoCount(): Flow<Int>

    @Query("SELECT COUNT(*) FROM photos WHERE isProcessed = 1")
    fun getProcessedPhotoCount(): Flow<Int>

    @Query("SELECT COUNT(*) FROM persons WHERE faceCount > 0")
    fun getTotalPeopleCount(): Flow<Int>

    @Query("""
        SELECT f.faceId, f.photoId, p.uri as photoUri, f.bboxX1, f.bboxY1, f.bboxX2, f.bboxY2
        FROM faces f
        INNER JOIN photos p ON f.photoId = p.photoId
        WHERE f.personId = :personId
        LIMIT 1
    """)
    suspend fun getAvatarFaceForPerson(personId: Long): AvatarFaceInfo?

    @Query("SELECT * FROM persons WHERE personId IN (:personIds)")
    suspend fun getPersonsByIds(personIds: List<Long>): List<PersonEntity>
}

data class AvatarFaceInfo(
    val faceId: Long,
    val photoId: Long,
    val photoUri: String,
    val bboxX1: Float,
    val bboxY1: Float,
    val bboxX2: Float,
    val bboxY2: Float
)

data class PhotoClipProjection(
    val photoId: Long,
    val clipEmbedding: ByteArray
)
