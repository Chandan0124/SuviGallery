package com.suvi.gallery.data.ml

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.common.FileUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.sqrt

@Singleton
class MobileFaceNetEngine @Inject constructor(
    @ApplicationContext context: Context
) {
    private var interpreter: Interpreter? = null
    private val inputSize = 160
    private val embeddingDim = 512

    init {
        try {
            val modelBuffer = FileUtil.loadMappedFile(context, "mobilefacenet.tflite")
            val options = Interpreter.Options().apply {
                setNumThreads(4)
            }
            interpreter = Interpreter(modelBuffer, options)
            Log.i("MobileFaceNetEngine", "MobileFaceNet model loaded successfully.")
        } catch (e: Exception) {
            Log.e("MobileFaceNetEngine", "Failed to initialize TFLite interpreter", e)
        }
    }

    fun getEmbedding(faceBitmap: Bitmap): FloatArray {
        val interp = interpreter ?: return FloatArray(embeddingDim)
        if (faceBitmap.isRecycled) return FloatArray(embeddingDim)

        return try {
            val resized = Bitmap.createScaledBitmap(faceBitmap, inputSize, inputSize, true)
            val byteBuffer = ByteBuffer.allocateDirect(1 * inputSize * inputSize * 3 * 4)
                .order(ByteOrder.nativeOrder())

            val intValues = IntArray(inputSize * inputSize)
            resized.getPixels(intValues, 0, inputSize, 0, 0, inputSize, inputSize)

            // Standard FaceNet normalization: (pixel - 127.5) / 128.0
            for (pixelValue in intValues) {
                val r = (pixelValue shr 16 and 0xFF)
                val g = (pixelValue shr 8 and 0xFF)
                val b = (pixelValue and 0xFF)
                byteBuffer.putFloat((r - 127.5f) / 128.0f)
                byteBuffer.putFloat((g - 127.5f) / 128.0f)
                byteBuffer.putFloat((b - 127.5f) / 128.0f)
            }
            resized.recycle()

            // CRITICAL: Rewind buffer position back to 0 before passing to TFLite
            byteBuffer.rewind()

            val output = Array(1) { FloatArray(embeddingDim) }
            interp.run(byteBuffer, output)

            val emb = output[0]
            // L2 Unit Normalization
            var sumSquares = 0f
            for (v in emb) sumSquares += v * v
            val norm = sqrt(sumSquares)
            if (norm > 0f) {
                for (i in emb.indices) emb[i] /= norm
            }
            emb
        } catch (e: Exception) {
            Log.e("MobileFaceNetEngine", "Error generating face embedding", e)
            FloatArray(embeddingDim)
        }
    }

    fun close() {
        interpreter?.close()
    }
}
