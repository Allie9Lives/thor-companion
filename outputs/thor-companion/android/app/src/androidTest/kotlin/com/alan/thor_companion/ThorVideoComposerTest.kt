package com.alan.thor_companion

import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Needs two real recordings pushed to /data/local/tmp/thor-top.mp4 and thor-bottom.mp4 (screenrecord on a Thor). */
@RunWith(AndroidJUnit4::class)
class ThorVideoComposerTest {
    private fun meta(file: File, key: Int): Long {
        val r = MediaMetadataRetriever()
        try { r.setDataSource(file.path); return r.extractMetadata(key)!!.toLong() } finally { r.release() }
    }

    @Test
    fun stacksTopAboveBottomAtNativeSize() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val inputs = listOf("top", "bottom").map { File("/data/local/tmp/thor-$it.mp4") }
        assumeTrue("push two recordings first", inputs.all { it.canRead() })
        val dir = File(context.cacheDir, "thor-transfers").apply { mkdirs() }
        val clips = inputs.map { source -> File(dir, source.name).also { source.copyTo(it, overwrite = true) } }
        val output = File(dir, "combined-test.mp4").apply { delete() }
        val done = CountDownLatch(1)
        var failure: Exception? = null
        Handler(Looper.getMainLooper()).post {
            ThorVideoComposer.compose(context, clips, listOf(0.0, 120.0), 30, output) { failure = it; done.countDown() }
        }
        assertTrue("export timed out", done.await(120, TimeUnit.SECONDS))
        assertNull(failure)
        val w = MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
        val h = MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
        // Displayed size: encoders may store portrait output as landscape plus a rotation flag.
        fun shown(f: File): Pair<Long, Long> =
            if (meta(f, MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) % 180 == 90L) meta(f, h) to meta(f, w) else meta(f, w) to meta(f, h)
        fun even(v: Long) = (v + 1) / 2 * 2
        val (outW, outH) = shown(output)
        assertEquals(even(clips.maxOf { shown(it).first }), outW)
        assertEquals(even(clips.sumOf { shown(it).second }), outH)
        // The top clip is trimmed 120 ms to line up with the bottom, then both end at the shorter one.
        val expected = minOf(meta(clips[0], MediaMetadataRetriever.METADATA_KEY_DURATION) - 120, meta(clips[1], MediaMetadataRetriever.METADATA_KEY_DURATION))
        val actual = meta(output, MediaMetadataRetriever.METADATA_KEY_DURATION)
        assertTrue("duration $actual vs $expected", kotlin.math.abs(actual - expected) < 250)
        MediaMetadataRetriever().run {
            setDataSource(output.path)
            getFrameAtTime(1_000_000)?.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, File(dir, "combined-frame.png").outputStream())
            release()
        }
        android.util.Log.i("ThorComposerTest", "COMPOSED ${outW}x$outH ${actual}ms from " + clips.joinToString { "${shown(it).first}x${shown(it).second}" })
    }
}
