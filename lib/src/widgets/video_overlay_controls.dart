import 'dart:async';
import 'package:flutter/material.dart';
import 'package:omni_video_player/src/widgets/auto_hide_controls_manager.dart';
import 'package:omni_video_player/src/widgets/auto_hide_play_pause_button.dart';
import 'package:omni_video_player/src/widgets/bottom_control_bar/gradient_bottom_control_bar.dart';
import 'package:omni_video_player/src/widgets/bottom_control_bar/video_playback_control_bar.dart';
import 'package:omni_video_player/omni_video_player/controllers/omni_playback_controller.dart';
import 'package:omni_video_player/omni_video_player/models/video_player_callbacks.dart';
import 'package:omni_video_player/omni_video_player/models/video_player_configuration.dart';

import 'indicators/animated_skip_indicator.dart';
import 'indicators/loader_indicator.dart';

class VideoOverlayControls extends StatefulWidget {
  const VideoOverlayControls({
    super.key,
    required this.child,
    required this.controller,
    this.playerBarPadding = const EdgeInsets.only(right: 8, left: 8, top: 16),
    required this.options,
    required this.callbacks,
  });

  final OmniPlaybackController controller;
  final Widget child;
  final VideoPlayerConfiguration options;
  final VideoPlayerCallbacks callbacks;
  final EdgeInsets playerBarPadding;

  @override
  State<VideoOverlayControls> createState() => _VideoOverlayControlsState();
}

