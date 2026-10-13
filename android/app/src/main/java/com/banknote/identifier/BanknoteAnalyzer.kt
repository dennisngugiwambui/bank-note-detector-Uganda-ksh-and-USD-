package com.banknote.identifier

import android.graphics.Bitmap
import android.graphics.Matrix
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy

class BanknoteAnalyzer(
    private val classifier: BanknoteClassifier,
    private val onResult: (RecognitionResult) -> Unit
) : ImageAnalysis.Analyzer {

    private var lastSpokenClass: String = ""
    private var lastSpokenTime: Long = 0L
    private var consecutiveHits: Int = 0
    private var candidateClass: String = ""

    companion object {
        private const val CONFIDENCE_THRESHOLD = 0.82f
        private const val REQUIRED_CONSECUTIVE_FRAMES = 3
        private const val SPEECH_COOLDOWN_MS = 2500L
    }

    override fun analyze(imageProxy: ImageProxy) {
        val rotationDegrees = imageProxy.imageInfo.rotationDegrees
        val bitmap = imageProxy.toBitmap()

        val rotatedBitmap = if (rotationDegrees != 0) {
            val matrix = Matrix().apply { postRotate(rotationDegrees.toFloat()) }
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } else {
            bitmap
        }

        val result = classifier.classify(rotatedBitmap)
        imageProxy.close()

        if (result != null) {
            handleStabilization(result)
        }
    }

    private fun handleStabilization(result: RecognitionResult) {
        // Discard negative background class or low-confidence noise
        if (result.rawLabel == "Background" || result.confidence < CONFIDENCE_THRESHOLD) {
            consecutiveHits = 0
            candidateClass = ""
            onResult(result)
            return
        }

        if (result.rawLabel == candidateClass) {
            consecutiveHits++
        } else {
            candidateClass = result.rawLabel
            consecutiveHits = 1
        }

        val currentTime = System.currentTimeMillis()
        val isCooldownPassed = (currentTime - lastSpokenTime) > SPEECH_COOLDOWN_MS
        val isDifferentNote = (result.rawLabel != lastSpokenClass)

        // Only trigger audio feedback if prediction is stable over several consecutive frames
        if (consecutiveHits >= REQUIRED_CONSECUTIVE_FRAMES && (isDifferentNote || isCooldownPassed)) {
            lastSpokenClass = result.rawLabel
            lastSpokenTime = currentTime
            onResult(result)
        } else {
            // Update UI silently without triggering audio re-announcement
            onResult(result.copy(formattedSpokenText = ""))
        }
    }
}
