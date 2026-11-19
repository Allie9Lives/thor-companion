package com.alan.thor_companion

import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.media.ImageReader
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Feeds a hardware-encoded Annex-B stream (like screenrecord's) through ThorLiveVideo and checks frames reach the texture. */
@RunWith(AndroidJUnit4::class)
class ThorLiveVideoTest {
    private fun encode(width: Int, height: Int, frames: Int): ByteArray {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, 2_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 10)
        }
        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val input = encoder.createInputSurface()
        encoder.start()
        val out = ByteArrayOutputStream()
        val info = MediaCodec.BufferInfo()
        for (n in 0 until frames) {
            input.lockHardwareCanvas().also { it.drawColor(if (n % 2 == 0) Color.RED else Color.BLUE) }.let { input.unlockCanvasAndPost(it) }
            Thread.sleep(33)
            drain(encoder, info, out)
        }
        encoder.signalEndOfInputStream()
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, 100_000)
            if (index >= 0) {
                encoder.getOutputBuffer(index)!!.let { b -> ByteArray(info.size).also { b.get(it) } }.let(out::write)
                encoder.releaseOutputBuffer(index, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            } else if (index == MediaCodec.INFO_TRY_AGAIN_LATER) break
        }
        encoder.stop(); encoder.release(); input.release()
        return out.toByteArray()
    }

    private fun drain(encoder: MediaCodec, info: MediaCodec.BufferInfo, out: ByteArrayOutputStream) {
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, 0)
            if (index < 0) return
            encoder.getOutputBuffer(index)!!.let { b -> ByteArray(info.size).also { b.get(it) } }.let(out::write)
            encoder.releaseOutputBuffer(index, false)
        }
    }

    @Test
    fun decodesChunkedAnnexBIntoTheTexture() {
        val stream = encode(1280, 720, 20)
        assertTrue("encoder output is not Annex-B", stream.size > 100 && stream[0] == 0.toByte() && stream[3] == 1.toByte())

        val frames = AtomicInteger()
        val sized = CountDownLatch(1)
        var size = Pair(0, 0)
        val readerThread = HandlerThread("reader").apply { start() }
        val reader = ImageReader.newInstance(1280, 720, ImageFormat.PRIVATE, 4)
        reader.setOnImageAvailableListener({ r -> r.acquireLatestImage()?.close(); frames.incrementAndGet() }, Handler(readerThread.looper))
        val producer = object : TextureRegistry.SurfaceProducer {
            override fun id() = 7L
            override fun release() {}
            override fun setSize(width: Int, height: Int) {}
            override fun getWidth() = 1280
            override fun getHeight() = 720
            override fun getSurface(): Surface = reader.surface
            override fun getForcedNewSurface(): Surface = reader.surface
            override fun setCallback(callback: TextureRegistry.SurfaceProducer.Callback?) {}
            override fun scheduleFrame() {}
            override fun handlesCropAndRotation() = true
        }
        val registry = object : TextureRegistry {
            override fun createSurfaceProducer(lifecycle: TextureRegistry.SurfaceLifecycle) = producer
            override fun createSurfaceTexture() = throw UnsupportedOperationException()
            override fun registerSurfaceTexture(surfaceTexture: SurfaceTexture) = throw UnsupportedOperationException()
            override fun createImageTexture() = throw UnsupportedOperationException()
        }
        // Size reports arrive as channel calls to Dart; capture them from the outgoing message.
        val messenger = object : BinaryMessenger {
            override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)
            override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
                val call = io.flutter.plugin.common.StandardMethodCodec.INSTANCE.decodeMethodCall(message!!.duplicate().apply { if (position() == limit()) flip() else rewind(); order(java.nio.ByteOrder.nativeOrder()) })
                if (call.method == "size") { val m = call.arguments as Map<*, *>; size = Pair(m["width"] as Int, m["height"] as Int); sized.countDown() }
            }
            override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {}
        }
        val video = ThorLiveVideo(registry, MethodChannel(messenger, "test"))
        val noop = object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(code: String, message: String?, details: Any?) { throw AssertionError(message) }
            override fun notImplemented() { throw AssertionError() }
        }
        val started = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            video.call("start", null, object : MethodChannel.Result by noop { override fun success(result: Any?) { started.countDown() } })
        }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        // Uneven chunks split NAL units across feeds, as network reads do.
        var offset = 0
        var chunk = 1
        while (offset < stream.size) {
            val end = minOf(stream.size, offset + 997 * chunk)
            video.call("feed", stream.copyOfRange(offset, end), noop)
            offset = end; chunk = chunk % 7 + 1
        }
        assertTrue("no size reported", sized.await(10, TimeUnit.SECONDS))
        assertEquals(Pair(1280, 720), size)
        val deadline = System.currentTimeMillis() + 10_000
        while (frames.get() < 10 && System.currentTimeMillis() < deadline) Thread.sleep(50)
        assertTrue("only ${frames.get()} frames decoded", frames.get() >= 10)
        android.util.Log.i("ThorLiveVideoTest", "DECODED ${frames.get()} frames at ${size.first}x${size.second} from ${stream.size} bytes")
        video.dispose(); reader.close(); readerThread.quitSafely()
    }
}
