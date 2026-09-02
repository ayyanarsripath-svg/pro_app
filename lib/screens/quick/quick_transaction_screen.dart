import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
// BUILD FIX (2026-09): SpeechRecognitionResult (the type _onSpeechResult
// takes) lives in this separate library, not re-exported by
// speech_to_text.dart itself - importing only the main library left
// `stt.SpeechRecognitionResult` unresolved and failed CI's release build
// ("Error: Type 'stt.SpeechRecognitionResult' not found"). Same `stt`
// prefix as above so both merge into one namespace.
import 'package:speech_to_text/speech_recognition_result.dart' as stt;

import '../../core/repositories/quick_transaction_repository.dart';
import '../../core/services/quick_notification_service.dart';
import '../../core/theme/app_theme.dart';

/// Fast Income/Expense entry (spec: "PRO SERVICE – Quick Income & Expense
/// Entry Feature", items 2 & 3 - "Minimum interaction-ல் transaction save
/// ஆக வேண்டும்"). Reached today from the Dashboard's Quick Income/Quick
/// Expense buttons. The persistent notification, home-screen widget, Quick
/// Settings tile and voice-entry pieces described in the same spec are
/// separate native-Android follow-ups; once built, each of them opens this
/// exact screen (or calls QuickTransactionRepository directly for the
/// notification's own inline buttons) - the save logic here does not
/// change when those arrive, only how this screen gets reached.
class QuickTransactionScreen extends StatefulWidget {
  final bool startAsExpense;

  /// Set only when this screen is the ROOT of its own standalone
  /// Activity/engine - the Quick Income/Expense notification's ➕ Income /
  /// ➖ Expense buttons (see QuickIncomeActivity/QuickExpenseActivity and
  /// quickIncomeMain/quickExpenseMain in main.dart). There is no previous
  /// route to pop back to in that case - Navigator.pop() on the app's only
  /// route is a silent no-op - so this closes the whole standalone task
  /// instead (same "finish back to the home screen" behaviour as the Daily
  /// Orders widget's QuickAddOrderScreen). Left null for the normal in-app
  /// path (Dashboard's own Quick Income/Quick Expense buttons), which keeps
  /// popping back to Dashboard exactly as before.
  final VoidCallback? onClose;

  const QuickTransactionScreen({super.key, this.startAsExpense = false, this.onClose});

  @override
  State<QuickTransactionScreen> createState() => _QuickTransactionScreenState();
}

class _QuickTransactionScreenState extends State<QuickTransactionScreen> {
  final _repo = QuickTransactionRepository();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  late bool _isExpense;
  late String _category;
  bool _saving = false;
  int _savedCount = 0;

