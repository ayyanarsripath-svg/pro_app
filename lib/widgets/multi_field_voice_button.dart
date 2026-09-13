import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/theme/app_theme.dart';

/// One mic button that fills MULTIPLE fields at once from a single spoken
/// sentence (spec: "ella feild laium inside bar la oru mic subole vachi
/// atha touch panni name quantity purchase amount sales amount thirishould
/// ethu ellam voice command la sonna athu text ah fill pannikkum" - typing
/// every field by hand for a new product is slow; speak the whole thing
/// once and let it fill Name/Quantity/Purchase Amount/Selling Amount/
/// Threshold on its own).
///
/// Distinct from the existing per-field mic buttons elsewhere in this app
/// (DailyOrderScreen's `_DialogMicButton`, QuickTransactionScreen's own
/// mic), which each fill exactly ONE field verbatim - this one listens
/// once and hands the FULL heard sentence to [onHeard] for the caller to
/// parse into as many fields as it can recognize (spec: "ethula extra
/// ethana add pannaumna ethapathina full details analysis panni add
/// pannikka" - analyze whatever was said and fill in whatever applies,
/// don't require one exact fixed phrasing). See VoiceProductParser for the
/// actual parsing.
///
/// Reuses the exact same `speech_to_text` plugin (and RECORD_AUDIO
/// permission, already declared in build-apk.yml for the other two mic
/// buttons) as the rest of the app - no new dependency or permission
/// needed.
class MultiFieldVoiceButton extends StatefulWidget {
  final void Function(String heardText) onHeard;

  const MultiFieldVoiceButton({super.key, required this.onHeard});

  @override
  State<MultiFieldVoiceButton> createState() => _MultiFieldVoiceButtonState();
}

class _MultiFieldVoiceButtonState extends State<MultiFieldVoiceButton> {
  final _speech = stt.SpeechToText();
  bool _listening = false;

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    // Lazily initialized on first tap (not in initState) so the phone's
    // microphone-permission prompt only fires when the shop actually wants
    // to use it, same pattern already used by the app's other mic buttons.
    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mic not available - check microphone permission in phone Settings.')),
        );
      }
      return;
    }
    if (mounted) setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          widget.onHeard(result.recognizedWords.trim());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _listening
          ? 'Listening... tap to stop'
          : 'Speak product details - name, quantity, purchase & selling price',
      icon: Icon(
        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: _listening ? AppColors.danger : null,
      ),
      onPressed: _toggle,
    );
  }
}
