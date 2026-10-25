package com.suvi.gallery.data.ml

import android.graphics.Bitmap
import android.graphics.Rect
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

@Singleton
class FaceDetectorEngine @Inject constructor() {
    private val detector: FaceDetector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setMinFaceSize(0.10f)
            .build()
    )

    suspend fun detectFaces(bitmap: Bitmap): List<Rect> {
        if (bitmap.isRecycled) return emptyList()

        return suspendCancellableCoroutine { cont ->
            try {
                val image = InputImage.fromBitmap(bitmap, 0)
                detector.process(image)
                    .addOnSuccessListener { faces ->
                        if (cont.isActive) {
                            cont.resume(faces.map { it.boundingBox })
                        }
                    }
                    .addOnFailureListener { e ->
                        Log.w("FaceDetectorEngine", "Face detection failed: ${e.message}")
                        if (cont.isActive) {
                            cont.resume(emptyList())
                        }
                    }
            } catch (e: Throwable) {
                Log.e("FaceDetectorEngine", "Error submitting image to detector", e)
                if (cont.isActive) {
                    cont.resume(emptyList())
                }
            }
        }
    }
}
