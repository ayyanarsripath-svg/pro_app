import 'package:flutter/material.dart';

import '../../core/repositories/service_repository.dart';
import '../../core/utils/formatters.dart';
import '../../models/service.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_badge.dart';
import 'service_detail_screen.dart';
import 'service_form_screen.dart';

class ServiceListScreen extends StatefulWidget {
  const ServiceListScreen({super.key});

  @override
  State<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends State<ServiceListScreen> {
  final _repo = ServiceRepository();
  List<ServiceJob> _services = [];
  bool _loading = true;
  String? _filter;

  final _tabs = ['All', ...ServiceStatus.all];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.all(statusFilter: _filter);
    setState(() {
      _services = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
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
                : _services.isEmpty
                    ? const EmptyState(icon: Icons.build_rounded, message: 'No service jobs')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _services.length,
                          itemBuilder: (context, i) {
                            final s = _services[i];
                            return Card(
                              child: ListTile(
                                title: Text('${s.billNo}  •  ${s.mobileName ?? 'Device'}',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                    '${s.complaint ?? '-'}\n${formatCurrency(s.finalAmount)}  •  Balance: ${formatCurrency(s.balance)}'),
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
