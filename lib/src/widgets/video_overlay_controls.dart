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

/// A widget that overlays video playback controls on top of a video display.
///
/// - Manages visibility of playback controls (auto-hide after timeout).
/// - Shows play/pause, bottom control bar, skip indicators.
/// - Handles gestures (tap, double-tap forward/backward, vertical drag).
/// - Uses [AnimationController] to animate skip indicator with fade-out.
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
  /// Indicates skip direction (forward / backward). Null when no skip indicator.
  SkipDirection? _skipDirection;

  /// Number of seconds skipped (default 5s).
  int _skipSeconds = 0;

  /// Controls skip indicator animation (fade-out).
  late final AnimationController _animationController;

  /// Current user interaction state (tap / double-tap).
  _TapInteractionState _tapState = _TapInteractionState.idle;

  @override
  void initState() {
    super.initState();

    // Initializes the animation controller for the skip indicator.
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )
    // Add status listener instead of .then to avoid multiple setStates.
      ..addStatusListener((status) {
        // When animation finishes → reset skip state.
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

  /// Triggers skip indicator animation with given [direction] and [skipSeconds].
  void _showSkip(SkipDirection direction, int skipSeconds) {
    // Update state to show skip indicator.
    setState(() {
      _skipDirection = direction;
      _skipSeconds = skipSeconds;
      _tapState = direction == SkipDirection.forward
          ? _TapInteractionState.doubleTapForward
          : _TapInteractionState.doubleTapBackward;
    });

    // If animation already running → stop it to avoid stacking animations.
    if (_animationController.isAnimating) {
      _animationController.stop();
    }

    // Restart the animation for new skip.
    _animationController.reset();
    _animationController.forward();
  }

  @override
  void dispose() {
    // Dispose animation controller to free resources.
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
            // Determine when bottom overlay controls should be visible.
            bool areOverlayControlsVisible =
                (widget.controller.isPlaying || widget.controller.isSeeking) &&
                    widget.options.playerUIVisibilityOptions
                        .showVideoBottomControlsBar &&
                    areControlsVisible &&
                    _tapState != _TapInteractionState.doubleTapForward &&
                    _tapState != _TapInteractionState.doubleTapBackward;

            // Determine visibility of central play/pause button.
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

            // Fire visibility callbacks for external listeners.
            widget.callbacks.onCenterControlsVisibilityChanged
                ?.call(isVisibleButton);
            widget.callbacks.onOverlayControlsVisibilityChanged?.call(
              areOverlayControlsVisible,
            );

            // Stack layers for overlay controls.
            List<Widget> layers = [
              widget.child,

              // Transparent layer to ensure tap detection (esp. on webviews).
              Container(
                color: Colors.transparent,
                width: double.infinity,
                height: double.infinity,
              ),

              // Tap zones for double-tap rewind/forward.
              Positioned.fill(
                child: Row(
                  children: [
                    // Left side: rewind
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () {
                          if (!widget.options.playerUIVisibilityOptions
                              .enableBackwardGesture ||
                              widget.controller.isFinished ||
                              !widget.controller.hasStarted) {
                            return;
                          }
                          int skipSeconds = 5;

                          final currentPosition =
                              widget.controller.currentPosition;
                          final targetPosition =
                              currentPosition - Duration(seconds: skipSeconds);

                          if (targetPosition < Duration.zero) return;

                          widget.controller.seekTo(
                            targetPosition > Duration.zero
                                ? targetPosition
                                : Duration.zero,
                          );
                          _showSkip(SkipDirection.backward, skipSeconds);
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),

                    // Right side: forward
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () {
                          if (!widget.options.playerUIVisibilityOptions
                              .enableForwardGesture ||
                              widget.controller.isFinished ||
                              !widget.controller.hasStarted) {
                            return;
                          }
                          int skipSeconds = 5;

                          final currentPosition =
                              widget.controller.currentPosition;
                          final targetPosition =
                              currentPosition + Duration(seconds: skipSeconds);

                          if (targetPosition > widget.controller.duration) {
                            return;
                          }

                          widget.controller.seekTo(targetPosition);
                          _showSkip(SkipDirection.forward, skipSeconds);
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),

              // Skip indicator (fade out animation).
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

              // Bottom gradient bar with playback controls.
              GradientBottomControlBar(
                isVisible: areOverlayControlsVisible,
                padding: widget.playerBarPadding,
                useSafeAreaForBottomControls: widget.options
                    .playerUIVisibilityOptions.useSafeAreaForBottomControls,
                showGradientBottomControl: widget.options
                    .playerUIVisibilityOptions.showGradientBottomControl,
                child: widget.options.customPlayerWidgets.bottomControlsBar ??
                    VideoPlaybackControlBar(
                      controller: widget.controller,
                      options: widget.options,
                      callbacks: widget.callbacks,
                    ),
              ),

              // Show loader while seeking.
              if (widget.controller.isSeeking) LoaderIndicator(),

              // Central play/pause button (auto-hide logic).
              AutoHidePlayPauseButton(
                isVisible: isVisibleButton,
                controller: widget.controller,
                options: widget.options,
                callbacks: widget.callbacks,
              ),
            ];

            // Insert custom overlays if provided in configuration.
            for (final customOverlay
            in widget.options.customPlayerWidgets.customOverlayLayers) {
              if (customOverlay.ignoreOverlayControlsVisibility ||
                  areOverlayControlsVisible) {
                final rotation = widget.controller.rotationCorrection;
                final size = widget.controller.size;

                final aspectRatio = (rotation == 90 || rotation == 270)
                    ? size.height / size.width
                    : size.width / size.height;

                layers.insert(
                  customOverlay.level,
                  Center(
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: customOverlay.widget,
                    ),
                  ),
                );
              }
            }

            // Gesture handling for whole overlay.
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
                if (!widget.options.playerUIVisibilityOptions
                    .enableExitFullscreenOnVerticalSwipe) {
                  return;
                }
                // Exit fullscreen if drag downwards significantly.
                if (details.primaryDelta != null &&
                    details.primaryDelta! > 10) {
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
              child: Stack(
                children: layers,
              ),
            );
          },
        );
      },
    );
  }
}

/// Represents the type of user interaction detected via tap.
enum _TapInteractionState {
  idle,
  singleTap,
  doubleTapForward,
  doubleTapBackward,
}
