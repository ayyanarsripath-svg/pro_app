import 'package:flutter/material.dart';

import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/service_repository.dart';
import '../../core/utils/formatters.dart';
import '../../models/customer.dart';
import '../../models/service.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_badge.dart';
import '../services/service_detail_screen.dart';

/// Complete customer history (spec: "Complete customer history") - every
/// service job tied to this customer, in one place.
class CustomerDetailScreen extends StatefulWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  final _customerRepo = CustomerRepository();
  final _serviceRepo = ServiceRepository();
  Customer? _customer;
  List<ServiceJob> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final customer = await _customerRepo.byId(widget.customerId);
    final services = await _serviceRepo.forCustomer(widget.customerId);
    setState(() {
      _customer = customer;
      _services = services;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _customer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = _customer!;
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SectionCard(title: 'Contact', icon: Icons.person_rounded, children: [
            Text('Phone: ${c.phone ?? '-'}'),
            if (c.phone2 != null && c.phone2!.isNotEmpty) Text('Alt Phone: ${c.phone2}'),
            if (c.address != null && c.address!.isNotEmpty) Text('Address: ${c.address}'),
            Text('Customer since: ${formatDate(c.createdAt)}'),
          ]),
          Text('Service History (${_services.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_services.isEmpty) const EmptyState(icon: Icons.build_rounded, message: 'No service history'),
          ..._services.map((s) => Card(
                child: ListTile(
                  title: Text('${s.billNo} - ${s.mobileName ?? ''} ${s.model ?? ''}'),
                  subtitle: Text('${s.complaint ?? '-'}\n${formatDate(s.createdAt)}  •  ${formatCurrency(s.finalAmount)}'),
                  isThreeLine: true,
                  trailing: StatusBadge(s.status, fontSize: 10),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailScreen(serviceId: s.id)));
                    _load();
                  },
                ),
              )),
        ],
      ),
    );
  }
}
