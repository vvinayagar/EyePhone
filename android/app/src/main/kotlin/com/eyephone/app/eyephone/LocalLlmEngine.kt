package com.eyephone.app.eyephone

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import java.io.File
import java.util.concurrent.Executors

/**
 * On-device multimodal inference backed by MediaPipe LLM Inference (Gemma 3n).
 *
 * This is the real replacement for the AICore / Gemini Nano path, which cannot run on
 * pre-2024 silicon. The model is a .task bundle the user supplies once; it is never
 * bundled in the APK (3-4 GB) and camera frames never leave the device.
 *
 * All inference runs on a single background thread — loading takes 10-30s and generation
 * several seconds, so nothing here may touch the main thread. Results are posted back to
 * the main looper because MethodChannel replies must be sent from there.
 */
class LocalLlmEngine(private val context: Context) {

    companion object {
        private const val TAG = "LocalLlmEngine"

        // Preferred bundles in order. Vision-capable ones come first: only Gemma 3n can
        // actually look at a camera frame, which is what this app fundamentally needs.
        private val KNOWN_MODEL_FILES = listOf(
            "gemma-3n-E4B-it-int4.task",
            "gemma-3n-E2B-it-int4.task",
            "deepseek_q8_ekv1280.task",
        )

        /**
         * Whether a bundle can accept images.
         *
         * Gemma 3n is multimodal; DeepSeek R1 distills and Gemma 3 1B are text-only. Sending
         * an image to a text-only graph fails inside MediaPipe, so this gates it up front.
         */
        fun modelSupportsVision(fileName: String): Boolean {
            val n = fileName.lowercase()
            return n.contains("gemma-3n") || n.contains("gemma3n")
        }

        // Gemma 3n encodes images as 256 tokens each; keep headroom for prompt + answer.
        private const val MAX_TOKENS = 1024

        // The vision encoder works on small square inputs. Downscaling before handing the
        // frame over cuts inference time substantially with no accuracy loss at this size.
        private const val MAX_IMAGE_EDGE = 512
    }

    enum class State { IDLE, LOADING, READY, ERROR }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var llm: LlmInference? = null
    @Volatile private var state: State = State.IDLE
    @Volatile private var lastError: String? = null
    @Volatile private var loadedModelPath: String? = null
    @Volatile private var activeBackend: String = ""

    /** Directory the user drops the .task bundle into. */
    fun modelsDir(): File {
        val dir = File(context.getExternalFilesDir(null), "models")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    /** First recognised model bundle present on disk, or null. */
    private fun findModelFile(): File? {
        val dir = modelsDir()
        for (name in KNOWN_MODEL_FILES) {
            val f = File(dir, name)
            if (f.isFile && f.length() > 0) return f
        }
        // Fall back to any .task file so users can bring their own quantisation.
        return dir.listFiles()?.firstOrNull { it.isFile && it.name.endsWith(".task") && it.length() > 0 }
    }

    fun status(): Map<String, Any?> {
        val model = findModelFile()
        return mapOf(
            "state" to state.name,
            "modelPresent" to (model != null),
            "modelName" to (model?.name ?: ""),
            "modelPath" to (model?.absolutePath ?: ""),
            "modelSizeBytes" to (model?.length() ?: 0L),
            "modelsDir" to modelsDir().absolutePath,
            "loadedModelPath" to (loadedModelPath ?: ""),
            "supportsVision" to (model != null && modelSupportsVision(model.name)),
            "backend" to activeBackend,
            "error" to (lastError ?: ""),
        )
    }

    /**
     * Loads the model into memory. Safe to call repeatedly; a load already in flight or a
     * model already resident is reported without redoing the work.
     */
    fun initialize(onResult: (Map<String, Any?>) -> Unit) {
        if (state == State.READY && llm != null) {
            onResult(status() + ("alreadyLoaded" to true))
            return
        }
        if (state == State.LOADING) {
            onResult(status() + ("alreadyLoading" to true))
            return
        }

        val modelFile = findModelFile()
        if (modelFile == null) {
            state = State.ERROR
            lastError = "No .task model bundle found in ${modelsDir().absolutePath}"
            onResult(status())
            return
        }

        state = State.LOADING
        lastError = null

        worker.execute {
            try {
                llm?.close()
                llm = null

                val vision = modelSupportsVision(modelFile.name)

                // GPU is typically several times faster than the XNNPack CPU path, but not
                // every .task bundle has GPU weights. Try it, then fall back rather than
                // leaving the user with no local engine at all.
                llm = createEngine(modelFile, vision, LlmInference.Backend.GPU)
                    ?: createEngine(modelFile, vision, LlmInference.Backend.CPU)
                    ?: throw IllegalStateException("Model could not be loaded on GPU or CPU")

                loadedModelPath = modelFile.absolutePath
                state = State.READY
                Log.i(TAG, "Loaded local model: ${modelFile.name}")
            } catch (t: Throwable) {
                // OOM and native loader failures arrive as Errors, not Exceptions.
                Log.e(TAG, "Model load failed", t)
                llm = null
                loadedModelPath = null
                state = State.ERROR
                lastError = t.message ?: t.toString()
            }
            main.post { onResult(status()) }
        }
    }

    /** Builds the engine on a specific backend, returning null if that backend is unusable. */
    private fun createEngine(
        modelFile: File,
        vision: Boolean,
        backend: LlmInference.Backend,
    ): LlmInference? {
        return try {
            val builder = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelFile.absolutePath)
                .setMaxTokens(MAX_TOKENS)
                .setPreferredBackend(backend)
            // Declaring image slots on a text-only graph fails the load outright.
            if (vision) builder.setMaxNumImages(1)
            val engine = LlmInference.createFromOptions(context, builder.build())
            Log.i(TAG, "Engine created on $backend")
            activeBackend = backend.name
            engine
        } catch (t: Throwable) {
            Log.w(TAG, "Backend $backend unavailable: ${t.message}")
            null
        }
    }

