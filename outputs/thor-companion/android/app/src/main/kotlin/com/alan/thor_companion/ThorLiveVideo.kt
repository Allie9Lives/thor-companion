package com.alan.thor_companion

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer

/** Decodes the Thor's raw H.264 live view into a Flutter texture. Dart owns the pinned network stream. */
/** One decoder per Thor screen ([id] 0 top, 1 bottom); size and reset callbacks carry the id. */
class ThorLiveVideo(private val textures: TextureRegistry, private val channel: MethodChannel, private val id: Int = 0) {
    private val thread = HandlerThread("ThorLiveVideo").apply { start() }
    private val handler = Handler(thread.looper)
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var producer: TextureRegistry.SurfaceProducer? = null
    private var codec: MediaCodec? = null
    private var sps: ByteArray? = null
    private var pps: ByteArray? = null
    private var waitingForKeyframe = true
    private var carry = ByteArray(0)
    private val frames = ArrayDeque<ByteArray>()
    private val inputs = ArrayDeque<Int>()

    fun call(method: String, bytes: ByteArray?, result: MethodChannel.Result) {
        when (method) {
            "start" -> {
                handler.post { reset() }
                main.post {
                    producer?.release()
                    val p = textures.createSurfaceProducer()
                    p.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                        // The surface can be replaced while backgrounded; Dart reopens the stream for a new keyframe.
                        override fun onSurfaceCleanup() { handler.post { reset() }; channel.invokeMethod("reset", mapOf("id" to id)) }
                    })
                    producer = p
                    result.success(p.id())
                }
            }
            "feed" -> {
                if (bytes == null || bytes.size > 4 * 1024 * 1024) { result.error("live", "Invalid video data", null); return }
                handler.post { feed(bytes) }
                result.success(null)
            }
            "stop" -> {
                handler.post { reset() }
                main.post { producer?.release(); producer = null; result.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    private fun reset() {
        try { codec?.stop() } catch (_: Exception) {}
        codec?.release()
        codec = null
        sps = null; pps = null; waitingForKeyframe = true
        carry = ByteArray(0); frames.clear(); inputs.clear()
    }

    private fun feed(bytes: ByteArray) {
        val data = carry + bytes
        val starts = mutableListOf<Int>()
        var i = 0
        while (i + 3 < data.size) {
            if (data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 0.toByte() && data[i + 3] == 1.toByte()) { starts.add(i); i += 4 } else i++
        }
        if (starts.isEmpty()) { carry = if (data.size > 8 * 1024 * 1024) ByteArray(0) else data; return }
        for (n in 0 until starts.size - 1) nal(data.copyOfRange(starts[n], starts[n + 1]))
        carry = data.copyOfRange(starts.last(), data.size) // last NAL may be incomplete
    }

    // screenrecord emits 4-byte start codes; parameter sets repeat unchanged when it restarts every 180 s.
    private fun nal(unit: ByteArray) {
        if (unit.size < 5) return
        val type = unit[4].toInt() and 31
        if (type == 7) { if (codec == null) sps = unit; return }
        if (type == 8) { if (codec == null) { pps = unit; configure() }; return }
        if (type != 1 && type != 5) return
        // Falling behind: drop to the next keyframe rather than build latency.
        if (frames.size > 30) { frames.clear(); waitingForKeyframe = true }
        if (type == 5) waitingForKeyframe = false
        if (waitingForKeyframe) return
        frames.addLast(unit)
        pump()
    }

    private fun configure() {
        val surface = producer?.surface ?: return
        val s = sps ?: return
        val p = pps ?: return
        if (codec != null) return
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1080).apply {
            setByteBuffer("csd-0", ByteBuffer.wrap(s))
            setByteBuffer("csd-1", ByteBuffer.wrap(p))
            setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
        }
        val decoder = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        decoder.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(c: MediaCodec, index: Int) { if (c == codec) { inputs.addLast(index); pump() } }
            override fun onOutputBufferAvailable(c: MediaCodec, index: Int, info: MediaCodec.BufferInfo) { if (c == codec) c.releaseOutputBuffer(index, true) }
            override fun onError(c: MediaCodec, e: MediaCodec.CodecException) { if (c == codec) { reset(); main.post { channel.invokeMethod("reset", mapOf("id" to id)) } } }
            override fun onOutputFormatChanged(c: MediaCodec, f: MediaFormat) {
                val w = if (f.containsKey("crop-right")) f.getInteger("crop-right") - f.getInteger("crop-left") + 1 else f.getInteger(MediaFormat.KEY_WIDTH)
                val h = if (f.containsKey("crop-bottom")) f.getInteger("crop-bottom") - f.getInteger("crop-top") + 1 else f.getInteger(MediaFormat.KEY_HEIGHT)
                main.post { producer?.setSize(w, h); channel.invokeMethod("size", mapOf("id" to id, "width" to w, "height" to h)) }
            }
        }, handler)
        decoder.configure(format, surface, null, 0)
        decoder.start()
        codec = decoder
    }

    private fun pump() {
        val c = codec ?: return
        while (frames.isNotEmpty() && inputs.isNotEmpty()) {
            val index = inputs.removeFirst()
            val frame = frames.removeFirst()
            val buffer = c.getInputBuffer(index) ?: continue
            if (frame.size > buffer.capacity()) { c.queueInputBuffer(index, 0, 0, 0, 0); continue }
            buffer.clear(); buffer.put(frame)
            c.queueInputBuffer(index, 0, frame.size, System.nanoTime() / 1000, 0)
        }
    }

    fun dispose() {
        handler.post { reset(); thread.quitSafely() }
        main.post { producer?.release(); producer = null }
    }
}
