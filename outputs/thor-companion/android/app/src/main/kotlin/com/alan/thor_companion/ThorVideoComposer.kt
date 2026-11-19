package com.alan.thor_companion

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.util.Size
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File
import kotlin.math.roundToLong

/** Stacks the top and bottom recordings like the iOS composer: top above bottom, centred, top-track audio. */
object ThorVideoComposer {
    private class Track(val durationMs: Long, val hasAudio: Boolean)

    private fun inspect(file: File): Track {
        val retriever = MediaMetadataRetriever()
        val duration = try {
            retriever.setDataSource(file.path)
            fun number(key: Int) = retriever.extractMetadata(key)?.toLongOrNull() ?: 0
            val ms = number(MediaMetadataRetriever.METADATA_KEY_DURATION)
            require(ms in 1..190_000 &&
                number(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH) in 1..4096 &&
                number(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT) in 1..4096) { "Unsupported recording" }
            ms
        } finally {
            retriever.release()
        }
        val extractor = MediaExtractor()
        val audio = try {
            extractor.setDataSource(file.path)
            (0 until extractor.trackCount).any { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
        } finally {
            extractor.release()
        }
        return Track(duration, audio)
    }

    /** Must be called on a thread with a Looper (Transformer requirement); [done] runs on that thread. */
    fun compose(context: Context, sources: List<File>, offsetsMs: List<Double>, fps: Int, output: File, done: (Exception?) -> Unit): Transformer? {
        try {
            require(sources.size == 2 && offsetsMs.size == 2 && fps in listOf(30, 60) && offsetsMs.all { it.isFinite() && it in 0.0..10_000.0 }) { "Invalid recording tracks" }
            val tracks = sources.map(::inspect)
            val commonStart = offsetsMs.max()
            val starts = offsetsMs.map { (commonStart - it).roundToLong() }
            val duration = tracks.indices.minOf { tracks[it].durationMs - starts[it] }
            require(duration > 0) { "The recording is too short to combine" }
            val sequences = sources.indices.map { index ->
                val item = MediaItem.Builder()
                    .setUri(Uri.fromFile(sources[index]))
                    .setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(starts[index])
                            .setEndPositionMs(starts[index] + duration)
                            .build(),
                    )
                    .build()
                val audio = index == 0 && tracks[0].hasAudio
                val edited = EditedMediaItem.Builder(item).setFrameRate(fps).setRemoveAudio(!audio).build()
                val types = if (audio) setOf(C.TRACK_TYPE_VIDEO, C.TRACK_TYPE_AUDIO) else setOf(C.TRACK_TYPE_VIDEO)
                EditedMediaItemSequence.Builder(types).addItem(edited).build()
            }
            val layout = object : VideoCompositorSettings {
                override fun getOutputSize(inputSizes: List<Size>): Size {
                    fun even(value: Int) = (value + 1) / 2 * 2
                    return Size(even(inputSizes.maxOf { it.width }), even(inputSizes.sumOf { it.height }))
                }

                // Scale 1 keeps each screen at its native pixel size; anchors pin top/bottom edges.
                override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
                    val edge = if (inputId == 0) 1f else -1f
                    return StaticOverlaySettings.Builder()
                        .setOverlayFrameAnchor(0f, edge)
                        .setBackgroundFrameAnchor(0f, edge)
                        .build()
                }
            }
            val composition = Composition.Builder(sequences).setVideoCompositorSettings(layout).build()
            val transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) = done(null)
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        output.delete()
                        done(exportException)
                    }
                })
                .build()
            transformer.start(composition, output.path)
            return transformer
        } catch (e: Exception) {
            output.delete()
            done(e)
            return null
        }
    }
}
