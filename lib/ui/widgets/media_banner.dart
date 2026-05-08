import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:video_player/video_player.dart';
import '../../core/models/models.dart';

class MediaBanner extends StatefulWidget {
  final PromotionBanner ad;
  final VoidCallback? onVideoEnd;
  final bool isActive;

  const MediaBanner({
    super.key,
    required this.ad,
    this.onVideoEnd,
    this.isActive = false,
  });

  @override
  State<MediaBanner> createState() => _MediaBannerState();
}

class _MediaBannerState extends State<MediaBanner> {
  CachedVideoPlayerPlus? _player;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.ad.isVideo) {
      _initVideo();
    }
  }

  @override
  void didUpdateWidget(MediaBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ad.imageUrl != oldWidget.ad.imageUrl) {
      _disposeVideo();
      _hasNotifiedEnd = false;
      if (widget.ad.isVideo) {
        _initVideo();
      }
    } else if (widget.ad.isVideo && _initialized) {
      if (widget.isActive) {
        if (_hasNotifiedEnd) {
          _hasNotifiedEnd = false;
          _player?.controller.seekTo(Duration.zero);
        }
        _player?.controller.play();
      } else {
        _player?.controller.pause();
      }
    }
  }

  void _disposeVideo() {
    _player?.controller.removeListener(_videoListener);
    _player?.dispose();
    _player = null;
    _initialized = false;
  }

  Future<void> _initVideo() async {
    if (widget.ad.imageUrl.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    try {
      final uri = Uri.tryParse(widget.ad.imageUrl);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        debugPrint("[MediaBanner] Invalid URI: ${widget.ad.imageUrl}");
        if (mounted) setState(() => _hasError = true);
        return;
      }

      _player = CachedVideoPlayerPlus.networkUrl(uri);
      await _player!.initialize();

      _player!.controller.addListener(_videoListener);
      
      if (mounted) {
        setState(() {
          _initialized = true;
          _player!.controller.setLooping(false); 
          _player!.controller.setVolume(1.0); 
          if (widget.isActive) {
            _player!.controller.play();
          }
        });
      }
    } catch (e) {
      if (!Platform.isWindows) {
        debugPrint("[MediaBanner] Error initializing video player: $e");
      }
      if (mounted) {
        setState(() => _hasError = true);
        if (widget.isActive) {
           _triggerEndWithDelay(delaySeconds: 1);
        }
      }
    }
  }


  void _triggerEndWithDelay({int delaySeconds = 2}) {
    Future.delayed(Duration(seconds: delaySeconds), () {
      if (mounted && widget.isActive) {
        debugPrint("[MediaBanner] Auto-skipping video banner (Reason: ${Platform.isWindows ? 'Windows Env' : 'Load Error'})");
        widget.onVideoEnd?.call();
      }
    });
  }



  bool _hasNotifiedEnd = false;

  void _videoListener() {
    if (_player == null || !mounted || _hasNotifiedEnd) return;
    
    final value = _player!.controller.value;
    if (!value.isInitialized) return;

    final position = value.position;
    final duration = value.duration;
    
    if (duration == Duration.zero) return;

    // Check if video reached the end (with a 500ms buffer for safety)
    bool isNearEnd = position >= duration - const Duration(milliseconds: 500);
    
    // Also check if it's paused and very near the end (some players stop early)
    bool isPausedAtEnd = !value.isPlaying && position >= duration - const Duration(milliseconds: 1000);

    if (isNearEnd || isPausedAtEnd) {
      debugPrint("[MediaBanner] Video progress: pos=$position, dur=$duration, isPlaying=${value.isPlaying} -> TRIGGERING END");
      _hasNotifiedEnd = true;
      widget.onVideoEnd?.call();
    } else {
      // Periodic log to trace progress
      if (position.inSeconds % 2 == 0) {
        debugPrint("[MediaBanner] Video progress: pos=$position / dur=$duration");
      }
    }
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ad.isVideo) {
      if (_hasError) {
        // Safe fallback for broken video on platforms like Windows
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [Colors.grey[800]!, Colors.grey[900]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_library_outlined, color: Colors.white54, size: 40),
                const SizedBox(height: 8),
                Text(
                  "عرض ترويجي",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.black,
        ),
        clipBehavior: Clip.antiAlias,
        child: _initialized
            ? FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: _player!.controller.value.size.width,
                  height: _player!.controller.value.size.height,
                  child: VideoPlayer(_player!.controller),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
              ),
      );
    }

    // Default to Image for static banners
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(
          image: CachedNetworkImageProvider(widget.ad.imageUrl),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

}
