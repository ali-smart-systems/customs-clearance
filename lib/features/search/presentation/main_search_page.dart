import 'package:flutter/material.dart';

import '../../customs/data/customs_repository.dart';
import '../../customs/domain/customs_record.dart';
import '../../customs/presentation/dialogs/edit_name_dialog.dart';
import '../../customs/presentation/customs_record_details_page.dart';
import '../../drivers/presentation/driver_details_page.dart';
import '../../merchants/presentation/merchant_details_page.dart';

class MainSearchPage extends StatefulWidget {
  const MainSearchPage({super.key});

  @override
  State<MainSearchPage> createState() => _MainSearchPageState();
}

class _MainSearchPageState extends State<MainSearchPage> {
  final _repository = CustomsRepository();
  final _searchController = TextEditingController();

  late Future<List<CustomsRecord>> _future;

  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _repository.getRecords();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  List<_SearchItem> _buildResults(List<CustomsRecord> records) {
    final query = _normalize(_query);

    if (query.isEmpty) return [];

    final Map<String, _SearchItem> items = {};

    void addItem(_SearchItem item) {
      final key = '${item.type.name}:${_normalize(item.title)}';
      final existing = items[key];

      if (existing == null) {
        items[key] = item;
      } else {
        items[key] = existing.copyWith(
          count: existing.count + item.count,
        );
      }
    }

    for (final record in records) {
      final agentName = record.agentName.trim();
      final driverName = record.driverName.trim();
      final merchantName = record.beneficiaryMerchant?.trim();

      if (_normalize(agentName).contains(query)) {
        addItem(
          _SearchItem(
            type: _SearchType.agent,
            title: agentName,
            subtitle: 'وكيل - اضغط لعرض بيانات الوكيل',
            count: 1,
          ),
        );
      }

      if (_normalize(driverName).contains(query)) {
        addItem(
          _SearchItem(
            type: _SearchType.driver,
            title: driverName,
            subtitle: 'سائق - اضغط لعرض بيانات السائق',
            count: 1,
          ),
        );
      }

      if (merchantName != null &&
          merchantName.isNotEmpty &&
          _normalize(merchantName).contains(query)) {
        addItem(
          _SearchItem(
            type: _SearchType.merchant,
            title: merchantName,
            subtitle: 'تاجر - اضغط لعرض بيانات التاجر',
            count: 1,
          ),
        );
      }
    }

    final result = items.values.toList()
      ..sort((a, b) {
        final byType = a.type.index.compareTo(b.type.index);
        if (byType != 0) return byType;
        return a.title.compareTo(b.title);
      });

    return result;
  }

  IconData _iconFor(_SearchType type) {
    switch (type) {
      case _SearchType.agent:
        return Icons.person;
      case _SearchType.merchant:
        return Icons.store;
      case _SearchType.driver:
        return Icons.drive_eta;
    }
  }

  Color _colorFor(_SearchType type) {
    switch (type) {
      case _SearchType.agent:
        return Colors.blue;
      case _SearchType.merchant:
        return Colors.green;
      case _SearchType.driver:
        return Colors.orange;
    }
  }

  void _reloadResults() {
    setState(() {
      _future = _repository.getRecords();
    });
  }

  Future<void> _renameMerchantResult(_SearchItem item) async {
    final newName = await showEditNameDialog(
      context,
      title: 'تعديل اسم التاجر',
      currentName: item.title,
      labelText: 'اسم التاجر',
    );

    if (newName == null) return;

    try {
      await _repository.renameMerchant(item.title, newName);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تعديل اسم التاجر')),
      );

      _reloadResults();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _deleteMerchantResult(_SearchItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف التاجر'),
          content: const Text(
            'سيتم إزالة ارتباط هذا التاجر من السجلات. هل أنت متأكد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteMerchant(item.title);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف ارتباط التاجر')),
      );

      _reloadResults();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _openResult(_SearchItem item) async {
    switch (item.type) {
      case _SearchType.agent:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomsRecordDetailsPage(agentName: item.title),
          ),
        );
        break;

      case _SearchType.merchant:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MerchantDetailsPage(merchantName: item.title),
          ),
        );
        break;

      case _SearchType.driver:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverDetailsPage(driverName: item.title),
          ),
        );
        break;
    }

    if (!mounted) return;

    _reloadResults();
  }

  Widget _trailingFor(_SearchItem item) {
    if (item.type != _SearchType.merchant) {
      return const Icon(Icons.chevron_left);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'تعديل',
          onPressed: () => _renameMerchantResult(item),
          icon: const Icon(Icons.edit, size: 20),
        ),
        IconButton(
          tooltip: 'حذف',
          onPressed: () => _deleteMerchantResult(item),
          icon: const Icon(Icons.delete_outline, size: 20),
        ),
        const Icon(Icons.chevron_left),
      ],
    );
  }

  Widget _emptyState() {
    if (_query.isEmpty) {
      return const Center(
        child: Text('اكتب اسم الوكيل أو التاجر أو السائق للبحث'),
      );
    }

    return const Center(
      child: Text('لا توجد نتائج مطابقة'),
    );
  }

  Widget _resultsList(List<_SearchItem> results) {
    if (results.isEmpty) return _emptyState();

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = results[index];

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _colorFor(item.type).withAlpha(35),
              child: Icon(
                _iconFor(item.type),
                color: _colorFor(item.type),
              ),
            ),
            title: Text(
              item.title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text('${item.subtitle} - عدد العمليات: ${item.count}'),
            trailing: _trailingFor(item),
            onTap: () => _openResult(item),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بحث'),
          centerTitle: true,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText: 'بحث عن وكيل أو تاجر أو سائق',
                  hintText: 'اكتب الاسم هنا',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<CustomsRecord>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final records = snapshot.data ?? [];
                  final results = _buildResults(records);

                  return _resultsList(results);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SearchType {
  agent,
  merchant,
  driver,
}

class _SearchItem {
  const _SearchItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final _SearchType type;
  final String title;
  final String subtitle;
  final int count;

  _SearchItem copyWith({
    _SearchType? type,
    String? title,
    String? subtitle,
    int? count,
  }) {
    return _SearchItem(
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      count: count ?? this.count,
    );
  }
}
