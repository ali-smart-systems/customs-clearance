import 'package:flutter/material.dart';

import '../data/accounting_repository.dart';
import '../domain/account.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final _repository = AccountingRepository();

  late Future<List<Account>> _future;

  static const _types = ['asset', 'liability', 'revenue', 'expense', 'equity'];

  @override
  void initState() {
    super.initState();
    _future = _repository.getAccounts();
  }

  void _reload() {
    setState(() {
      _future = _repository.getAccounts();
    });
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'asset':
        return 'أصل';
      case 'liability':
        return 'التزام';
      case 'revenue':
        return 'إيراد';
      case 'expense':
        return 'مصروف';
      case 'equity':
        return 'حقوق ملكية';
      default:
        return type;
    }
  }

  Future<void> _showAccountDialog([Account? account]) async {
    final codeController = TextEditingController(text: account?.code ?? '');
    final nameController = TextEditingController(text: account?.name ?? '');
    var selectedType = account?.type ?? 'asset';
    var isActive = account?.isActive ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(account == null ? 'إضافة حساب' : 'تعديل حساب'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: 'رمز الحساب',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم الحساب',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'نوع الحساب',
                        border: OutlineInputBorder(),
                      ),
                      items: _types
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(_typeLabel(type)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedType = value);
                      },
                    ),
                    CheckboxListTile(
                      value: isActive,
                      title: const Text('نشط'),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => isActive = value ?? true);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;

    try {
      if (account == null) {
        await _repository.createAccount(
          code: codeController.text,
          name: nameController.text,
          type: selectedType,
        );
      } else {
        await _repository.updateAccount(
          account: account,
          code: codeController.text,
          name: nameController.text,
          type: selectedType,
          isActive: isActive,
        );
      }

      if (!mounted) return;
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      codeController.dispose();
      nameController.dispose();
    }
  }

  Future<void> _deleteAccount(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف حساب'),
          content: Text('هل تريد حذف الحساب ${account.displayName}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteAccount(account);
      if (!mounted) return;
      _reload();
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
          title: const Text('دليل الحسابات'),
          centerTitle: true,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAccountDialog(),
          icon: const Icon(Icons.add),
          label: const Text('حساب'),
        ),
        body: FutureBuilder<List<Account>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final accounts = snapshot.data ?? [];

            if (accounts.isEmpty) {
              return const Center(child: Text('لا توجد حسابات'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final account = accounts[index];

                return Card(
                  child: ListTile(
                    title: Text(
                      account.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${_typeLabel(account.type)} - ${account.isActive ? 'نشط' : 'غير نشط'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'تعديل',
                          onPressed: () => _showAccountDialog(account),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          onPressed: () => _deleteAccount(account),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
