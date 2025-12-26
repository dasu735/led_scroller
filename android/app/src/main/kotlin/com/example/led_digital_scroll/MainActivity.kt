package com.example.led_digital_scroll

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Rect
import android.media.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import android.util.Log
import android.graphics.Color as AndroidColor
import android.graphics.ImageFormat
import android.renderscript.Allocation
import android.renderscript.Element
import android.renderscript.RenderScript
import android.renderscript.ScriptIntrinsicYuvToRGB

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.led_digital_scroll/video_encoder"
    private val TAG = "VideoEncoder"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "encodeVideo" -> {
                    Thread {
                        try {
                            val framePaths = call.argument<List<String>>("framePaths")
                            val outputPath = call.argument<String>("outputPath")
                            val audioPath = call.argument<String>("audioPath")
                            val fps = call.argument<Int>("fps") ?: 15
                            val duration = call.argument<Int>("duration") ?: 5

                            if (framePaths != null && outputPath != null) {
                                val success = createVideoWithFramesAndAudio(
                                    framePaths,
                                    outputPath,
                                    audioPath,
                                    fps
                                )
                                runOnUiThread {
                                    result.success(success)
                                }
                            } else {
                                runOnUiThread {
                                    result.error("INVALID_ARGS", "Missing required arguments", null)
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error encoding video", e)
                            runOnUiThread {
                                result.error("ENCODING_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createVideoWithFramesAndAudio(
        framePaths: List<String>,
        outputPath: String,
        audioPath: String?,
        fps: Int
    ): Boolean {
        return try {
            Log.d(TAG, "Creating video with ${framePaths.size} frames, fps=$fps, audio=${audioPath != null}")
            
            if (framePaths.isEmpty()) {
                Log.e(TAG, "No frames provided")
                return false
            }
            
            // Get dimensions from first frame
            val firstBitmap = BitmapFactory.decodeFile(framePaths[0])
            val width = firstBitmap.width
            val height = firstBitmap.height
            firstBitmap.recycle()
            
            Log.d(TAG, "Video dimensions: ${width}x$height")
            
            // Create video
            val tempVideoPath = createVideoOnly(framePaths, width, height, fps)
            
            // If no audio, just rename temp file
            if (audioPath == null) {
                val tempFile = File(tempVideoPath)
                val outputFile = File(outputPath)
                tempFile.renameTo(outputFile)
                Log.d(TAG, "Video without audio created: $outputPath")
                return true
            }
            
            // Mux video with audio
            val muxResult = muxVideoWithAudio(tempVideoPath, audioPath, outputPath)
            if (!muxResult) {
                // If muxing fails, just copy the video without audio
                val tempFile = File(tempVideoPath)
                val outputFile = File(outputPath)
                tempFile.renameTo(outputFile)
                Log.d(TAG, "Video without audio created: $outputPath")
                return true
            }
            
            // Clean up temp video
            File(tempVideoPath).delete()
            
            Log.d(TAG, "Video with audio created: $outputPath")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error in createVideoWithFramesAndAudio", e)
            false
        }
    }
    
    private fun bitmapToNV21(bitmap: Bitmap): ByteArray {
        val width = bitmap.width
        val height = bitmap.height
        
        val argb = IntArray(width * height)
        bitmap.getPixels(argb, 0, width, 0, 0, width, height)
        
        val yuv = ByteArray(width * height * 3 / 2)
        var yIndex = 0
        var uvIndex = width * height
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                val rgb = argb[y * width + x]
                
                val r = (rgb shr 16) and 0xFF
                val g = (rgb shr 8) and 0xFF
                val b = rgb and 0xFF
                
                // Convert RGB to YUV
                val yValue = (0.299 * r + 0.587 * g + 0.114 * b).toInt().coerceIn(0, 255)
                val uValue = ((-0.147 * r - 0.289 * g + 0.436 * b + 128).toInt()).coerceIn(0, 255)
                val vValue = ((0.615 * r - 0.515 * g - 0.100 * b + 128).toInt()).coerceIn(0, 255)
                
                yuv[yIndex++] = yValue.toByte()
                
                // Only add UV values for every second pixel (4:2:0 subsampling)
                if (y % 2 == 0 && x % 2 == 0 && uvIndex + 1 < yuv.size) {
                    yuv[uvIndex++] = vValue.toByte() // V
                    yuv[uvIndex++] = uValue.toByte() // U
                }
            }
        }
        
        return yuv
    }
    
    private fun createVideoOnly(
        framePaths: List<String>,
        width: Int,
        height: Int,
        fps: Int
    ): String {
        val tempVideoPath = "${getCacheDir()}/temp_video_${System.currentTimeMillis()}.mp4"
        
        var mediaCodec: MediaCodec? = null
        var mediaMuxer: MediaMuxer? = null
        
        try {
            // Configure video encoder
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            format.setInteger(MediaFormat.KEY_BIT_RATE, 2000000) // 2 Mbps
            format.setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            
            mediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            mediaCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            mediaCodec.start()
            
            mediaMuxer = MediaMuxer(tempVideoPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            
            val bufferInfo = MediaCodec.BufferInfo()
            var trackIndex = -1
            var muxerStarted = false
            
            val frameDurationUs = (1000000 / fps).toLong()
            
            // Encode each frame
            for (i in framePaths.indices) {
                val framePath = framePaths[i]
                val bitmap = BitmapFactory.decodeFile(framePath)
                
                // Feed frame to encoder
                var inputBufferIndex = mediaCodec.dequeueInputBuffer(10000)
                if (inputBufferIndex >= 0) {
                    val inputBuffer = mediaCodec.getInputBuffer(inputBufferIndex)
                    inputBuffer?.clear()
                    
                    // Convert bitmap to YUV and feed to encoder
                    val frameBitmap = BitmapFactory.decodeFile(framePath)
                    if (frameBitmap != null) {
                        // Resize bitmap to match video dimensions if needed
                        val resizedBitmap = if (frameBitmap.width != width || frameBitmap.height != height) {
                            Bitmap.createScaledBitmap(frameBitmap, width, height, true)
                        } else {
                            frameBitmap
                        }
                        
                        // Convert bitmap to YUV420
                        val yuvBytes = bitmapToNV21(resizedBitmap)
                        
                        // Copy YUV data to input buffer
                        inputBuffer?.put(yuvBytes)
                        
                        // Clean up resized bitmap if it was created
                        if (resizedBitmap != frameBitmap) {
                            resizedBitmap.recycle()
                        }
                        
                        frameBitmap.recycle()
                        
                        val presentationTimeUs = i * frameDurationUs
                        mediaCodec.queueInputBuffer(inputBufferIndex, 0, yuvBytes.size, presentationTimeUs, 0)
                    }
                }
                
                // Get encoded output
                var outputBufferIndex = mediaCodec.dequeueOutputBuffer(bufferInfo, 10000)
                while (outputBufferIndex >= 0) {
                    if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        if (!muxerStarted) {
                            trackIndex = mediaMuxer.addTrack(mediaCodec.outputFormat)
                            mediaMuxer.start()
                            muxerStarted = true
                        }
                    } else {
                        val outputBuffer = mediaCodec.getOutputBuffer(outputBufferIndex)
                        if (outputBuffer != null && muxerStarted) {
                            mediaMuxer.writeSampleData(trackIndex, outputBuffer, bufferInfo)
                        }
                    }
                    mediaCodec.releaseOutputBuffer(outputBufferIndex, false)
                    outputBufferIndex = mediaCodec.dequeueOutputBuffer(bufferInfo, 0)
                }
                
            }
            
            // Signal end of stream
            var inputBufferIndex = mediaCodec.dequeueInputBuffer(10000)
            if (inputBufferIndex >= 0) {
                mediaCodec.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            }
            
            // Drain remaining output
            var outputBufferIndex = mediaCodec.dequeueOutputBuffer(bufferInfo, 10000)
            while (outputBufferIndex >= 0) {
                val outputBuffer = mediaCodec.getOutputBuffer(outputBufferIndex)
                if (outputBuffer != null && muxerStarted) {
                    mediaMuxer.writeSampleData(trackIndex, outputBuffer, bufferInfo)
                }
                mediaCodec.releaseOutputBuffer(outputBufferIndex, false)
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                outputBufferIndex = mediaCodec.dequeueOutputBuffer(bufferInfo, 0)
            }
            
            // Ensure muxer is stopped if it was started
            if (muxerStarted) {
                try {
                    mediaMuxer?.stop()
                } catch (e: Exception) {
                    Log.e(TAG, "Error stopping muxer", e)
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error encoding video", e)
            throw e
        } finally {
            try {
                mediaCodec?.stop()
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping codec", e)
            }
            mediaCodec?.release()
            mediaMuxer?.release()
        }
        
        return tempVideoPath
    }
    
    private fun muxVideoWithAudio(videoPath: String, audioPath: String, outputPath: String): Boolean {
        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null
        
        try {
            videoExtractor = MediaExtractor()
            videoExtractor.setDataSource(videoPath)
            
            audioExtractor = MediaExtractor()
            audioExtractor.setDataSource(audioPath)
            
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            
            // Find and add video track
            var videoTrackIndex = -1
            for (i in 0 until videoExtractor.trackCount) {
                val format = videoExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("video/") == true) {
                    videoExtractor.selectTrack(i)
                    videoTrackIndex = muxer.addTrack(format)
                    break
                }
            }
            
            // Find and add audio track
            var audioTrackIndex = -1
            for (i in 0 until audioExtractor.trackCount) {
                val format = audioExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") == true) {
                    audioExtractor.selectTrack(i)
                    audioTrackIndex = muxer.addTrack(format)
                    break
                }
            }
            
            // Start muxer only if both tracks are available
            if (videoTrackIndex >= 0 && audioTrackIndex >= 0) {
                muxer.start()
                
                // Synchronize video and audio samples
                val videoBuffer = ByteBuffer.allocate(1024 * 1024) // 1MB buffer
                val audioBuffer = ByteBuffer.allocate(256 * 1024) // 256KB buffer
                val videoBufferInfo = MediaCodec.BufferInfo()
                val audioBufferInfo = MediaCodec.BufferInfo()
                
                var videoSampleSize: Int = -1
                var audioSampleSize: Int = -1
                var videoSampleTime: Long = 0L
                var audioSampleTime: Long = 0L
                var videoTrackSelected = videoTrackIndex >= 0
                var audioTrackSelected = audioTrackIndex >= 0
                
                while (true) {
                    videoSampleSize = -1
                    audioSampleSize = -1
                    
                    // Read next video sample if available
                    if (videoTrackSelected) {
                        videoSampleSize = videoExtractor.readSampleData(videoBuffer, 0)
                        videoSampleTime = videoExtractor.sampleTime
                    }
                    
                    // Read next audio sample if available
                    if (audioTrackSelected) {
                        audioSampleSize = audioExtractor.readSampleData(audioBuffer, 0)
                        audioSampleTime = audioExtractor.sampleTime
                    }
                    
                    // Determine which sample to write next based on timestamp
                    if (videoSampleSize >= 0 || audioSampleSize >= 0) {
                        if (videoSampleSize >= 0 && 
                            (audioSampleSize < 0 || videoSampleTime < audioSampleTime)) {
                            // Write video sample
                            videoBufferInfo.size = videoSampleSize
                            videoBufferInfo.presentationTimeUs = videoSampleTime
                            videoBufferInfo.flags = videoExtractor.sampleFlags
                            muxer.writeSampleData(videoTrackIndex, videoBuffer, videoBufferInfo)
                            videoExtractor.advance()
                        } else if (audioSampleSize >= 0) {
                            // Write audio sample
                            audioBufferInfo.size = audioSampleSize
                            audioBufferInfo.presentationTimeUs = audioSampleTime
                            audioBufferInfo.flags = audioExtractor.sampleFlags
                            muxer.writeSampleData(audioTrackIndex, audioBuffer, audioBufferInfo)
                            audioExtractor.advance()
                        }
                    } else {
                        // No more samples from either track
                        break
                    }
                }
            } else {
                // If one of the tracks is missing, copy the available one
                if (videoTrackIndex >= 0) {
                    // Copy video track only
                    muxer.start()
                    val buffer = ByteBuffer.allocate(1024 * 1024)
                    val bufferInfo = MediaCodec.BufferInfo()
                    
                    videoExtractor.selectTrack(0) // Select the video track
                    while (true) {
                        val sampleSize = videoExtractor.readSampleData(buffer, 0)
                        if (sampleSize < 0) break
                        
                        bufferInfo.size = sampleSize
                        bufferInfo.presentationTimeUs = videoExtractor.sampleTime
                        bufferInfo.flags = videoExtractor.sampleFlags
                        muxer.writeSampleData(videoTrackIndex, buffer, bufferInfo)
                        videoExtractor.advance()
                    }
                } else if (audioTrackIndex >= 0) {
                    // Copy audio track only
                    muxer.start()
                    val buffer = ByteBuffer.allocate(256 * 1024)
                    val bufferInfo = MediaCodec.BufferInfo()
                    
                    audioExtractor.selectTrack(0) // Select the audio track
                    while (true) {
                        val sampleSize = audioExtractor.readSampleData(buffer, 0)
                        if (sampleSize < 0) break
                        
                        bufferInfo.size = sampleSize
                        bufferInfo.presentationTimeUs = audioExtractor.sampleTime
                        bufferInfo.flags = audioExtractor.sampleFlags
                        muxer.writeSampleData(audioTrackIndex, buffer, bufferInfo)
                        audioExtractor.advance()
                    }
                }
            }
            
            Log.d(TAG, "Muxing completed: $outputPath")
            return true
            
        } catch (e: Exception) {
            Log.e(TAG, "Error muxing video with audio", e)
            return false
        } finally {
            try {
                videoExtractor?.release()
                audioExtractor?.release()
                // Only stop muxer if it was started and is in started state
                muxer?.release() // MediaMuxer automatically stops when released
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing muxer", e)
            }
        }
    }
}
