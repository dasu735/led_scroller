import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

class VideoRecorder {
  // Main method to record video with background audio
  static Future<String?> recordVideo({
    required GlobalKey boundaryKey,
    int durationSeconds = 10,
    int fps = 15, // Lower FPS for faster processing
    String? audioPath,
    int maxWidth = 720, // WhatsApp status width
    int maxHeight = 1280, // WhatsApp status height
    String fitMode =
        'vertical', // 'vertical' (status) or 'horizontal' (full width)
    Function(double)? onProgress,
    Function(String)? onComplete,
    bool saveToGallery = true, // Auto-save to gallery
  }) async {
    String? resolvedAudioPath = audioPath;
    // If audioPath is an asset, copy to temp file
    if (audioPath != null && audioPath.startsWith('assets/')) {
      try {
        final byteData = await rootBundle.load(audioPath);
        final tempDir = await getTemporaryDirectory();
        final tempAudioFile = File(p.join(tempDir.path, p.basename(audioPath)));
        await tempAudioFile.writeAsBytes(byteData.buffer.asUint8List(),
            flush: true);
        resolvedAudioPath = tempAudioFile.path;
        print('Copied asset audio to temp: $resolvedAudioPath');
      } catch (e) {
        print('Failed to copy asset audio: $e');
        resolvedAudioPath = null;
      }
    }
    try {
      // Request correct permissions based on Android version
      bool hasPermission = false;
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        if (sdkInt >= 33) {
          // Android 13+ (API 33+): request media permissions
          final videoStatus = await Permission.videos.request();
          final audioStatus = await Permission.audio.request();
          hasPermission = videoStatus.isGranted || audioStatus.isGranted;
        } else {
          // Android 12 and below: request storage
          final storageStatus = await Permission.storage.request();
          hasPermission = storageStatus.isGranted;
        }
      } else {
        hasPermission = true; // Not Android, assume granted
      }
      if (!hasPermission) {
        print('❌ Storage/media permission not granted.');
        return null;
      }
      print(
          '🎬 Starting optimized video recording (${durationSeconds}s @ ${fps}fps)...');

      // Step 1: Capture frames efficiently
      final frames = await _captureFramesOptimized(
        boundaryKey: boundaryKey,
        durationSeconds: durationSeconds,
        fps: fps,
        onProgress: (progress) {
          onProgress?.call(progress * 0.3); // 30% for capture
        },
      );

      if (frames.isEmpty) {
        print('❌ No frames captured');
        return null;
      }

      print('✅ Captured ${frames.length} frames');

      // Step 2: Create video with audio
      onProgress?.call(0.3);
      final videoPath = await _createVideoWithFfmpeg(
        framePaths: frames,
        fps: fps,
        audioPath: resolvedAudioPath,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        fitMode: fitMode,
        onProgress: (progress) {
          onProgress?.call(0.3 + progress * 0.7); // 70% for encoding
        },
      );

      if (videoPath == null || !await File(videoPath).exists()) {
        print('❌ Failed to create video');
        return null;
      }

      // Step 3: Save to gallery automatically
      if (saveToGallery) {
        final saved = await saveVideoToGallery(videoPath);
        if (saved) {
          print('💾 Video saved to gallery');
        }
      }

      final fileSize = await File(videoPath).length();
      print('🎉 Video created: $videoPath (${fileSize ~/ 1024}KB)');
      onComplete?.call(videoPath);
      return videoPath;
    } catch (e, stack) {
      print('❌ Video recording error: $e');
      print('Stack trace: $stack');
    }
  }

  /// Optimized frame capture with performance improvements
  static Future<List<String>> _captureFramesOptimized({
    required GlobalKey boundaryKey,
    required int durationSeconds,
    required int fps,
    Function(double)? onProgress,
  }) async {
    final List<String> framePaths = [];
    final frameCount = durationSeconds * fps;
    final frameDelay = Duration(milliseconds: (1000 / fps).round());

    // Create frames directory
    final tempDir = await getTemporaryDirectory();
    final framesDir = Directory(p.join(
        tempDir.path, 'frames_${DateTime.now().millisecondsSinceEpoch}'));
    await framesDir.create(recursive: true);

    try {
      for (int i = 0; i < frameCount; i++) {
        try {
          // Get render boundary
          final boundary = boundaryKey.currentContext?.findRenderObject();
          if (boundary is! RenderRepaintBoundary) {
            await Future.delayed(frameDelay);
            continue;
          }

          // Capture frame
          final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
          final ByteData? byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);

          if (byteData != null) {
            // Save frame to file immediately to save memory
            final framePath = p.join(
                framesDir.path, 'frame_${i.toString().padLeft(6, '0')}.png');
            await File(framePath)
                .writeAsBytes(byteData.buffer.asUint8List(), flush: true);
            framePaths.add(framePath);
          }

          // Update progress every 5 frames to reduce UI updates
          if (i % 5 == 0 || i == frameCount - 1) {
            onProgress?.call(i / frameCount);
          }

          // Delay between frames
          if (i < frameCount - 1) {
            await Future.delayed(frameDelay);
          }
        } catch (e) {
          print('⚠️ Error capturing frame $i: $e');
        }
      }
    } catch (e) {
      print('❌ Frame capture failed: $e');
    }

    return framePaths;
  }

  /// Create video using FFmpeg with hardware acceleration
  static Future<String?> _createVideoWithFfmpeg({
    required List<String> framePaths,
    required int fps,
    String? audioPath,
    int maxWidth = 720,
    int maxHeight = 1280,
    String fitMode = 'vertical',
    Function(double)? onProgress,
  }) async {
    if (framePaths.isEmpty) return null;

    // Debug: Print frame count and first/last frame file names
    print('FFmpeg input: ${framePaths.length} frames');
    if (framePaths.isNotEmpty) {
      print('First frame: ${framePaths.first}');
      print('Last frame: ${framePaths.last}');
    }

    try {
      // Get output directory (use external storage for better performance)
      final Directory? externalDir = await getExternalStorageDirectory();
      final outputDir = externalDir ?? await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = p.join(outputDir.path, 'led_video_$timestamp.mp4');

      print('📁 Creating video at: $outputPath');

      // Use image2 demuxer with sequentially named frames
      final framesDir = p.dirname(framePaths.first);
      final framePattern = p.join(framesDir, 'frame_%06d.png');

      // Build FFmpeg command with hardware acceleration
      // Ensure width and height are even numbers for libx264
      // WhatsApp status: 9:16 portrait, e.g., 720x1280
      String scaleFilter;
      if (fitMode == 'horizontal') {
        // Fill width, keep height (no vertical crop/pad)
        scaleFilter = "scale=$maxWidth:-1";
      } else {
        // WhatsApp status: 9:16 portrait, crop to fit
        scaleFilter =
            "scale=$maxWidth:$maxHeight:force_original_aspect_ratio=increase,crop=$maxWidth:$maxHeight";
      }
      String command;
      if (audioPath != null) {
        print('🔎 audioPath provided: $audioPath');
        final audioFile = File(audioPath);
        final audioExists = await audioFile.exists();
        print('🔎 audioPath exists: $audioExists');
        print('🔎 audioPath extension: ${p.extension(audioPath)}');
        if (audioExists) {
          // Video with audio: force sample rate, channel count
          command = '-framerate $fps -i "$framePattern" '
              '-i "${audioPath}" '
              '-c:v libx264 -preset ultrafast -tune zerolatency '
              '-c:a aac -b:a 128k -ar 44100 -ac 2 '
              '-pix_fmt yuv420p '
              "-vf \"$scaleFilter\" "
              '-shortest -y "$outputPath"';
        } else {
          print(
              '❌ Provided audioPath does not exist or is not accessible: $audioPath');
          // Video without audio
          command = '-framerate $fps -i "$framePattern" '
              '-c:v libx264 -preset ultrafast -tune zerolatency '
              '-pix_fmt yuv420p '
              "-vf \"$scaleFilter\" "
              '-y "$outputPath"';
        }
      } else {
        // Video without audio
        command = '-framerate $fps -i "$framePattern" '
            '-c:v libx264 -preset ultrafast -tune zerolatency '
            '-pix_fmt yuv420p '
            "-vf \"$scaleFilter\" "
            '-y "$outputPath"';
      }

      print('📹 FFmpeg command: $command');

      // Execute FFmpeg
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final output = await session.getOutput();
      final logs = await session.getAllLogs();
      final failStackTrace = await session.getFailStackTrace();

      // Print full FFmpeg output and logs for debugging
      print('FFmpegKit output: $output');
      if (logs.isNotEmpty) {
        print('FFmpegKit logs:');
        for (final log in logs) {
          print(log.getMessage());
        }
      }
      if (failStackTrace != null) {
        print('FFmpegKit failStackTrace: $failStackTrace');
      }

      if (returnCode != null && returnCode.isValueSuccess()) {
        onProgress?.call(1.0);

        // Verify video was created
        if (await File(outputPath).exists()) {
          // Check if muxed video has audio stream using ffprobe
          final probeSession =
              await FFmpegKit.execute('-i "$outputPath" -hide_banner');
          final probeOutput = await probeSession.getOutput();
          print('ffprobe output: $probeOutput');
          if (audioPath != null && await File(audioPath).exists()) {
            if (probeOutput != null && probeOutput.contains('Audio:')) {
              print('✅ Muxed video has audio stream.');
              return outputPath;
            } else {
              print('❌ Muxed video has NO audio stream!');
            }
          } else {
            // No audio expected, just return
            return outputPath;
          }
        }
      } else {
        print('❌ FFmpeg failed: $output');
      }
    } catch (e) {
      print('❌ FFmpeg video creation error: $e');
    }

    return null;
  }

  /// Alternative: Create video using simpler approach (fallback)
  static Future<String?> _createVideoFallback({
    required List<String> framePaths,
    required String outputPath,
    required int fps,
    String? audioPath,
  }) async {
    // Create a simple video package with instructions
    final packageDir = Directory(outputPath.replaceAll('.mp4', '_package'));
    await packageDir.create(recursive: true);

    // Copy frames
    final framesDir = Directory(p.join(packageDir.path, 'frames'));
    await framesDir.create();

    for (int i = 0; i < framePaths.length; i++) {
      final frame = File(framePaths[i]);
      if (await frame.exists()) {
        await frame.copy(p.join(
            framesDir.path, 'frame_${i.toString().padLeft(6, '0')}.png'));
      }
    }

    // Copy audio if exists
    if (audioPath != null && await File(audioPath).exists()) {
      await File(audioPath).copy(p.join(packageDir.path, 'audio.mp3'));
    }

    // Create README with FFmpeg instructions
    final readme = '''
  VIDEO CREATION PACKAGE
  =====================
  Frames: ${framePaths.length}
  FPS: $fps
  Audio: ${audioPath != null ? 'Included (audio.mp3)' : 'Not included'}

  Create video with FFmpeg:
  ${audioPath != null ? 'ffmpeg -framerate $fps -i frames/frame_%06d.png -i audio.mp3 ' + '-c:v libx264 -c:a aac -pix_fmt yuv420p -shortest video.mp4' : 'ffmpeg -framerate $fps -i frames/frame_%06d.png ' + '-c:v libx264 -pix_fmt yuv420p video.mp4'}
  ''';

    await File(p.join(packageDir.path, 'README.txt')).writeAsString(readme);

    return packageDir.path;
  }

  /// Save video to device gallery
  static Future<bool> saveVideoToGallery(String videoPath) async {
    try {
      print('Attempting to save video to gallery. Path: $videoPath');
      final file = File(videoPath);
      final exists = await file.exists();
      print('File exists before saving: $exists');
      if (!exists) {
        print('❌ Video file does not exist: $videoPath');
        return false;
      }

      final result =
          await GallerySaver.saveVideo(videoPath, albumName: 'LED Scroller');
      print('GallerySaver result: $result');
      if (result != true) {
        print('❌ GallerySaver failed to save the video.');
      }
      return result == true;
    } catch (e, stack) {
      print('❌ Error saving to gallery: $e');
      print('Stack trace: $stack');
      return false;
    }
  }

  /// Share video with progress indicator
  static Future<void> shareVideo(String videoPath,
      {String? title, BuildContext? context, String? audioPath}) async {
    try {
      if (!await File(videoPath).exists()) {
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video file not found')));
        }
        return;
      }

      // If audioPath is provided, always re-mux video with audio before sharing
      String videoToShare = videoPath;
      if (audioPath != null && await File(audioPath).exists()) {
        try {
          print('🔊 Provided audioPath: $audioPath');
          final Directory tempDir = await getTemporaryDirectory();
          final String newVideoPath = p.join(tempDir.path,
              'shared_led_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
          String command =
              '-i "$videoPath" -an -i "$audioPath" -c:v copy -c:a aac -ar 44100 -ac 2 -shortest -y "$newVideoPath"';
          print('🔊 Muxing audio for share: $command');
          final session = await FFmpegKit.execute(command);
          final returnCode = await session.getReturnCode();
          final output = await session.getOutput();
          final logs = await session.getAllLogs();
          final failStackTrace = await session.getFailStackTrace();
          print('FFmpegKit output: $output');
          if (logs.isNotEmpty) {
            print('FFmpegKit logs:');
            for (final log in logs) {
              print(log.getMessage());
            }
          }
          if (failStackTrace != null) {
            print('FFmpegKit failStackTrace: $failStackTrace');
          }
          if (returnCode != null &&
              returnCode.isValueSuccess() &&
              await File(newVideoPath).exists()) {
            print('✅ Audio muxed successfully for sharing.');
            // Check if muxed video has audio stream using ffprobe
            final probeSession =
                await FFmpegKit.execute('-i "$newVideoPath" -hide_banner');
            final probeOutput = await probeSession.getOutput();
            print('ffprobe output: $probeOutput');
            if (probeOutput != null && probeOutput.contains('Audio:')) {
              videoToShare = newVideoPath;
            } else {
              print('❌ Muxed video has no audio stream!');
              if (context != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Muxed video has no audio stream!')),
                );
              }
            }
          } else {
            print('❌ Audio muxing failed: $output');
            if (context != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to add audio to video.')),
              );
            }
          }
        } catch (e) {
          print('❌ Exception during audio muxing: $e');
          if (context != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error adding audio: $e')),
            );
          }
        }
      } else if (audioPath != null) {
        print('❌ Provided audioPath does not exist: $audioPath');
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Audio file not found: $audioPath')),
          );
        }
      }
      final file = XFile(videoToShare, mimeType: 'video/mp4');

      if (context != null && context.mounted) {
        // Show sharing dialog
        showModalBottomSheet(
          context: context,
          builder: (ctx) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Share Video'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    // Save to gallery before sharing
                    final saved = await saveVideoToGallery(videoToShare);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(saved
                              ? 'Video saved to gallery!'
                              : 'Failed to save video before sharing')));
                    }
                    await Share.shareXFiles(
                      [file],
                      subject: title ?? 'My LED Video',
                      text: 'Check out this LED video I created!',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.save),
                  title: const Text('Save to Gallery'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final saved = await saveVideoToGallery(videoToShare);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(saved
                              ? 'Video saved to gallery!'
                              : 'Failed to save video')));
                    }
                  },
                ),
              ],
            );
          },
        );
      } else {
        // Save to gallery before direct share
        await saveVideoToGallery(videoToShare);
        await Share.shareXFiles(
          [file],
          subject: title ?? 'My LED Video',
          text: 'Check out this LED video I created!',
        );
      }
    } catch (e) {
      print('❌ Error sharing video: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error sharing: $e')));
      }
    }
  }

  /// Stub for getVideoInfo to fix build errors. Replace with real implementation as needed.
  static Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    throw UnimplementedError('getVideoInfo is not implemented.');
  }
}
