package com.banknote.identifier

import android.content.Context
import android.graphics.Bitmap
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.CompatibilityList
import org.tensorflow.lite.gpu.GpuDelegate
import org.tensorflow.lite.support.common.FileUtil
import org.tensorflow.lite.support.common.ops.NormalizeOp
import org.tensorflow.lite.support.image.ImageProcessor
import org.tensorflow.lite.support.image.TensorImage
import org.tensorflow.lite.support.image.ops.ResizeOp
import org.tensorflow.lite.support.label.TensorLabel
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer
import java.nio.MappedByteBuffer

data class RecognitionResult(
    val rawLabel: String,
    val currencyName: String,
    val denomination: String,
    val confidence: Float,
    val formattedSpokenText: String
)

class BanknoteClassifier(private val context: Context) {

    private var interpreter: Interpreter? = null
    private var gpuDelegate: GpuDelegate? = null
    private val labels: List<String>
    private val imageProcessor: ImageProcessor

    init {
        val modelBuffer: MappedByteBuffer = FileUtil.loadMappedFile(context, "banknote_model.tflite")
        val options = Interpreter.Options()

        // Enable GPU acceleration if supported on device
        val compatList = CompatibilityList()
        if (compatList.isDelegateSupportedOnThisDevice) {
            gpuDelegate = GpuDelegate(compatList.bestOptionsForThisDevice)
            options.addDelegate(gpuDelegate)
        } else {
            // High-performance CPU multithreading fallback
            options.setNumThreads(4)
        }

        interpreter = Interpreter(modelBuffer, options)
        labels = FileUtil.loadLabels(context, "labels.txt")

        // MobileNetV2 requires resize to 224x224 and normalization [-1, 1]
        // NormalizeOp(mean, std): (x - mean) / std => (x - 127.5f) / 127.5f
        imageProcessor = ImageProcessor.Builder()
            .add(ResizeOp(224, 224, ResizeOp.ResizeMethod.BILINEAR))
            .add(NormalizeOp(127.5f, 127.5f))
            .build()
    }

    fun classify(bitmap: Bitmap): RecognitionResult? {
        val tInterpreter = interpreter ?: return null

        var tensorImage = TensorImage.fromBitmap(bitmap)
        tensorImage = imageProcessor.process(tensorImage)

        // Allocate probability buffer matching output shape [1, num_classes]
        val outputProbabilityBuffer = TensorBuffer.createFixedSize(
            tInterpreter.getOutputTensor(0).shape(),
            tInterpreter.getOutputTensor(0).dataType()
        )

        tInterpreter.run(tensorImage.buffer, outputProbabilityBuffer.buffer.rewind())

        val labeledProbabilities = TensorLabel(labels, outputProbabilityBuffer).mapWithFloatValue
        val bestEntry = labeledProbabilities.maxByOrNull { it.value } ?: return null

        return parseLabel(bestEntry.key, bestEntry.value)
    }

    private fun parseLabel(label: String, confidence: Float): RecognitionResult {
        if (label.equals("Background", ignoreCase = true)) {
            return RecognitionResult(
                rawLabel = "Background",
                currencyName = "None",
                denomination = "None",
                confidence = confidence,
                formattedSpokenText = ""
            )
        }

        // Standard format: [ISO_CODE]_[DENOMINATION] (e.g. "KES_500")
        val parts = label.split("_")
        val code = parts.getOrNull(0) ?: "Unknown"
        val denom = parts.getOrNull(1) ?: ""

        val currencyFullName = when (code) {
            "INR" -> "Indian Rupee"
            "KES" -> "Kenyan Shilling"
            "EGP" -> "Egyptian Pound"
            "UGX" -> "Ugandan Shilling"
            "USD" -> "US Dollar"
            else -> code
        }

        val speech = "$denom $currencyFullName"

        return RecognitionResult(
            rawLabel = label,
            currencyName = currencyFullName,
            denomination = denom,
            confidence = confidence,
            formattedSpokenText = speech
        )
    }

    fun close() {
        interpreter?.close()
        gpuDelegate?.close()
    }
}
