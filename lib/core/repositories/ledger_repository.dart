import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/ledger_transaction.dart';

/// Writes and reads the unified accounting ledger. Every other repository
/// calls [record] whenever money or inventory value moves, so the P&L
/// engine can compute everything from real transactions (spec section 30)
/// instead of re-deriving profit from current stock snapshots.
class LedgerRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<void> record({
    required DateTime txnDate,
    required String category,
    required String txnType,
    String? referenceType,
    String? referenceId,
    required double amount,
    String? description,
    Transaction? txn,
  }) async {
    final entry = LedgerTransaction(
      id: newId(),
      txnDate: txnDate,
      category: category,
      txnType: txnType,
      referenceType: referenceType,
      referenceId: referenceId,
      amount: amount,
      description: description,
      createdAt: DateTime.now(),
    );
    if (txn != null) {
      await txn.insert('ledger_transactions', entry.toMap());
    } else {
      final db = await _dbHelper.database;
      await db.insert('ledger_transactions', entry.toMap());
    }
  }

  /// Removes all ledger rows tied to a given reference (used when a
  /// service/sale/purchase is edited and its financial rows need to be
  /// recreated from scratch rather than double counted).
  Future<void> clearForReference(String referenceType, String referenceId, {Transaction? txn}) async {
    final executor = txn ?? await _dbHelper.database;
    await executor.delete('ledger_transactions',
        where: 'reference_type = ? AND reference_id = ?', whereArgs: [referenceType, referenceId]);
  }

  Future<List<LedgerTransaction>> inRange(DateTime from, DateTime to, {String? category}) async {
    final db = await _dbHelper.database;
    final where = StringBuffer('txn_date >= ? AND txn_date <= ?');
    final args = <Object?>[from.toIso8601String(), to.toIso8601String()];
    if (category != null) {
      where.write(' AND category = ?');
      args.add(category);
    }
    final rows = await db.query('ledger_transactions', where: where.toString(), whereArgs: args);
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  /// Every ledger row tagged with a given [referenceType] - feeds
  /// QuickHistoryScreen's Income side (referenceType 'quick_income', see
  /// QuickTransactionRepository.recordIncome), newest first.
  Future<List<LedgerTransaction>> byReferenceType(String referenceType) async {
    final db = await _dbHelper.database;
    final rows = await db.query('ledger_transactions',
        where: 'reference_type = ?', whereArgs: [referenceType], orderBy: 'created_at DESC');
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  /// Removes a single ledger row by id - used by QuickHistoryScreen to
  /// delete a Quick Income entry (which, unlike a service/sale/expense,
  /// has no other repository row to clean up alongside it; the ledger row
  /// IS the record of that income).
  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('ledger_transactions', where: 'id = ?', whereArgs: [id]);
  }
}