class _VideoOverlayControlsState extends State<VideoOverlayControls>
    with SingleTickerProviderStateMixin {
  SkipDirection? _skipDirection;
  int _skipSeconds = 0;
  late final AnimationController _animationController;
  _TapInteractionState _tapState = _TapInteractionState.idle;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          setState(() {
            _skipDirection = null;
            _tapState = _TapInteractionState.idle;
          });
        }
      }
    });
  }

  /// Shows skip indicator & performs the seek with a short delay.
  Future<void> _triggerSkip(
      SkipDirection direction, int skipSeconds, Duration targetPosition) async {
    // Show skip indicator immediately
    _showSkip(direction, skipSeconds);

    // Delay to let animation show before seeking
    await Future.delayed(const Duration(milliseconds: 250));

    // Check buffering for next 3 seconds before applying seek
    if (_isBuffered(targetPosition, const Duration(seconds: 1))) {
      widget.controller.seekTo(targetPosition);
    } else {
      debugPrint("⚠️ Skip cancelled: not enough buffered video ahead.");
    }
  }

  /// Check if the given [target] + [bufferMargin] is within buffered ranges.
  bool _isBuffered(Duration target, Duration bufferMargin) {
    final ranges = widget.controller.buffered;
    for (final range in ranges) {
      if (target >= range.start &&
          target + bufferMargin <= range.end) {
        return true;
      }
    }
    return false;
  }

  void _showSkip(SkipDirection direction, int skipSeconds) {
    setState(() {
      _skipDirection = direction;
      _skipSeconds = skipSeconds;
      _tapState = direction == SkipDirection.forward
          ? _TapInteractionState.doubleTapForward
          : _TapInteractionState.doubleTapBackward;
    });

    if (_animationController.isAnimating) {
      _animationController.stop();
    }
    _animationController.reset();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, __) {
        return AutoHideControlsManager(
          controller: widget.controller,
          options: widget.options,
          callbacks: widget.callbacks,
          builder: (context, areControlsVisible, toggleVisibility) {
            bool areOverlayControlsVisible =
                (widget.controller.isPlaying || widget.controller.isSeeking) &&
                    widget.options.playerUIVisibilityOptions
                        .showVideoBottomControlsBar &&
                    areControlsVisible &&
                    _tapState != _TapInteractionState.doubleTapForward &&
                    _tapState != _TapInteractionState.doubleTapBackward;

            bool isVisibleButton = widget.controller.isFinished ||
                (areControlsVisible &&
                    !widget.controller.isBuffering &&
                    !widget.controller.isSeeking &&
                    widget.controller.isReady &&
                    !(widget.controller.isFinished &&
                        !widget.options.playerUIVisibilityOptions
                            .showReplayButton) &&
                    _tapState != _TapInteractionState.doubleTapForward &&
                    _tapState != _TapInteractionState.doubleTapBackward);

            widget.callbacks.onCenterControlsVisibilityChanged
                ?.call(isVisibleButton);
            widget.callbacks.onOverlayControlsVisibilityChanged?.call(
              areOverlayControlsVisible,
            );

            List<Widget> layers = [
              widget.child,
              Container(color: Colors.transparent, width: double.infinity, height: double.infinity),

              // Tap zones
              Positioned.fill(
                child: Row(
                  children: [
                    // Rewind
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () {
                          if (!widget.options.playerUIVisibilityOptions.enableBackwardGesture ||
                              widget.controller.isFinished ||
                              !widget.controller.hasStarted) {
                            return;
                          }
                          const skipSeconds = 5;
                          final currentPosition = widget.controller.currentPosition;
                          final target = currentPosition - const Duration(seconds: skipSeconds);

                          if (target < Duration.zero) return;

                          _triggerSkip(SkipDirection.backward, skipSeconds, target);
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),

                    // Forward
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () {
                          if (!widget.options.playerUIVisibilityOptions.enableForwardGesture ||
                              widget.controller.isFinished ||
                              !widget.controller.hasStarted) {
                            return;
                          }
                          const skipSeconds = 5;
                          final currentPosition = widget.controller.currentPosition;
                          final target = currentPosition + const Duration(seconds: skipSeconds);

                          if (target > widget.controller.duration) return;

                          _triggerSkip(SkipDirection.forward, skipSeconds, target);
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),

              // Skip indicator
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: _skipDirection != null &&
                    (_tapState == _TapInteractionState.doubleTapForward ||
                        _tapState == _TapInteractionState.doubleTapBackward)
                    ? AnimatedSkipIndicator(
                  skipDirection: _skipDirection!,
                  skipSeconds: _skipSeconds,
                )
                    : const SizedBox.shrink(),
              ),

              // Bottom bar
              GradientBottomControlBar(
                isVisible: areOverlayControlsVisible,
                padding: widget.playerBarPadding,
                useSafeAreaForBottomControls:
                widget.options.playerUIVisibilityOptions.useSafeAreaForBottomControls,
                showGradientBottomControl:
                widget.options.playerUIVisibilityOptions.showGradientBottomControl,
                child: widget.options.customPlayerWidgets.bottomControlsBar ??
                    VideoPlaybackControlBar(
                      controller: widget.controller,
                      options: widget.options,
                      callbacks: widget.callbacks,
                    ),
              ),

              if (widget.controller.isSeeking) LoaderIndicator(),

              AutoHidePlayPauseButton(
                isVisible: isVisibleButton,
                controller: widget.controller,
                options: widget.options,
                callbacks: widget.callbacks,
              ),
            ];

            return GestureDetector(
              onTap: () {
                setState(() => _tapState = _TapInteractionState.singleTap);
                toggleVisibility();
              },
              onDoubleTap: () {
                setState(() => _tapState = _TapInteractionState.idle);
                toggleVisibility();
              },
              onVerticalDragUpdate: (details) {
                if (!widget.options.playerUIVisibilityOptions.enableExitFullscreenOnVerticalSwipe) {
                  return;
                }
                if (details.primaryDelta != null && details.primaryDelta! > 10) {
                  if (widget.controller.isFullScreen) {
                    widget.controller.switchFullScreenMode(
                      context,
                      pageBuilder: null,
                      onToggle: widget.callbacks.onFullScreenToggled,
                    );
                  }
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Stack(children: layers),
            );
          },
        );
      },
    );
  }
}

enum _TapInteractionState {
  idle,
  singleTap,
  doubleTapForward,
  doubleTapBackward,
}
