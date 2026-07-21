import 'package:flutter/material.dart';

import '../../../core/constants/demo_users.dart';
import '../../../features/accounting/presentation/accounting_home_page.dart';
import '../../../features/customs/data/customs_repository.dart';
import '../../../features/customs/domain/customs_record.dart';
import '../../../features/customs/presentation/dialogs/edit_name_dialog.dart';
import '../../../features/customs/presentation/customs_record_details_page.dart';
import '../../../features/customs/presentation/smart_customs_table_page.dart';
import '../../../features/manager/presentation/request_details_page.dart';
import '../../../features/search/presentation/main_search_page.dart';
import '../../../features/shipments/data/shipment_repository.dart';
import '../../../features/shipments/domain/shipment_request.dart';
import '../../../features/worker/presentation/worker_request_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _shipmentRepository = ShipmentRepository();
  final _customsRepository = CustomsRepository();
  final _smartTableKey = GlobalKey<SmartCustomsTablePageState>();

  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadHomeData();
  }

  Future<_HomeData> _loadHomeData() async {
    final pendingRequests = await _shipmentRepository.getPendingRequests();
    await _customsRepository.resyncPaymentsAndPaidAmounts();
    final customsRecords = await _customsRepository.getRecords();

    return _HomeData(
      pendingRequests: pendingRequests,
      customsRecords: customsRecords,
    );
  }

  void _reload() {
    setState(() {
      _future = _loadHomeData();
    });
  }

  Future<void> _openWorkerPage() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const WorkerRequestPage(),
      ),
    );

    if (result == true) {
      _reload();
    }
  }

  Future<void> _openSearchPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MainSearchPage(),
      ),
    );

    _reload();
  }

  Future<void> _openAccountingPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AccountingHomePage(),
      ),
    );

    await _customsRepository.resyncPaymentsAndPaidAmounts();
    if (!mounted) return;
    await _smartTableKey.currentState?.refreshFromDatabase();
    _reload();
  }

  Future<void> _openRequestDetails(ShipmentRequest request) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RequestDetailsPage(requestId: request.id),
      ),
    );

    _reload();
  }

  Future<void> _acceptRequest(ShipmentRequest request) async {
    await _shipmentRepository.acceptRequest(
      requestId: request.id,
      managerId: DemoUsers.managerId,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'تم قبول رسالة ${request.agentName} وإضافتها تحت نفس اسم الوكيل'),
      ),
    );

    _reload();
  }

  Future<void> _rejectRequest(ShipmentRequest request) async {
    await _shipmentRepository.rejectRequest(
      requestId: request.id,
      managerId: DemoUsers.managerId,
      reason: 'رفض من الشاشة الرئيسية',
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم رفض رسالة ${request.agentName}'),
      ),
    );

    _reload();
  }

  Future<void> _openAgentRecords(String agentName) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomsRecordDetailsPage(agentName: agentName),
      ),
    );

    _reload();
  }

  Future<void> _renameAgent(_AgentGroup agent) async {
    final newName = await showEditNameDialog(
      context,
      title: 'تعديل اسم الوكيل',
      currentName: agent.agentName,
      labelText: 'اسم الوكيل',
    );

    if (newName == null) return;

    try {
      await _customsRepository.renameAgent(agent.agentName, newName);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تعديل اسم الوكيل')),
      );

      _reload();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _deleteAgent(_AgentGroup agent) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف الوكيل'),
          content: Text(
            'سيتم حذف كل بيانات هذا الوكيل وعدد عملياته: ${agent.recordsCount}. هل أنت متأكد؟',
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
      await _customsRepository.deleteAgent(agent.agentName);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الوكيل وبياناته')),
      );

      _reload();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _resetOperationsData() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => const _ResetOperationsConfirmDialog(),
      );

      if (confirmed != true) return;

      await _customsRepository.resetAllOperationsData();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('تم تصفير البيانات السابقة بنجاح ويمكنك البدء من الصفر'),
        ),
      );

      _reload();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Widget _workerTopAction({required bool compact}) {
    if (compact) {
      return IconButton.filledTonal(
        tooltip: 'الدخول كعامل',
        onPressed: _openWorkerPage,
        icon: const Icon(Icons.engineering),
      );
    }

    return FilledButton.icon(
      onPressed: _openWorkerPage,
      icon: const Icon(Icons.engineering),
      label: const Text('الدخول كعامل'),
    );
  }

  Widget _smartTableTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _workerTopAction(compact: compact),
                ],
              ),
            ),
            Expanded(
              child: SmartCustomsTablePage(
                key: _smartTableKey,
                onChanged: _reload,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header() {
    return const Column(
      children: [
        Icon(
          Icons.local_shipping_outlined,
          size: 64,
          color: Color(0xFF1565C0),
        ),
        SizedBox(height: 8),
        Text(
          'الشاشة الرئيسية للتخليص الجمركي',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'إذا تكرر اسم الوكيل، تظهر كل بياناته تحت نفس الاسم ولا يتم إنشاء حقل مكرر.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _accountingButton() {
    return Center(
      child: FilledButton.icon(
        onPressed: _openAccountingPage,
        icon: const Icon(Icons.account_balance),
        label: const Text('إدارة الحسابات'),
      ),
    );
  }

  Widget _pendingRequestsSection(List<ShipmentRequest> requests) {
    if (requests.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.notifications_none),
          title: Text('لا توجد رسائل معلقة'),
          subtitle: Text('عند إرسال العامل بيانات جديدة ستظهر هنا للموافقة.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'رسائل معلقة بانتظار الموافقة (${requests.length})',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...requests.map((request) {
          return Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.notifications_active,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'رسالة معلقة من العامل',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اسم الوكيل: ${request.agentName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'السائق: ${request.driverName} | اللوحة: ${request.plateNumber} | الكمية: ${_formatNumber(request.quantity)}',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _acceptRequest(request),
                          icon: const Icon(Icons.check),
                          label: const Text('موافقة'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _rejectRequest(request),
                          icon: const Icon(Icons.close),
                          label: const Text('رفض'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'عرض التفاصيل',
                        onPressed: () => _openRequestDetails(request),
                        icon: const Icon(Icons.visibility),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _acceptedAgentsSection(List<CustomsRecord> records) {
    final agents = _groupRecordsByAgent(records);

    if (agents.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.table_rows_outlined),
          title: Text('لا توجد أسماء وكلاء معتمدة'),
          subtitle:
              Text('بعد الموافقة على رسالة العامل سيظهر اسم الوكيل هنا فقط.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الوكلاء المعتمدون (${agents.length})',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...agents.map((agent) {
          final isComplete =
              agent.pendingPricingCount == 0 && agent.pendingMerchantCount == 0;

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isComplete
                    ? Colors.green.withAlpha(35)
                    : Colors.orange.withAlpha(35),
                child: Icon(
                  isComplete ? Icons.check_circle : Icons.pending_actions,
                  color: isComplete ? Colors.green : Colors.orange,
                ),
              ),
              title: Text(
                agent.agentName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('عدد العمليات: ${agent.recordsCount}'),
                  const SizedBox(height: 4),
                  if (isComplete)
                    const Text(
                      'مكتمل: تم إضافة التسعير الجمركي والتاجر',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    Text(
                      'معلق: تسعير ناقص ${agent.pendingPricingCount} | تاجر ناقص ${agent.pendingMerchantCount}',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'تعديل',
                    onPressed: () => _renameAgent(agent),
                    icon: const Icon(Icons.edit, size: 20),
                  ),
                  IconButton(
                    tooltip: 'حذف',
                    onPressed: () => _deleteAgent(agent),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                  Icon(
                    isComplete ? Icons.verified : Icons.warning_amber,
                    color: isComplete ? Colors.green : Colors.orange,
                  ),
                ],
              ),
              onTap: () => _openAgentRecords(agent.agentName),
            ),
          );
        }),
      ],
    );
  }

  List<_AgentGroup> _groupRecordsByAgent(List<CustomsRecord> records) {
    final Map<String, _AgentGroup> grouped = {};

    for (final record in records) {
      final key = _normalizeAgentName(record.agentName);

      final needsPricing = _recordNeedsPricing(record);
      final needsMerchant = _recordNeedsMerchant(record);

      final existing = grouped[key];

      if (existing == null) {
        grouped[key] = _AgentGroup(
          agentName: record.agentName.trim(),
          recordsCount: 1,
          latestDate: record.createdAt,
          pendingPricingCount: needsPricing ? 1 : 0,
          pendingMerchantCount: needsMerchant ? 1 : 0,
        );
      } else {
        grouped[key] = existing.copyWith(
          recordsCount: existing.recordsCount + 1,
          latestDate: record.createdAt.isAfter(existing.latestDate)
              ? record.createdAt
              : existing.latestDate,
          pendingPricingCount:
              existing.pendingPricingCount + (needsPricing ? 1 : 0),
          pendingMerchantCount:
              existing.pendingMerchantCount + (needsMerchant ? 1 : 0),
        );
      }
    }

    final agents = grouped.values.toList()
      ..sort((a, b) => b.latestDate.compareTo(a.latestDate));

    return agents;
  }

  bool _recordNeedsPricing(CustomsRecord record) {
    final hasUnit =
        record.pricingUnit != null && record.pricingUnit!.trim().isNotEmpty;

    final hasUnitPrice = record.unitPrice != null && record.unitPrice! > 0;

    final hasAmount = record.customsAmount > 0;

    return !(hasUnit && hasUnitPrice && hasAmount);
  }

  bool _recordNeedsMerchant(CustomsRecord record) {
    return record.beneficiaryMerchant == null ||
        record.beneficiaryMerchant!.trim().isEmpty;
  }

  static String _normalizeAgentName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الرئيسية'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'بحث',
              onPressed: _openSearchPage,
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: 'المزيد',
              onSelected: (value) {
                if (value == 'reset_operations') {
                  _resetOperationsData();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'reset_operations',
                  child: ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red),
                    title: Text('تصفير البيانات'),
                    subtitle: Text('حذف العمليات والسداد والقيود التلقائية'),
                  ),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.table_chart_outlined), text: 'الجدول الذكي'),
              Tab(icon: Icon(Icons.badge_outlined), text: 'الوكلاء'),
              Tab(icon: Icon(Icons.pending_actions), text: 'الطلبات المعلقة'),
              Tab(icon: Icon(Icons.account_balance), text: 'إدارة الحسابات'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _smartTableTab(),
            _agentsTab(),
            _pendingRequestsTab(),
            _accountingTab(),
          ],
        ),
      ),
    );
  }

  Widget _homeDataBuilder(Widget Function(_HomeData data) builder) {
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ??
            const _HomeData(
              pendingRequests: [],
              customsRecords: [],
            );

        return builder(data);
      },
    );
  }

  Widget _agentsTab() {
    return _homeDataBuilder((data) {
      return RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            _header(),
            const SizedBox(height: 16),
            _acceptedAgentsSection(data.customsRecords),
          ],
        ),
      );
    });
  }

  Widget _pendingRequestsTab() {
    return _homeDataBuilder((data) {
      return RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            _pendingRequestsSection(data.pendingRequests),
          ],
        ),
      );
    });
  }

  Widget _accountingTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.account_balance),
            title: Text('إدارة الحسابات'),
            subtitle: Text(
                'دليل الحسابات والقيود اليومية ودفتر الأستاذ وميزان المراجعة.'),
          ),
        ),
        const SizedBox(height: 12),
        _accountingButton(),
      ],
    );
  }
}

