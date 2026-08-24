import 'package:flutter/material.dart';

import '../../core/repositories/reorder_repository.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/reorder_scheduler_service.dart';
import '../../core/services/whatsapp_file_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/reorder_task.dart';
import '../../widgets/section_card.dart';
import 'quick_order_screen.dart';

/// Lists every scheduled supplier order and is where a "due" order actually
/// gets sent - whether it became due because the reminder notification was
/// tapped, or because this screen's own catch-up check found one whose time
/// already passed (e.g. the OS alarm was missed - see
/// ReorderSchedulerService for why that safety net exists).
class ReorderListScreen extends StatefulWidget {
  const ReorderListScreen({super.key});

  @override
  State<ReorderListScreen> createState() => _ReorderListScreenState();
}

class _ReorderListScreenState extends State<ReorderListScreen> {
  final _repo = ReorderRepository();
  final _scheduler = ReorderSchedulerService();
  final _pdfService = PdfService();
  final _waService = WhatsAppFileService();

  List<ReorderTask> _tasks = [];
  bool _loading = true;
  final Set<String> _promptedIds = {};

  @override
  void initState() {
    super.initState();
    _scheduler.dueTaskId.addListener(_onDueTaskChanged);
    _init();
  }

  @override
  void dispose() {
    _scheduler.dueTaskId.removeListener(_onDueTaskChanged);
    super.dispose();
  }

  Future<void> _init() async {
    await _load();
    final due = await _scheduler.checkAndCollectDue();
    await _load();
    for (final t in due) {
      _maybePromptSend(t.id);
    }
    // The scheduler may have already recorded a due task (notification
    // tapped, or app cold-started from one) before this screen existed to
    // listen for it - ValueNotifier only notifies listeners of *future*
    // changes, so the already-set current value has to be checked directly.
    final currentDue = _scheduler.dueTaskId.value;
    if (currentDue != null) _maybePromptSend(currentDue);
  }

  void _onDueTaskChanged() {
    final id = _scheduler.dueTaskId.value;
    if (id != null) _maybePromptSend(id);
  }

  void _maybePromptSend(String taskId) {
    if (_promptedIds.contains(taskId)) return;
    _promptedIds.add(taskId);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      final task = _tasks.where((t) => t.id == taskId).firstOrNull;
      if (task != null && mounted) _openSendSheet(task);
    });
  }

  Future<void> _load() async {
    final tasks = await _repo.all();
    if (mounted) setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supplier Orders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await Navigator.push(context, MaterialPageRoute(builder: (_) => const QuickOrderScreen()));
          if (saved == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Quick Order'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? const EmptyState(icon: Icons.alarm_add_rounded, message: 'No supplier orders scheduled yet.\nTap "Quick Order" to note one down.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                  itemCount: _tasks.length,
                  itemBuilder: (context, i) => _tile(_tasks[i]),
                ),
    );
  }

  Widget _tile(ReorderTask task) {
    final due = task.status != ReorderTask.statusSent &&
        task.status != ReorderTask.statusCancelled &&
        !task.scheduledAt.isAfter(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: _statusColor(task.status).withOpacity(0.15),
          child: Icon(_statusIcon(task.status), color: _statusColor(task.status)),
        ),
        title: Text(task.supplierName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.note, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${formatDateTime(task.scheduledAt)}${task.repeatDaily ? '  •  daily' : ''}  •  ${task.supplierPhone}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _onAction(v, task),
          itemBuilder: (context) => [
            if (task.status != ReorderTask.statusCancelled && task.status != ReorderTask.statusSent)
              const PopupMenuItem(value: 'send', child: Text('Send Now')),
            if (task.status != ReorderTask.statusCancelled && task.status != ReorderTask.statusSent)
              const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case ReorderTask.statusSent:
        return AppColors.success;
      case ReorderTask.statusCancelled:
        return AppColors.textSecondary;
      case ReorderTask.statusNotified:
        return AppColors.warning;
      default:
        return AppColors.primaryBlue;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case ReorderTask.statusSent:
        return Icons.check_circle_rounded;
      case ReorderTask.statusCancelled:
        return Icons.cancel_rounded;
      case ReorderTask.statusNotified:
        return Icons.notifications_active_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  Future<void> _onAction(String action, ReorderTask task) async {
    switch (action) {
      case 'send':
        _openSendSheet(task);
        break;
      case 'cancel':
        await _scheduler.cancel(task);
        await _repo.updateStatus(task.id, ReorderTask.statusCancelled);
        _load();
        break;
      case 'delete':
        await _scheduler.cancel(task);
        await _repo.delete(task.id);
        _load();
        break;
    }
  }

  /// The actual "auto PDF + ready-to-send WhatsApp" step: generates the
  /// order PDF (if not already cached for this task) then shows the two
  /// send actions described in ReorderSchedulerService's doc comment.
  Future<void> _openSendSheet(ReorderTask task) async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _SendSheet(
        task: task,
        pdfService: _pdfService,
        waService: _waService,
        onMarkSent: () async {
          if (task.repeatDaily) {
            // A repeating order's OS alarm re-fires itself tomorrow (native
            // AlarmManager recurrence via matchDateTimeComponents.time in
            // ReorderSchedulerService - no re-scheduling call needed here).
            // What has to move is our own bookkeeping: advance scheduled_at
            // to tomorrow and reset status to pending, so this row is ready
            // to be recognised as "due" again on its next occurrence
            // instead of staying stuck as permanently "sent".
            await _repo.update(task.copyWith(
              status: ReorderTask.statusPending,
              scheduledAt: task.scheduledAt.add(const Duration(days: 1)),
            ));
          } else {
            await _repo.updateStatus(task.id, ReorderTask.statusSent);
          }
          _load();
        },
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _SendSheet extends StatefulWidget {
  final ReorderTask task;
  final PdfService pdfService;
  final WhatsAppFileService waService;
  final VoidCallback onMarkSent;

  const _SendSheet({
    required this.task,
    required this.pdfService,
    required this.waService,
    required this.onMarkSent,
  });

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  String? _pdfPath;
  bool _building = true;

  @override
  void initState() {
    super.initState();
    _buildPdf();
  }

  Future<void> _buildPdf() async {
    final bytes = await widget.pdfService.buildOrderNotePdf(
      note: widget.task.note,
      supplierName: widget.task.supplierName,
      supplierPhone: widget.task.supplierPhone,
      orderDate: widget.task.scheduledAt,
    );
    final file = await widget.pdfService.saveToFile(bytes, 'order_${widget.task.id}.pdf');
    if (mounted) setState(() {
      _pdfPath = file.path;
      _building = false;
    });
  }

  String get _message =>
      'Order for ${widget.task.supplierName}:\n${widget.task.note}\n\n- Professional Mobiles & Laptop Service';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send order to ${widget.task.supplierName}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(widget.task.supplierPhone, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            if (_building) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
            if (!_building) ...[
              ElevatedButton.icon(
                onPressed: () async {
                  await widget.waService.openChat(phone: widget.task.supplierPhone, message: _message);
                },
                icon: const Icon(Icons.chat_rounded),
                label: const Text('1. Open WhatsApp Chat'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pdfPath == null
                    ? null
                    : () async {
                        await widget.waService.sharePdf(
                          pdfPath: _pdfPath!,
                          supplierName: widget.task.supplierName,
                          caption: _message,
                        );
                      },
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('2. Share Order PDF (choose WhatsApp)'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Chat opens with your message ready - attach the PDF from step 2 (or just type it in) and tap Send in WhatsApp.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () {
                  widget.onMarkSent();
                  Navigator.pop(context);
                },
                child: const Text('Mark as Sent'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