  // Mic entry (spec: "adikkadi type panni text enter panna mudiyathu so
  // mic touch panni petrol 50 rupees nu sonna enakku expenses la petrol
  // add pannittu 50 ah amount la add pannanum" - speaking an entry instead
  // of typing the amount and a note every single time). _speech is
  // created fresh per screen (not a shared singleton) since this is the
  // only screen that uses it - no need for app-wide plumbing.
  final _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _isExpense = widget.startAsExpense;
    _category = _categories.first;
  }

  List<String> get _categories =>
      _isExpense ? QuickTransactionCategory.expenseCategories : QuickTransactionCategory.incomeCategories;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _amountFocus.dispose();
    _speech.stop();
    super.dispose();
  }

  /// Starts (or, if already listening, stops) voice entry. Lazily
  /// initializes speech_to_text on first tap rather than in initState, so
  /// opening this screen never itself triggers the RECORD_AUDIO permission
  /// prompt - only actually tapping the mic does, same as every other
  /// permission in this app being asked for only when the shop uses the
  /// feature that needs it.
  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!_speechAvailable) {
      final ok = await _speech.initialize(
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
        onStatus: (status) {
          // Covers the recognizer stopping itself after a pause in speech
          // (the normal end of a successful entry), not just an explicit
          // stop tap - otherwise the mic icon would stay stuck in its
          // "listening" state after the shop finished speaking.
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = ok);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mic not available - check microphone permission in phone Settings'),
        ));
        return;
      }
    }

    setState(() => _listening = true);
    await _speech.listen(onResult: _onSpeechResult);
  }

  /// Fills Amount + Note from what was heard. Only the AMOUNT is parsed out
  /// with any confidence (the first plain number in the phrase, e.g. "50"
  /// in "petrol 50 rupees") - matching text against this app's fixed
  /// Category list by voice would be guesswork risking the wrong category
  /// getting silently picked, so the full heard phrase (with that number
  /// and a trailing "rupees"/"rs" removed) goes into Note instead, e.g.
  /// "petrol" - visible and editable, and the shop still picks the right
  /// Category with one tap same as always.
  void _onSpeechResult(stt.SpeechRecognitionResult result) {
    final heard = result.recognizedWords.trim();
    if (heard.isEmpty) return;

    final numberMatch = RegExp(r'\d+(\.\d+)?').firstMatch(heard);
    var description = heard;
    if (numberMatch != null) {
      _amountCtrl.text = numberMatch.group(0)!;
      description = (heard.substring(0, numberMatch.start) + heard.substring(numberMatch.end)).trim();
    }
    // Strip a trailing/leading currency word left over once the number
    // itself is removed (e.g. "petrol  rupees" -> "petrol").
    description = description.replaceAll(RegExp(r'\b(rupees?|rs\.?)\b', caseSensitive: false), '').trim();
    if (description.isNotEmpty) _noteCtrl.text = description;

    if (result.finalResult && mounted) setState(() {});
  }

  Future<void> _save({bool addAnother = false}) async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount')));
      return;
    }
    setState(() => _saving = true);
    try {
      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      if (_isExpense) {
        await _repo.recordExpense(amount: amount, category: _category, note: note);
      } else {
        await _repo.recordIncome(amount: amount, category: _category, note: note);
      }
      if (!mounted) return;
      _savedCount++;
      // Keeps the persistent notification's own "Today - Income: ...
      // Expense: ..." body in sync the instant a save happens here too -
      // not just when saved directly from the notification's own action
      // buttons (see QuickNotificationService's "notification auto-update"
      // doc comment). Fire-and-forget: never worth blocking this screen's
      // own save flow on a notification refresh.
      QuickNotificationService.show();
      if (addAnother) {
        _amountCtrl.clear();
        _noteCtrl.clear();
        setState(() => _saving = false);
        // Cursor back to Amount so the next entry can be typed straight
        // away, same "no extra tap" convenience as Quick Add Order.
        FocusScope.of(context).requestFocus(_amountFocus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_isExpense ? 'Expense' : 'Income'} of ₹${amount.toStringAsFixed(0)} saved')),
        );
      } else if (widget.onClose != null) {
        // Standalone (notification) entry point - see [QuickTransactionScreen.onClose].
        widget.onClose!();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _isExpense ? AppColors.danger : AppColors.success;
    final standalone = widget.onClose != null;
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(_savedCount == 0
            ? (_isExpense ? 'Quick Expense' : 'Quick Income')
            : '${_isExpense ? 'Quick Expense' : 'Quick Income'} ($_savedCount saved)'),
        // Standalone (notification) launch is this Navigator's only/root
        // route, so Flutter never draws its own automatic back arrow here -
        // this is the only way to close it without saving anything, same
        // as QuickAddOrderScreen's own close icon.
        leading: standalone ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: widget.onClose) : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Income/Expense toggle - switching resets the category to
              // the new list's first entry so a stale Expense category
              // (e.g. "Shop Rent") can never get silently saved as Income,
              // or vice versa.
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Income'), icon: Icon(Icons.add_circle_outline_rounded)),
                  ButtonSegment(value: true, label: Text('Expense'), icon: Icon(Icons.remove_circle_outline_rounded)),
                ],
                selected: {_isExpense},
                onSelectionChanged: (s) => setState(() {
                  _isExpense = s.first;
                  _category = _categories.first;
                }),
              ),
              const SizedBox(height: 14),
              // Voice entry (spec: speak instead of typing - "petrol 50
              // rupees" fills Amount with 50 and Note with "petrol" below).
              // Centered and full-width so it reads as an alternative way
              // to fill the form below, not a minor extra button.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _toggleListening,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _listening ? color : null,
                    side: _listening ? BorderSide(color: color, width: 2) : null,
                  ),
                  icon: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded),
                  label: Text(_listening ? 'Listening... (tap to stop)' : 'Speak an entry (e.g. "petrol 50 rupees")'),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _amountCtrl,
                focusNode: _amountFocus,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
                decoration: const InputDecoration(labelText: 'Amount (₹) *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _noteCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
                  onPressed: _saving ? null : () => _save(),
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: const Text('Save & Close'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save(addAnother: true),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Save & Add Another'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!standalone) return scaffold;

    // Standalone (notification) launch has no previous route for the
    // device back button/gesture to reveal either - without this, it would
    // be silently swallowed (a no-op) the same way Navigator.pop() is in
    // _save() above. Same PopScope pattern as QuickAddOrderScreen.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose!();
      },
      child: scaffold,
    );
  }
}