    /**
     * Runs one prompt, optionally with a single camera frame.
     *
     * A fresh session per call is deliberate: each scan is independent, and reusing a session
     * would accumulate prior frames in the context window until it overflows.
     */
    fun generate(prompt: String, imageBytes: ByteArray?, onResult: (Map<String, Any?>) -> Unit) {
        val engine = llm
        if (state != State.READY || engine == null) {
            onResult(
                mapOf(
                    "success" to false,
                    "error" to (lastError ?: "Local model is not loaded"),
                    "state" to state.name,
                )
            )
            return
        }

        // A text-only model cannot see the frame; drop it rather than fail the whole call,
        // so the caller can fall back to a vision engine.
        val visionCapable = loadedModelPath?.let { modelSupportsVision(File(it).name) } ?: false
        val usableImage = if (visionCapable) imageBytes else null

        worker.execute {
            var session: LlmInferenceSession? = null
            val startedAt = System.currentTimeMillis()
            try {
                val sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                    .setTopK(40)
                    .setTopP(0.9f)
                    // Low temperature: navigation guidance must be literal, not creative.
                    .setTemperature(0.2f)
                    .setGraphOptions(
                        GraphOptions.builder()
                            .setEnableVisionModality(usableImage != null)
                            .build()
                    )
                    .build()

                session = LlmInferenceSession.createFromOptions(engine, sessionOptions)
                session.addQueryChunk(prompt)

                if (usableImage != null) {
                    val bitmap = decodeScaled(usableImage)
                        ?: throw IllegalArgumentException("Camera frame could not be decoded")
                    session.addImage(BitmapImageBuilder(bitmap).build())
                }

                val response = session.generateResponse()
                val elapsed = System.currentTimeMillis() - startedAt
                Log.i(TAG, "Local inference finished in ${elapsed}ms")

                main.post {
                    onResult(
                        mapOf(
                            "success" to true,
                            "response" to (response ?: ""),
                            "usedImage" to (usableImage != null),
                            "elapsedMs" to elapsed,
                            "engine" to (loadedModelPath?.let { File(it).name } ?: "local"),
                        )
                    )
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Local inference failed", t)
                main.post {
                    onResult(
                        mapOf(
                            "success" to false,
                            "error" to (t.message ?: t.toString()),
                            "state" to state.name,
                        )
                    )
                }
            } finally {
                try {
                    session?.close()
                } catch (t: Throwable) {
                    Log.w(TAG, "Session close failed", t)
                }
            }
        }
    }

    /** Decodes JPEG bytes, downscaled to keep the vision encoder fast. */
    private fun decodeScaled(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val longest = maxOf(bounds.outWidth, bounds.outHeight)

        val opts = BitmapFactory.Options()
        if (longest > MAX_IMAGE_EDGE) {
            var sample = 1
            while (longest / sample > MAX_IMAGE_EDGE) sample *= 2
            opts.inSampleSize = sample
        }
        // MediaPipe requires ARGB_8888 input.
        opts.inPreferredConfig = Bitmap.Config.ARGB_8888

        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) ?: return null
        if (decoded.config == Bitmap.Config.ARGB_8888) return decoded
        return decoded.copy(Bitmap.Config.ARGB_8888, false).also { decoded.recycle() }
    }

    fun dispose() {
        worker.execute {
            try {
                llm?.close()
            } catch (t: Throwable) {
                Log.w(TAG, "Engine close failed", t)
            }
            llm = null
            loadedModelPath = null
            state = State.IDLE
        }
        worker.shutdown()
    }
}
