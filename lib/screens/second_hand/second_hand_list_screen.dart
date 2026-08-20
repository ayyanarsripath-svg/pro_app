import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/second_hand_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/second_hand_phone.dart';
import '../../widgets/section_card.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';
import 'second_hand_detail_screen.dart';
import 'second_hand_purchase_form_screen.dart';

class SecondHandListScreen extends StatefulWidget {
  const SecondHandListScreen({super.key});

  @override
  State<SecondHandListScreen> createState() => _SecondHandListScreenState();
}

class _SecondHandListScreenState extends State<SecondHandListScreen> {
  final _repo = SecondHandRepository();
  List<SecondHandPhone> _phones = [];
  Map<String, double> _stock = {};
  bool _loading = true;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final phones = await _repo.all(statusFilter: _filter);
    final stock = await _repo.stockSummary();
    setState(() {
      _phones = phones;
      _stock = stock;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    // Investment/profit figures are cost data (spec section 28) - never
    // shown to a login that isn't cleared to see cost/profit, regardless
    // of which menu section (Billing/Inventory/Full) it belongs to.
    final showCost = auth.canSeeCost;
    final showProfit = auth.canSeeProfit;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.6,
                    children: [
                      StatCard(label: 'Total Phones', value: _stock['totalPhones'] ?? 0, isCurrency: false, icon: Icons.phone_iphone_rounded),
                      StatCard(label: 'Unsold Stock', value: _stock['unsoldCount'] ?? 0, isCurrency: false, icon: Icons.inventory_rounded, color: AppColors.warning),
                      if (showCost) StatCard(label: 'Current Stock Value', value: _stock['currentStockValue'] ?? 0, icon: Icons.savings_rounded, color: AppColors.info),
                      if (showProfit) StatCard(label: 'Realized Profit', value: _stock['realizedProfit'] ?? 0, icon: Icons.trending_up_rounded, color: AppColors.success),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (showProfit)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Potential Profit (unsold): ${formatCurrency(_stock['potentialProfit'] ?? 0)}',
                                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context), fontStyle: FontStyle.italic)),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _filterChip('All', null),
                        ...SecondHandStatus.all.map((s) => _filterChip(s, s)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_phones.isEmpty) const EmptyState(icon: Icons.phone_iphone_rounded, message: 'No 2nd hand phones yet'),
                  ..._phones.map((phone) => Card(
                        child: ListTile(
                          title: Text('${phone.brand ?? ''} ${phone.model ?? ''} (${phone.purchaseNo})'),
                          subtitle: Text(showCost
                              ? '${phone.conditionGrade ?? '-'}  •  Investment: ${formatCurrency(phone.totalInvestment)}'
                              : phone.conditionGrade ?? '-'),
                          trailing: StatusBadge(phone.status, fontSize: 10),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => SecondHandDetailScreen(phoneId: phone.id)));
                            _load();
                          },
                        ),
                      )),
                ],
              ),
            ),
      // Buying a used phone into stock is an Inventory-side action - a
      // Billing-section login can still open this screen to sell an
      // already-purchased phone, but doesn't get the "add stock" button.
      floatingActionButton: auth.canDoInventoryActions
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SecondHandPurchaseFormScreen()));
                if (created == true) _load();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Purchase Phone'),
            )
          : null,
    );
  }

  Widget _filterChip(String label, String? value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filter = value);
          _load();
        },
      ),
    );
  }
}
