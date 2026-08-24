import 'package:flutter/material.dart';

import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/service_repository.dart';
import '../../core/utils/formatters.dart';
import '../../models/customer.dart';
import '../../models/service.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_badge.dart';
import 'service_detail_screen.dart';
import 'service_form_screen.dart';

class ServiceListScreen extends StatefulWidget {
  // When true, shows only jobs that are still pending (not yet Delivered
  // or Cancelled) - used by the Dashboard's "Pending Services" tap so it
  // actually opens the matching bills instead of just going to the
  // Service Bill tab (spec: "pending service click panna entha bill
  // pending la erukkunu kamikkanum"). This mirrors the Dashboard's own
  // definition of "pending" (see DashboardScreen._load), which isn't a
  // single ServiceStatus value, so it can't just reuse the status tabs
  // below - it's applied as its own client-side filter and this screen is
  // always pushed as its own route (with its own AppBar) when used this
  // way, rather than being the Service Bill destination inside the shell.
  final bool pendingOnly;
  const ServiceListScreen({super.key, this.pendingOnly = false});

  @override
  State<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends State<ServiceListScreen> {
  final _repo = ServiceRepository();
  final _customerRepo = CustomerRepository();
  List<ServiceJob> _services = [];
  Map<String, Customer> _customersById = {};
  bool _loading = true;
  String? _filter;
  bool _searching = false;
  String _query = '';
  final _searchCtrl = TextEditingController();

  final _tabs = ['All', ...ServiceStatus.all];

  bool get _pendingOnly => widget.pendingOnly;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.all(statusFilter: _filter);
    final customers = await _customerRepo.all();
    setState(() {
      _services = list;
      _customersById = {for (final c in customers) c.id: c};
      _loading = false;
    });
  }

  List<ServiceJob> get _filteredServices {
    var list = _services;
    if (_pendingOnly) {
      list = list.where((s) => s.status != ServiceStatus.delivered && s.status != ServiceStatus.cancelled).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((s) {
      final customer = _customersById[s.customerId];
      final name = customer?.name.toLowerCase() ?? '';
      final phone = customer?.phone?.toLowerCase() ?? '';
      final model = (s.model ?? '').toLowerCase();
      final mobileName = (s.mobileName ?? '').toLowerCase();
      final billNo = s.billNo.toLowerCase();
      return name.contains(q) || phone.contains(q) || model.contains(q) || mobileName.contains(q) || billNo.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredServices;
    return Scaffold(
      appBar: _pendingOnly ? AppBar(title: const Text('Pending Services')) : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Row(
              children: [
                if (_searching)
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search by name, phone or model',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    onChanged: (v) => setState(() => _query = v),
                    ),
                  )
                else
                const Spacer(),
                IconButton(
                  icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                  onPressed: () {
                    setState(() {
                      if (_searching) {
                        _searching = false;
                        _query = '';
                        _searchCtrl.clear();
                      } else {
                        _searching = true;
                      }
                    });
                  },
                  ),
                ],
              ),
            ),
          // The status tabs pick a single ServiceStatus, but "pending"
          // spans several statuses (see _filteredServices) - hidden here
          // so the fixed pending view isn't confused with a normal tab.
          if (!_pendingOnly)
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              itemCount: _tabs.length,
              itemBuilder: (context, i) {
                final tab = _tabs[i];
                final selected = (tab == 'All' && _filter == null) || tab == _filter;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(tab),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _filter = tab == 'All' ? null : tab);
                      _load();
                    },
                    ),
                  );
              },
              ),
            ),
          Expanded(
            child: _loading
            ? const Center(child: CircularProgressIndicator())
            : filtered.isEmpty
            ? EmptyState(icon: Icons.build_rounded, message: _pendingOnly ? 'No pending services - all caught up!' : 'No service jobs')
            : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final s = filtered[i];
                  final customer = _customersById[s.customerId];
                  return Card(
                    child: ListTile(
                      title: Text('${s.billNo} • ${s.mobileName ?? 'Device'}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${customer?.name ?? '-'} • ${customer?.phone ?? '-'}\n${s.complaint ?? '-'}\n${formatCurrency(s.billTotal)} • Balance: ${formatCurrency(s.displayBalance)}'),
                      isThreeLine: true,
                      trailing: StatusBadge(s.status, fontSize: 10),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailScreen(serviceId: s.id)));
                        _load();
                      },
                      ),
                    );
                },
                ),
              ),
            ),
          ],
        ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ServiceFormScreen()));
          if (created == true) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Service'),
        ),
      );
  }
}