class _ResetOperationsConfirmDialog extends StatefulWidget {
  const _ResetOperationsConfirmDialog();

  @override
  State<_ResetOperationsConfirmDialog> createState() =>
      _ResetOperationsConfirmDialogState();
}

class _ResetOperationsConfirmDialogState
    extends State<_ResetOperationsConfirmDialog> {
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
    final canConfirm = _controller.text.trim() == 'حذف';
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
      title: const Text('تصفير البيانات'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سيتم حذف كل عمليات التخليص والسداد والقيود التلقائية المرتبطة بها. لن يتم حذف دليل الحسابات أو القيود اليدوية. هل أنت متأكد؟',
          ),
          const SizedBox(height: 12),
          const Text(
            'للمتابعة اكتب كلمة: حذف',
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
              hintText: 'حذف',
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
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          onPressed: _canConfirm ? _confirm : null,
          icon: const Icon(Icons.delete_forever),
          label: const Text('تصفير البيانات'),
        ),
      ],
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.pendingRequests,
    required this.customsRecords,
  });

  final List<ShipmentRequest> pendingRequests;
  final List<CustomsRecord> customsRecords;
}

class _AgentGroup {
  const _AgentGroup({
    required this.agentName,
    required this.recordsCount,
    required this.latestDate,
    required this.pendingPricingCount,
    required this.pendingMerchantCount,
  });

  final String agentName;
  final int recordsCount;
  final DateTime latestDate;
  final int pendingPricingCount;
  final int pendingMerchantCount;

  _AgentGroup copyWith({
    String? agentName,
    int? recordsCount,
    DateTime? latestDate,
    int? pendingPricingCount,
    int? pendingMerchantCount,
  }) {
    return _AgentGroup(
      agentName: agentName ?? this.agentName,
      recordsCount: recordsCount ?? this.recordsCount,
      latestDate: latestDate ?? this.latestDate,
      pendingPricingCount: pendingPricingCount ?? this.pendingPricingCount,
      pendingMerchantCount: pendingMerchantCount ?? this.pendingMerchantCount,
    );
  }
}
