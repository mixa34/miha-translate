import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '/data.dart';
import '/simplytranslate.dart' as simplytranslate;

enum TtsState { idle, loading, playing }

/// Why a playback failed, which decides the message shown to the user.
enum TtsFailure { network, other }

/// Text-to-speech playback for one side of the translate screen.
///
/// There is one instance per side ([inputTts], [outputTts]) for the lifetime
/// of the app. Each owns its [AudioPlayer], created on first use, and a single
/// completion subscription; [dispose] releases both. Widgets only listen to
/// [state], so no playback callback ever reaches a disposed widget.
///
/// Every play and stop takes a new generation: an asynchronous step whose
/// generation is no longer current does nothing, so a cancelled or superseded
/// request can never start playing later.
class TtsPlayback {
  final state = ValueNotifier(TtsState.idle);

  AudioPlayer? _player;
  StreamSubscription<void>? _completion;
  int _generation = 0;

  @visibleForTesting
  String? get playerId => _player?.playerId;

  AudioPlayer get _audio {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _completion = player.onPlayerComplete.listen(
      (_) {
        if (state.value == TtsState.playing) state.value = TtsState.idle;
      },
      // Native player errors also arrive on this stream; play() reports
      // them, so they must not surface here as uncaught exceptions.
      onError: (Object _) {},
    );
    return _player = player;
  }

  /// Speaks [text] in [language], stopping the other side's voice first.
  ///
  /// [onError] is called if fetching or playing the audio fails, unless the
  /// playback was stopped or superseded in the meantime.
  Future<void> play(String text, String language, {required void Function(TtsFailure failure) onError}) async {
    for (final playback in [inputTts, outputTts]) {
      playback.stop();
    }
    final generation = ++_generation;
    state.value = TtsState.loading;

    final Uint8List bytes;
    try {
      bytes = await simplytranslate.tts(text, language);
    } catch (error) {
      final network = error is TimeoutException || error is SocketException || error is http.ClientException;
      _fail(generation, network ? TtsFailure.network : TtsFailure.other, onError);
      return;
    }
    if (generation != _generation) return;

    try {
      final player = _audio;
      await player.setSourceBytes(bytes);
      if (generation != _generation) return;
      state.value = TtsState.playing;
      await player.resume();
    } catch (error) {
      if (generation == _generation) _stopPlayer();
      _fail(generation, TtsFailure.other, onError);
    }
  }

  void _fail(int generation, TtsFailure failure, void Function(TtsFailure failure) onError) {
    if (generation != _generation) return;
    state.value = TtsState.idle;
    onError(failure);
  }

  /// Cancels a pending request and stops any audio at once.
  void stop() {
    _generation++;
    if (state.value == TtsState.playing) _stopPlayer();
    state.value = TtsState.idle;
  }

  void _stopPlayer() {
    final player = _player;
    if (player != null) unawaited(player.stop().catchError((Object _) {}));
  }

  /// Stops playback and releases the audio player. A later [play] creates a
  /// new one. Never completes with an error: it runs while the app shuts down,
  /// unawaited, and a native release failure must not become an unhandled
  /// exception.
  Future<void> dispose() async {
    stop();
    final player = _player;
    final completion = _completion;
    _player = null;
    _completion = null;
    try {
      await Future.wait([
        if (completion != null) completion.cancel(),
        if (player != null) player.dispose(),
      ]);
    } catch (_) {
      // The native player could not be released; nothing else can be done.
    }
  }
}

final inputTts = TtsPlayback();
final outputTts = TtsPlayback();

/// Stops both voices. Used whenever the text or languages they would speak
/// change: editing, Clear, Swap, language changes and shared text.
void stopAllTts() {
  inputTts.stop();
  outputTts.stop();
}

/// Releases both audio players; called when the app's root widget is disposed.
Future<void> disposeTts() => Future.wait([inputTts.dispose(), outputTts.dispose()]);

/// The speaker button shared by the input and the output.
///
/// [language] is read only when the button is pressed, so it always reflects
/// the current selection; null then means nothing is spoken. [available] false
/// disables the button. [listenLabel] names what it speaks; while loading or
/// playing, pressing it stops, and its tooltip says so.
class TtsButton extends StatelessWidget {
  final TtsPlayback playback;
  final String text;
  final String? Function() language;
  final bool available;
  final String listenLabel;

  const TtsButton({
    required this.playback,
    required this.text,
    required this.language,
    required this.listenLabel,
    this.available = true,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TtsState>(
      valueListenable: playback.state,
      builder: (context, state, _) {
        if (state == TtsState.loading) {
          // Pressing it stops, as while playing.
          return Tooltip(
            message: i18n().main.stop_audio,
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: playback.stop,
                child: Container(
                  height: 48,
                  width: 48,
                  alignment: Alignment.center,
                  child: Container(
                    alignment: Alignment.center,
                    height: 24,
                    width: 24,
                    child: const CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ),
            ),
          );
        }
        final playing = state == TtsState.playing;
        return IconButton(
          tooltip: playing ? i18n().main.stop_audio : listenLabel,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onPressed: () {
            if (playing) return playback.stop;
            if (text.isEmpty || !available) return null;
            if (text.length > 200) return () => _audioLimit(context);
            return () {
              final lang = language();
              if (lang != null) playback.play(text, lang, onError: (failure) => _showError(context, failure));
            };
          }(),
          icon: Icon(
            playing ? Icons.stop : Icons.volume_up,
            color: text.length > 200 && !playing ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38) : null,
          ),
        );
      },
    );
  }
}

bool _isSnackBarPressed = false;

void _audioLimit(BuildContext context) {
  if (!_isSnackBarPressed) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(seconds: 2),
        width: 300,
        content: Text(i18n().main.audio_limit, textAlign: TextAlign.center),
      ),
    );
    _isSnackBarPressed = true;
    Future.delayed(const Duration(seconds: 1)).then((_) => _isSnackBarPressed = false);
  }
}

void _showError(BuildContext context, TtsFailure failure) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: Duration(seconds: 2),
      width: 300,
      content: Text(
        failure == TtsFailure.network ? i18n().main.no_internet : i18n().main.something_went_wrong,
        textAlign: TextAlign.center,
      ),
    ),
  );
}
