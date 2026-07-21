import 'package:flutter/material.dart';

import '../../customs/data/customs_repository.dart';
import '../data/accounting_repository.dart';
import 'account_ledger_page.dart';
import 'accounts_page.dart';
import 'journal_entries_page.dart';
import 'trial_balance_page.dart';

class AccountingHomePage extends StatefulWidget {
  const AccountingHomePage({super.key});

  @override
  State<AccountingHomePage> createState() => _AccountingHomePageState();
}

class _AccountingHomePageState extends State<AccountingHomePage> {
  final _customsRepository = CustomsRepository();
  final _accountingRepository = AccountingRepository();

  @override
  void initState() {
    super.initState();
    _syncAutomaticJournals();
  }

  Future<void> _syncAutomaticJournals() async {
    try {
      await _customsRepository.syncAutomaticAccountingJournals();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _resetJournalEntries() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _ResetJournalEntriesConfirmDialog(),
    );

    if (confirmed != true) return;

    try {
      await _accountingRepository.resetAllJournalEntries();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تصفير القيود اليومية بنجاح')),
      );

      setState(() {});
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الحسابات'),
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _AccountingButton(
              icon: Icons.account_tree_outlined,
              title: 'دليل الحسابات',
              onTap: () => _open(context, const AccountsPage()),
            ),
            _AccountingButton(
              icon: Icons.receipt_long,
              title: 'القيود اليومية',
              onTap: () => _open(context, const JournalEntriesPage()),
            ),
            _AccountingButton(
              icon: Icons.menu_book_outlined,
              title: 'دفتر الأستاذ',
              onTap: () => _open(context, const AccountLedgerPage()),
            ),
            _AccountingButton(
              icon: Icons.balance,
              title: 'ميزان المراجعة',
              onTap: () => _open(context, const TrialBalancePage()),
            ),
            const SizedBox(height: 12),
            _DangerAccountingButton(
              icon: Icons.delete_sweep_outlined,
              title: 'تصفير القيود اليومية',
              subtitle: 'حذف كل القيود والحركات المحاسبية فقط',
              onTap: _resetJournalEntries,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResetJournalEntriesConfirmDialog extends StatefulWidget {
  const _ResetJournalEntriesConfirmDialog();

  @override
  State<_ResetJournalEntriesConfirmDialog> createState() =>
      _ResetJournalEntriesConfirmDialogState();
}

class _ResetJournalEntriesConfirmDialogState
    extends State<_ResetJournalEntriesConfirmDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _canConfirm = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateCanConfirm);
  }

  @override
  void dispose() {
    _controller.removeListener(_updateCanConfirm);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateCanConfirm() {
    final canConfirm = _controller.text.trim() == 'تصفير';
    if (canConfirm == _canConfirm) return;

    setState(() {
      _canConfirm = canConfirm;
    });
  }

  void _confirm() {
    if (!_canConfirm) return;

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تصفير القيود اليومية'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سيتم حذف كل القيود اليومية اليدوية والتلقائية وكل الحركات المحاسبية. لن يتم حذف دليل الحسابات. هل أنت متأكد؟',
          ),
          const SizedBox(height: 12),
          const Text(
            'للمتابعة اكتب كلمة: تصفير',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'تصفير',
            ),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _canConfirm ? _confirm : null,
          icon: const Icon(Icons.delete_forever),
          label: const Text('تصفير القيود اليومية'),
        ),
      ],
    );
  }
}

class _AccountingButton extends StatelessWidget {
  const _AccountingButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}

class _DangerAccountingButton extends StatelessWidget {
  const _DangerAccountingButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Colors.red),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.warning_amber_outlined, color: Colors.red),
        onTap: onTap,
      ),
    );
  }
}
