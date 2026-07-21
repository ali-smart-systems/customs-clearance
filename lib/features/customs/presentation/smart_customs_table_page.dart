import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/demo_users.dart';
import '../../customs/data/customs_repository.dart';
import '../../customs/data/smart_table_settings_repository.dart';
import '../../customs/data/smart_table_export_service.dart';
import '../../customs/domain/customs_record.dart';
import '../../customs/presentation/customs_record_details_page.dart';
import '../../customs/presentation/dialogs/merchant_dialog.dart';
import '../../customs/presentation/dialogs/payment_dialog.dart';
import '../../customs/presentation/dialogs/pricing_dialog.dart';
import '../../customs/presentation/dialogs/split_merchant_quantity_dialog.dart';
import '../../merchants/presentation/merchant_details_page.dart';
import '../../shipments/data/shipment_repository.dart';

const double _minColumnWidth = 70;
const double _maxColumnWidth = 300;
const double _rowNumberColumnWidth = 48;

const List<_RowMenuEntry> _rowMenuEntries = [
  _RowMenuEntry.action(
    action: _RowAction.move,
    icon: Icons.drive_file_move_outline,
    label: 'نقل الصف',
  ),
  _RowMenuEntry.action(
    action: _RowAction.copy,
    icon: Icons.copy_outlined,
    label: 'نسخ بيانات الصف',
  ),
  _RowMenuEntry.action(
    action: _RowAction.info,
    icon: Icons.info_outline,
    label: 'معلومات الصف',
  ),
  _RowMenuEntry.action(
    action: _RowAction.delete,
    icon: Icons.delete_outline,
    label: 'حذف الصف',
    destructive: true,
  ),
  _RowMenuEntry.divider(),
  _RowMenuEntry.header(
    icon: Icons.ios_share_outlined,
    label: 'تصدير وطباعة',
  ),
  _RowMenuEntry.action(
    action: _RowAction.exportExcel,
    icon: Icons.table_chart_outlined,
    label: 'تصدير الصف إلى Excel',
  ),
  _RowMenuEntry.action(
    action: _RowAction.exportPdf,
    icon: Icons.picture_as_pdf_outlined,
    label: 'تصدير الصف إلى PDF',
  ),
  _RowMenuEntry.action(
    action: _RowAction.print,
    icon: Icons.print_outlined,
    label: 'طباعة الصف',
  ),
  _RowMenuEntry.divider(),
  _RowMenuEntry.action(
    action: _RowAction.cancel,
    icon: Icons.close,
    label: 'إلغاء',
  ),
];

class SmartCustomsTablePage extends StatefulWidget {
  const SmartCustomsTablePage({
    super.key,
    this.onChanged,
  })  : _isFullscreen = false,
        _initialState = null;

  const SmartCustomsTablePage._fullscreen({
    required _SmartTableViewState initialState,
    this.onChanged,
  })  : _isFullscreen = true,
        _initialState = initialState;

  final VoidCallback? onChanged;
  final bool _isFullscreen;
  final _SmartTableViewState? _initialState;

  @override
  State<SmartCustomsTablePage> createState() => SmartCustomsTablePageState();
}

class SmartCustomsTablePageState extends State<SmartCustomsTablePage> {
  final _customsRepository = CustomsRepository();
  final _shipmentRepository = ShipmentRepository();
  final _settingsRepository = SmartTableSettingsRepository();
  final _exportService = SmartTableExportService();
  final _searchController = TextEditingController();
  final _jumpController = TextEditingController();
  final _inlineEditController = TextEditingController();
  final _inlineEditFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _tableTransformationController = TransformationController();

  late Future<List<CustomsRecord>> _future;
  List<_TableRowModel> _visibleRows = const [];
  _DateFilter _dateFilter = _DateFilter.allDays;
  _TableFilter _filter = _TableFilter.all;
  _TableSort _sort = _TableSort.manual;
  String? _selectedAgent;
  String? _selectedMerchant;
  String? _selectedRecordId;
  int? _selectedRowIndex;
  bool _groupByAgent = false;
  bool _showFullscreenSummary = false;
  bool _didAutoShowAll = false;
  bool _isSavingInlineEdit = false;
  bool _isCancellingInlineEdit = false;
  bool _isExportingRow = false;
  Timer? _singleTapTimer;
  DateTime? _ignoreSingleTapUntil;
  String? _lastPipelineDebug;
  CustomsRecord? _editingRecord;
  _TableColumn? _editingColumn;
  final Set<_TableColumn> _visibleColumns = {..._TableColumn.values};
  final Map<_TableColumn, double> _columnWidths = {};

  @override
  void initState() {
    super.initState();
    _inlineEditFocusNode.addListener(_handleInlineEditFocusChange);
    _applyInitialState();
    _future = _loadRecords();
    if (!widget._isFullscreen) {
      _loadSettings();
    }
  }

  @override
  void dispose() {
    _inlineEditFocusNode.removeListener(_handleInlineEditFocusChange);
    _searchController.dispose();
    _jumpController.dispose();
    _inlineEditController.dispose();
    _inlineEditFocusNode.dispose();
    _scrollController.dispose();
    _tableTransformationController.dispose();
    _singleTapTimer?.cancel();
    super.dispose();
  }

  Future<List<CustomsRecord>> _loadRecords() async {
    await _customsRepository.resyncPaymentsAndPaidAmounts();
    return _customsRepository.getRecords();
  }

  Future<void> refreshFromDatabase() async {
    await _customsRepository.resyncPaymentsAndPaidAmounts();
    if (!mounted) return;

    setState(() {
      _future = _customsRepository.getRecords();
    });
  }

  void _applyInitialState() {
    final initialState = widget._initialState;
    if (initialState == null) return;

    _searchController.text = initialState.searchText;
    _dateFilter = initialState.dateFilter;
    _filter = initialState.filter;
    _sort = initialState.sort;
    _selectedAgent = initialState.selectedAgent;
    _selectedMerchant = initialState.selectedMerchant;
    _groupByAgent = initialState.groupByAgent;
    _visibleColumns
      ..clear()
      ..addAll(initialState.visibleColumns);
    _columnWidths
      ..clear()
      ..addAll(initialState.columnWidths);
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsRepository.load();
    if (!mounted) return;

    final dateFilter = _enumByName(_DateFilter.values, settings.dateFilter);
    final statusFilter =
        _enumByName(_TableFilter.values, settings.statusFilter);
    final sort = _enumByName(_TableSort.values, settings.sort);
    final visibleColumns = settings.visibleColumns
        ?.map((name) => _enumByName(_TableColumn.values, name))
        .whereType<_TableColumn>()
        .toSet();
    final columnWidths = _parseColumnWidths(settings.columnWidths);

    setState(() {
      if (dateFilter != null) _dateFilter = dateFilter;
      if (statusFilter != null) _filter = statusFilter;
      if (sort != null) _sort = sort;
      _groupByAgent = settings.groupByAgent ?? _groupByAgent;
      if (visibleColumns != null && visibleColumns.isNotEmpty) {
        _visibleColumns
          ..clear()
          ..addAll(visibleColumns);
        _visibleColumns
          ..add(_TableColumn.clearanceFee)
          ..add(_TableColumn.driverAdvance);
      }
      _columnWidths
        ..clear()
        ..addAll(columnWidths);
    });
  }

  Map<_TableColumn, double> _parseColumnWidths(List<String>? values) {
    final widths = <_TableColumn, double>{};
    if (values == null) return widths;

    for (final value in values) {
      final separatorIndex = value.indexOf(':');
      if (separatorIndex <= 0) continue;
      final columnName = value.substring(0, separatorIndex);
      final width = double.tryParse(value.substring(separatorIndex + 1));
      final column = _enumByName(_TableColumn.values, columnName);
      if (column == null || width == null) continue;
      widths[column] = width.clamp(_minColumnWidth, _maxColumnWidth).toDouble();
    }

    return widths;
  }

  T? _enumByName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;

    for (final value in values) {
      if (value.name == name) return value;
    }

    return null;
  }

  Future<void> _saveVisibleColumns() {
    return _settingsRepository.saveVisibleColumns(
      _visibleColumns.map((column) => column.name).toList(),
    );
  }

  Future<void> _saveColumnWidths() {
    return _settingsRepository.saveColumnWidths(
      _columnWidths.map((column, width) => MapEntry(column.name, width)),
    );
  }

  double _columnWidth(_TableColumn column) {
    return _columnWidths[column] ?? column.defaultWidth;
  }

  double _visibleTableWidth() {
    const dataTableHorizontalMargin = 8.0 * 2;
    const resizeHandleAllowance = 4.0;
    const rowNumberColumnSpacing = 14.0;
    return _rowNumberColumnWidth +
        rowNumberColumnSpacing +
        _visibleColumns.fold<double>(
          dataTableHorizontalMargin,
          (sum, column) => sum + _columnWidth(column) + resizeHandleAllowance,
        ) +
        14.0 * (_visibleColumns.length - 1).clamp(0, _visibleColumns.length);
  }

  double _radiologyAmount(CustomsRecord record) {
    return record.radiologyAmount;
  }

  double _customsBaseAmount(CustomsRecord record) {
    return record.customsBaseAmount;
  }

  double _customsAndClearanceAmount(CustomsRecord record) {
    return _customsBaseAmount(record) + record.clearanceFee;
  }

  double _recordGrandTotal(CustomsRecord record) {
    return record.grandTotal;
  }

  double _recordBalance(CustomsRecord record) {
    return record.balanceAmount;
  }

  void _resizeColumn(_TableColumn column, double delta) {
    final width = (_columnWidth(column) + delta)
        .clamp(_minColumnWidth, _maxColumnWidth)
        .toDouble();

    setState(() {
      _columnWidths[column] = width;
    });

    _saveColumnWidths();
  }

  void _reload() {
    setState(() {
      _future = _loadRecords();
    });
    widget.onChanged?.call();
  }

  void _showAllRecords() {
    setState(() {
      _searchController.clear();
      _dateFilter = _DateFilter.allDays;
      _filter = _TableFilter.all;
      _sort = _TableSort.manual;
      _selectedAgent = null;
      _selectedMerchant = null;
      _selectedRecordId = null;
      _selectedRowIndex = null;
      _jumpController.clear();
    });

    _settingsRepository.saveDateFilter(_DateFilter.allDays.name);
    _settingsRepository.saveStatusFilter(_TableFilter.all.name);
    _settingsRepository.saveSort(_TableSort.manual.name);
  }

  void _scheduleShowAllIfFiltersHideRecords(
    List<CustomsRecord> records,
    List<CustomsRecord> visibleRecords,
  ) {
    if (_didAutoShowAll || records.isEmpty || visibleRecords.isNotEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didAutoShowAll) return;
      _didAutoShowAll = true;
      _showAllRecords();
    });
  }

  _SmartTableViewState _currentViewState() {
    return _SmartTableViewState(
      searchText: _searchController.text,
      dateFilter: _dateFilter,
      filter: _filter,
      sort: _sort,
      selectedAgent: _selectedAgent,
      selectedMerchant: _selectedMerchant,
      groupByAgent: _groupByAgent,
      visibleColumns: {..._visibleColumns},
      columnWidths: {..._columnWidths},
    );
  }

  Future<void> _openFullscreenTable() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SmartCustomsTablePage._fullscreen(
          initialState: _currentViewState(),
          onChanged: widget.onChanged,
        ),
      ),
    );

    if (!mounted) return;

    await _loadSettings();
    _reload();
  }

  bool _hasPricing(CustomsRecord record) {
    return record.customsAmount > 0 &&
        record.unitPrice != null &&
        record.unitPrice! > 0 &&
        record.pricingUnit != null &&
        record.pricingUnit!.trim().isNotEmpty;
  }

  bool _hasMerchant(CustomsRecord record) {
    return record.beneficiaryMerchant != null &&
        record.beneficiaryMerchant!.trim().isNotEmpty;
  }

  _RecordStatus _statusOf(CustomsRecord record) {
    const tolerance = 0.01;
    final total = _recordGrandTotal(record);
    if (total <= tolerance) {
      return record.paidAmount > tolerance
          ? _RecordStatus.credit
          : _RecordStatus.missingPricing;
    }
    if (!_hasMerchant(record)) return _RecordStatus.missingMerchant;
    if (record.paidAmount <= tolerance) return _RecordStatus.unpaid;
    if (record.paidAmount + tolerance < total) {
      return _RecordStatus.partial;
    }
    if ((record.paidAmount - total).abs() <= tolerance) {
      return _RecordStatus.paid;
    }
    return _RecordStatus.credit;
  }

  List<CustomsRecord> _visibleRecords(List<CustomsRecord> records) {
    final filtered = _recordsAfterStatusFilter(
      _recordsAfterSearch(_recordsForDate(records)),
    );

    filtered.sort((a, b) {
      switch (_sort) {
        case _TableSort.manual:
          return a.displayOrder.compareTo(b.displayOrder);
        case _TableSort.newest:
          return b.createdAt.compareTo(a.createdAt);
        case _TableSort.oldest:
          return a.createdAt.compareTo(b.createdAt);
        case _TableSort.agent:
          return a.agentName.compareTo(b.agentName);
        case _TableSort.merchant:
          return (a.beneficiaryMerchant ?? '')
              .compareTo(b.beneficiaryMerchant ?? '');
        case _TableSort.balanceDesc:
          return b.balanceAmount.compareTo(a.balanceAmount);
      }
    });

    return filtered;
  }

  List<CustomsRecord> _recordsAfterSearch(List<CustomsRecord> records) {
    final query = _normalize(_searchController.text);
    if (query.isEmpty) return records;

    return records.where((record) {
      final fields = [
        record.agentName,
        record.beneficiaryMerchant ?? '',
        record.driverName,
        record.plateNumber,
      ].map(_normalize).join(' ');

      return fields.contains(query);
    }).toList();
  }

  List<CustomsRecord> _recordsAfterStatusFilter(List<CustomsRecord> records) {
    return records.where((record) {
      final status = _statusOf(record);
      switch (_filter) {
        case _TableFilter.all:
          return true;
        case _TableFilter.missingPricing:
          return status == _RecordStatus.missingPricing;
        case _TableFilter.missingMerchant:
          return status == _RecordStatus.missingMerchant;
        case _TableFilter.unpaid:
          return status == _RecordStatus.unpaid;
        case _TableFilter.paid:
          return status == _RecordStatus.paid ||
              status == _RecordStatus.partial;
        case _TableFilter.credit:
          return status == _RecordStatus.credit;
        case _TableFilter.byAgent:
          return _selectedAgent == null || record.agentName == _selectedAgent;
        case _TableFilter.byMerchant:
          return _selectedMerchant == null ||
              record.beneficiaryMerchant == _selectedMerchant;
      }
    }).toList();
  }

  void _debugRowsPipeline(
    List<CustomsRecord> allRecords,
    List<CustomsRecord> finalRecords,
  ) {
    final dateRecords = _recordsForDate(allRecords);
    final searchRecords = _recordsAfterSearch(dateRecords);
    final statusRecords = _recordsAfterStatusFilter(searchRecords);
    final paidDebug = allRecords
        .where((record) => record.paidAmount > 0)
        .take(5)
        .map((record) {
      return '${record.id}:${record.paidAmount}:${_statusOf(record).name}';
    }).join(',');
    final signature = [
      allRecords.length,
      dateRecords.length,
      searchRecords.length,
      statusRecords.length,
      finalRecords.length,
      paidDebug,
      _dateFilter.name,
      _filter.name,
      _sort.name,
      _searchController.text,
    ].join('|');

    if (_lastPipelineDebug == signature) return;
    _lastPipelineDebug = signature;

    debugPrint(
      'SmartTable records: all=${allRecords.length}, '
      'afterDate=${dateRecords.length}, '
      'afterSearch=${searchRecords.length}, '
      'afterStatus=${statusRecords.length}, '
      'final=${finalRecords.length}, '
      'dateFilter=${_dateFilter.name}, '
      'statusFilter=${_filter.name}, '
      'sort=${_sort.name}, '
      'paidRecords=[$paidDebug]',
    );
  }

  List<CustomsRecord> _recordsForDate(List<CustomsRecord> records) {
    if (_dateFilter == _DateFilter.allDays) return records;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final start = switch (_dateFilter) {
      _DateFilter.today => todayStart,
      _DateFilter.yesterday => todayStart.subtract(const Duration(days: 1)),
      _DateFilter.allDays => DateTime(0),
    };
    final end = start.add(const Duration(days: 1));

    return records.where((record) {
      final createdAt = record.createdAt;
      return !createdAt.isBefore(start) && createdAt.isBefore(end);
    }).toList();
  }

  List<String> _agents(List<CustomsRecord> records) {
    return records.map((record) => record.agentName).toSet().toList()..sort();
  }

  List<String> _merchants(List<CustomsRecord> records) {
    return records
        .map((record) => record.beneficiaryMerchant?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Map<String, List<_TableRowModel>> _groupRowsByAgent(
    List<_TableRowModel> rows,
  ) {
    final grouped = <String, List<_TableRowModel>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.record.agentName, () => []).add(row);
    }
    return grouped;
  }

  List<_TableRowModel> _rowsWithRunningBalance(List<CustomsRecord> records) {
    var runningBalance = 0.0;
    final rows = <_TableRowModel>[];

    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      runningBalance += _recordBalance(record);
      rows.add(
        _TableRowModel(
          index: index,
          record: record,
          runningBalance: runningBalance,
          status: _statusOf(record),
        ),
      );
    }

    return rows;
  }

  void _syncSelectionWithRows(List<_TableRowModel> rows) {
    _visibleRows = rows;

    final selectedId = _selectedRecordId;
    if (selectedId == null) return;

    final index = rows.indexWhere((row) => row.record.id == selectedId);
    if (index == -1) {
      _selectedRecordId = null;
      _selectedRowIndex = null;
      _jumpController.clear();
      return;
    }

    if (_selectedRowIndex != index) {
      _selectedRowIndex = index;
      _jumpController.text = (index + 1).toString();
    }
  }

  void _selectRow(_TableRowModel row) {
    _goToVisibleRowIndex(row.index);
  }

  Future<void> _showRowLongPressMenu(_TableRowModel row) {
    return _showRowContextMenu(row);
  }

  Future<void> _showRowContextMenu(
    _TableRowModel row, {
    Offset? position,
  }) async {
    _cancelPendingSingleTap();
    _selectRow(row);

    if (!mounted) return;
    _RowAction? action;
    if (position == null) {
      action = await showModalBottomSheet<_RowAction>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: _rowMenuSheetItems(context),
            ),
          );
        },
      );
    } else {
      final menuPosition = _rowContextMenuPosition(context, position);
      action = await showMenu<_RowAction>(
        context: context,
        position: menuPosition,
        items: _rowMenuPopupItems(),
      );
    }

    if (action == null || !mounted) return;
    await _handleRowMenuAction(row, action);
  }

  RelativeRect _rowContextMenuPosition(
    BuildContext menuContext,
    Offset position,
  ) {
    final overlay =
        Overlay.of(menuContext).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    );
  }

  List<Widget> _rowMenuSheetItems(BuildContext sheetContext) {
    return _rowMenuEntries.map((entry) {
      if (entry.isDivider) return const Divider(height: 1);
      if (entry.action == null) {
        return ListTile(
          dense: true,
          enabled: false,
          leading: Icon(entry.icon),
          title: Text(entry.label),
        );
      }

      final color = entry.destructive ? Colors.red : null;
      return ListTile(
        leading: Icon(entry.icon, color: color),
        title: Text(entry.label, style: TextStyle(color: color)),
        onTap: () => Navigator.pop(sheetContext, entry.action),
      );
    }).toList();
  }

  List<PopupMenuEntry<_RowAction>> _rowMenuPopupItems() {
    return _rowMenuEntries.map<PopupMenuEntry<_RowAction>>((entry) {
      if (entry.isDivider) return const PopupMenuDivider(height: 1);
      if (entry.action == null) {
        return PopupMenuItem<_RowAction>(
          enabled: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon),
              const SizedBox(width: 8),
              Text(entry.label),
            ],
          ),
        );
      }

      final color = entry.destructive ? Colors.red : null;
      return PopupMenuItem<_RowAction>(
        value: entry.action,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(entry.icon, color: color),
            const SizedBox(width: 8),
            Text(entry.label, style: TextStyle(color: color)),
          ],
        ),
      );
    }).toList();
  }

  Future<void> _handleRowMenuAction(
    _TableRowModel row,
    _RowAction action,
  ) async {
    switch (action) {
      case _RowAction.move:
      case _RowAction.cancel:
        return;
      case _RowAction.copy:
        await _copyRowData(row);
        return;
      case _RowAction.info:
        await _showRowInfoDialog(row);
        return;
      case _RowAction.delete:
        await _deleteRowFromMenu(row);
        return;
      case _RowAction.exportExcel:
        await _exportSingleRow(row, _RowExportAction.excel);
        return;
      case _RowAction.exportPdf:
        await _exportSingleRow(row, _RowExportAction.pdf);
        return;
      case _RowAction.print:
        await _exportSingleRow(row, _RowExportAction.print);
        return;
    }
  }

  Widget _rowContextMenuRegion({
    required _TableRowModel row,
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showRowContextMenu(
        row,
        position: details.globalPosition,
      ),
      child: child,
    );
  }

  Future<void> _exportSingleRow(
    _TableRowModel row,
    _RowExportAction action,
  ) async {
    if (_isExportingRow) {
      _message('توجد عملية تصدير قيد التنفيذ. انتظر حتى تكتمل.');
      return;
    }

    final currentRowIndex = _visibleRows.indexWhere(
      (visibleRow) => visibleRow.record.id == row.record.id,
    );
    if (currentRowIndex == -1) {
      _message('لم يعد الصف المحدد موجوداً.');
      return;
    }
    final currentRow = _visibleRows[currentRowIndex];

    _isExportingRow = true;
    try {
      final data = _buildExportData(
        title: 'بيانات الصف رقم ${currentRow.index + 1}',
        rows: [currentRow],
        includeRowNumber: true,
        excludeActionsColumn: true,
      );

      switch (action) {
        case _RowExportAction.excel:
          final path = await _exportService.exportExcel(data);
          if (!mounted) return;
          _message('تم تصدير الصف إلى Excel بنجاح. $path');
          return;
        case _RowExportAction.pdf:
          final path = await _exportService.exportPdf(data);
          if (!mounted) return;
          _message('تم تصدير الصف إلى PDF بنجاح. $path');
          return;
        case _RowExportAction.print:
          await _exportService.printPdf(data);
          if (!mounted) return;
          _message('تم إرسال الصف للطباعة بنجاح.');
          return;
      }
    } catch (error) {
      if (!mounted) return;
      _message('تعذر تنفيذ العملية: $error');
    } finally {
      _isExportingRow = false;
    }
  }

  Future<void> _deleteRowFromMenu(_TableRowModel row) async {
    final confirmed = await _confirmDeleteRow(row);
    if (confirmed != true || !mounted) return;

    try {
      await _customsRepository.deleteRecord(row.record);
      if (!mounted) return;
      setState(() {
        _selectedRecordId = null;
        _selectedRowIndex = null;
        _jumpController.clear();
      });
      _message('تم حذف الصف بنجاح.');
      _reload();
    } catch (error) {
      if (!mounted) return;
      _message(error.toString());
    }
  }

  Future<bool?> _confirmDeleteRow(_TableRowModel row) {
    final record = row.record;
    final merchantName = record.beneficiaryMerchant?.trim();
    final fields = <MapEntry<String, String>>[
      MapEntry('رقم الصف', (row.index + 1).toString()),
      MapEntry('اسم الوكيل', record.agentName),
      MapEntry('اسم السائق', record.driverName),
      MapEntry('رقم اللوحة', record.plateNumber),
      if (merchantName != null && merchantName.isNotEmpty)
        MapEntry('التاجر', merchantName),
      MapEntry('مبلغ الجمارك', _money(record.customsAmount)),
      MapEntry('مبلغ السداد', _money(record.paidAmount)),
    ];

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف الصف'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'هل أنت متأكد من حذف هذا الصف؟\n'
                    'لا يمكن التراجع عن هذه العملية.',
                  ),
                  const SizedBox(height: 12),
                  ...fields.map((field) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(field.key),
                      subtitle: Text(
                        field.value.isEmpty ? '-' : field.value,
                        textDirection: TextDirection.rtl,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
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
  }

  Future<void> _copyRowData(_TableRowModel row) async {
    await Clipboard.setData(ClipboardData(text: _rowClipboardText(row)));
    _message('تم نسخ بيانات الصف.');
  }

  String _rowClipboardText(_TableRowModel row) {
    final lines = <String>[
      'بيانات الصف',
      'رقم الصف: ${row.index + 1}',
    ];

    for (final column in _visibleColumns) {
      if (column == _TableColumn.actions) continue;
      final value = _exportCellValue(column, row).trim();
      if (value.isEmpty) continue;
      lines.add('${column.label}: $value');
    }

    return lines.join('\n');
  }

  Future<void> _showRowInfoDialog(_TableRowModel row) {
    final record = row.record;
    final fields = <MapEntry<String, String>>[
      MapEntry('رقم الصف الظاهر', (row.index + 1).toString()),
      MapEntry('معرف السجل', record.id),
      MapEntry('اسم الوكيل', record.agentName),
      MapEntry('اسم السائق', record.driverName),
      MapEntry('رقم اللوحة', record.plateNumber),
      MapEntry('الكمية', _number(record.quantity)),
      MapEntry('مبلغ الجمارك', _money(record.customsAmount)),
      MapEntry('مبلغ السداد', _money(record.paidAmount)),
      MapEntry('الرصيد', _money(row.runningBalance)),
      MapEntry('التاجر', record.beneficiaryMerchant?.trim() ?? '-'),
      MapEntry('حالة السجل', row.status.label),
      MapEntry('تاريخ الإنشاء', _dateTime(record.createdAt)),
      MapEntry('تاريخ التعديل', _dateTime(record.updatedAt)),
    ];

    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('معلومات الصف'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: fields.map((field) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(field.key),
                    subtitle: Text(
                      field.value.isEmpty ? '-' : field.value,
                      textDirection: TextDirection.rtl,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  void _closeRowNavigator() {
    setState(() {
      _selectedRecordId = null;
      _selectedRowIndex = null;
      _jumpController.clear();
    });
  }

  void _goToVisibleRowIndex(int index) {
    final rows = _visibleRows;
    if (rows.isEmpty) {
      _closeRowNavigator();
      return;
    }

    if (index < 0 || index >= rows.length) {
      _message('رقم الصف خارج النطاق');
      return;
    }

    final row = rows[index];
    setState(() {
      _selectedRecordId = row.record.id;
      _selectedRowIndex = index;
      _jumpController.text = (index + 1).toString();
    });
    _scrollToSelectedRow();
  }

  void _goToTypedRowNumber() {
    final text = _jumpController.text.trim();
    final requestedRowNumber = int.tryParse(text);

    if (requestedRowNumber == null) {
      _message('أدخل رقم صف صحيح');
      return;
    }

    final totalRows = _visibleRows.length;
    if (requestedRowNumber < 1 || requestedRowNumber > totalRows) {
      _message('رقم الصف خارج النطاق');
      return;
    }

    _goToVisibleRowIndex(requestedRowNumber - 1);
  }

  Future<void> _moveSelectedRowToTypedNumber() async {
    if (_searchController.text.trim().isNotEmpty ||
        _filter != _TableFilter.all ||
        _dateFilter != _DateFilter.allDays ||
        _groupByAgent ||
        _sort != _TableSort.manual) {
      _message(
        'لا يمكن نقل الصف أثناء البحث أو التصفية أو التجميع. '
        'ألغِ البحث والفلاتر والتجميع ثم أعد المحاولة.',
      );
      return;
    }

    final fromIndex = _selectedRowIndex;
    if (fromIndex == null ||
        fromIndex < 0 ||
        fromIndex >= _visibleRows.length) {
      _message('حدد صفاً أولاً');
      return;
    }

    final text = _jumpController.text.trim();
    final requestedRowNumber = int.tryParse(text);
    if (requestedRowNumber == null) {
      _message('أدخل رقم صف صحيح');
      return;
    }

    if (requestedRowNumber < 1 || requestedRowNumber > _visibleRows.length) {
      _message('رقم الصف خارج النطاق');
      return;
    }

    final toIndex = requestedRowNumber - 1;
    if (toIndex == fromIndex) {
      _goToTypedRowNumber();
      return;
    }

    final selectedRecordId = _visibleRows[fromIndex].record.id;
    try {
      await _customsRepository.moveRecordToVisiblePosition(
        visibleRecords: _visibleRows.map((row) => row.record).toList(),
        fromIndex: fromIndex,
        toIndex: toIndex,
      );

      setState(() {
        _selectedRecordId = selectedRecordId;
        _selectedRowIndex = toIndex;
        _jumpController.text = (toIndex + 1).toString();
        _future = _loadRecords();
      });
      _scrollToSelectedRow();
    } catch (error) {
      _message(error.toString());
    }
  }

  void _scrollToSelectedRow() {
    final selectedIndex = _selectedRowIndex;
    if (selectedIndex == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      const rowHeight = 42.0;
      if (_scrollController.hasClients) {
        const tableTopOffset = 190.0;
        final target = tableTopOffset + (selectedIndex * rowHeight);
        final maxExtent = _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          target.clamp(0.0, maxExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        return;
      }

      final matrix = Matrix4.copy(_tableTransformationController.value);
      final scale = matrix.getMaxScaleOnAxis();
      final targetY = -(selectedIndex * rowHeight * scale);
      matrix.setTranslationRaw(matrix.storage[12], targetY, 0);
      _tableTransformationController.value = matrix;
    });
  }

  Future<void> _openAgent(CustomsRecord record) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomsRecordDetailsPage(agentName: record.agentName),
      ),
    );
    _reload();
  }

  Future<void> _openMerchant(CustomsRecord record) async {
    final merchantName = record.beneficiaryMerchant?.trim();
    if (merchantName == null || merchantName.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MerchantDetailsPage(merchantName: merchantName),
      ),
    );
    _reload();
  }

  Future<void> _editPricing(CustomsRecord record) async {
    if (_hasMerchant(record)) {
      _message('لا يمكن تعديل التسعير بعد إضافة التاجر');
      return;
    }

    final result = await showPricingDialog(
      context,
      quantity: record.quantity,
      currentUnit: record.pricingUnit,
      currentUnitPrice: record.unitPrice,
    );

    if (result == null) return;

    await _customsRepository.updatePricing(
      record: record,
      unit: result.unit,
      unitPrice: result.unitPrice,
    );
    _reload();
  }

  Future<void> _editMerchant(CustomsRecord record) async {
    if (!_hasPricing(record)) {
      _message('أضف التسعير أولاً قبل إضافة التاجر');
      return;
    }

    if (_hasMerchant(record)) {
      await _openMerchant(record);
      return;
    }

    final merchantName = await showMerchantDialog(
      context,
      currentName: record.beneficiaryMerchant,
    );
    if (merchantName == null) return;

    await _customsRepository.updateBeneficiaryMerchant(
      recordId: record.id,
      merchantName: merchantName,
    );
    _reload();
  }

  Future<void> _editPayment(CustomsRecord record) async {
    if (!_hasMerchant(record)) {
      _message('أضف التاجر أولاً قبل تسجيل السداد');
      return;
    }

    final changed = await showPaymentDialog(context, record: record);
    if (changed == true) {
      await _customsRepository.recalculatePaidAmount(record.id);
      if (!mounted) return;
      _reload();
    }
  }

  Future<void> _splitQuantity(CustomsRecord record) async {
    if (_hasMerchant(record)) {
      _message('لا يمكن توزيع سجل مرتبط بتاجر');
      return;
    }

    if (!_hasPricing(record)) {
      _message('أضف التسعير أولاً قبل توزيع الكمية');
      return;
    }

    final result = await showSplitMerchantQuantityDialog(
      context,
      availableQuantity: record.quantity,
    );
    if (result == null) return;

    await _customsRepository.splitQuantityForMerchant(
      record: record,
      merchantName: result.merchantName,
      merchantQuantity: result.quantity,
    );
    _reload();
  }

  Future<void> _addQuickRecord() async {
    final result = await showDialog<_QuickRecordInput>(
      context: context,
      builder: (context) => const _QuickRecordDialog(),
    );
    if (result == null) return;

    try {
      final requestId = await _shipmentRepository.createRequest(
        workerId: DemoUsers.workerId,
        agentName: result.agentName,
        driverName: result.driverName,
        plateNumber: result.plateNumber,
        quantity: result.quantity,
      );
      await _shipmentRepository.acceptRequest(
        requestId: requestId,
        managerId: DemoUsers.managerId,
      );

      _message('تمت إضافة العملية واعتمادها مباشرة');
      _reload();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _editRecord(CustomsRecord record) async {
    final result = await showDialog<_EditRecordInput>(
      context: context,
      builder: (context) => _EditRecordDialog(record: record),
    );
    if (result == null) return;

    try {
      await _customsRepository.updateRecord(
        record: record,
        agentName: result.agentName,
        driverName: result.driverName,
        plateNumber: result.plateNumber,
        quantity: result.quantity,
        unit: result.unit,
        unitPrice: result.unitPrice,
        clearanceFee: result.clearanceFee,
        driverAdvance: result.driverAdvance,
        merchantName: result.merchantName,
      );

      _message('تم تعديل العملية');
      _reload();
    } catch (error) {
      _message(error.toString());
    }
  }

  void _handleInlineEditFocusChange() {
    if (_inlineEditFocusNode.hasFocus ||
        _isSavingInlineEdit ||
        _isCancellingInlineEdit) {
      return;
    }

    final record = _editingRecord;
    final column = _editingColumn;
    if (record == null || column == null) return;

    _submitInlineEdit(record, column);
  }

  void _startInlineEdit(
    CustomsRecord record,
    _TableColumn column,
    String value,
  ) {
    if (!_isInlineEditable(column)) return;

    setState(() {
      _editingRecord = record;
      _editingColumn = column;
      _inlineEditController.text = value;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inlineEditFocusNode.requestFocus();
      _inlineEditController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _inlineEditController.text.length,
      );
    });
  }

  void _cancelInlineEdit() {
    _isCancellingInlineEdit = true;
    setState(() {
      _editingRecord = null;
      _editingColumn = null;
      _inlineEditController.clear();
    });
    _inlineEditFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isCancellingInlineEdit = false;
    });
  }

  Future<void> _submitInlineEdit(
    CustomsRecord record,
    _TableColumn column,
  ) async {
    if (_isSavingInlineEdit) return;
    if (_editingRecord?.id != record.id || _editingColumn != column) return;

    final rawValue = _inlineEditController.text.trim();
    final normalizedValue = rawValue.replaceAll(RegExp(r'\s+'), ' ');
    final currentMerchant = record.beneficiaryMerchant?.trim() ?? '';
    double? parsePositiveNumber(String label) {
      final parsed = double.tryParse(rawValue.replaceAll(',', '.'));
      if (parsed == null) {
        _message('$label يجب أن يكون رقماً صحيحاً');
        return null;
      }
      if (parsed <= 0) {
        _message('$label يجب أن يكون أكبر من صفر');
        return null;
      }
      return parsed;
    }

    double? parseNonNegativeNumber(String label) {
      final parsed = double.tryParse(rawValue.replaceAll(',', '.'));
      if (parsed == null) {
        _message('$label يجب أن يكون رقماً صحيحاً');
        return null;
      }
      if (parsed < 0) {
        _message('$label لا يمكن أن يكون أقل من صفر');
        return null;
      }
      return parsed;
    }

    String? agentName;
    String? driverName;
    String? plateNumber;
    double? quantity;
    String? pricingUnit;
    double? unitPrice;
    double? customsAmount;
    double? clearanceFee;
    double? driverAdvance;
    String? beneficiaryMerchant;

    switch (column) {
      case _TableColumn.agent:
        if (normalizedValue.isEmpty) {
          _message('اسم الوكيل مطلوب');
          return;
        }
        agentName = normalizedValue;
        break;
      case _TableColumn.driver:
        if (normalizedValue.isEmpty) {
          _message('اسم السائق مطلوب');
          return;
        }
        driverName = normalizedValue;
        break;
      case _TableColumn.plate:
        if (normalizedValue.isEmpty) {
          _message('رقم اللوحة مطلوب');
          return;
        }
        plateNumber = normalizedValue;
        break;
      case _TableColumn.quantity:
        quantity = parsePositiveNumber('الكمية');
        if (quantity == null) return;
        break;
      case _TableColumn.unit:
        pricingUnit = normalizedValue;
        break;
      case _TableColumn.unitPrice:
        unitPrice = parsePositiveNumber('سعر الوحدة');
        if (unitPrice == null) return;
        break;
      case _TableColumn.customsAmount:
        customsAmount = parsePositiveNumber('مبلغ الجمارك');
        if (customsAmount == null) return;
        break;
      case _TableColumn.clearanceFee:
        clearanceFee = parseNonNegativeNumber('رسوم التخليص');
        if (clearanceFee == null) return;
        break;
      case _TableColumn.driverAdvance:
        driverAdvance = parseNonNegativeNumber('سلفة السائق');
        if (driverAdvance == null) return;
        break;
      case _TableColumn.merchant:
        if (normalizedValue.isEmpty && currentMerchant.isNotEmpty) {
          _message('لا يمكن إفراغ اسم التاجر من التحرير المباشر');
          return;
        }
        beneficiaryMerchant = normalizedValue;
        break;
      case _TableColumn.date:
      case _TableColumn.paidAmount:
      case _TableColumn.balance:
      case _TableColumn.status:
      case _TableColumn.actions:
        return;
    }

    try {
      _isSavingInlineEdit = true;
      await _customsRepository.updateCustomsRecordInline(
        record: record,
        agentName: agentName,
        driverName: driverName,
        plateNumber: plateNumber,
        quantity: quantity,
        pricingUnit: pricingUnit,
        unitPrice: unitPrice,
        customsAmount: customsAmount,
        clearanceFee: clearanceFee,
        driverAdvance: driverAdvance,
        beneficiaryMerchant: beneficiaryMerchant,
      );

      if (!mounted) return;
      setState(() {
        _editingRecord = null;
        _editingColumn = null;
        _inlineEditController.clear();
      });
      _reload();
    } catch (error) {
      if (!mounted) return;
      _message(error.toString());
      _inlineEditFocusNode.requestFocus();
    } finally {
      _isSavingInlineEdit = false;
    }
  }

  Future<void> _deleteRecord(CustomsRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف العملية'),
          content: const Text('هل تريد حذف هذه العملية؟'),
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
      await _customsRepository.deleteRecord(record);
      _message('تم حذف العملية');
      _reload();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _showCellActionSheet({
    required CustomsRecord record,
    required String fieldKey,
    required String displayValue,
    required bool editable,
  }) async {
    final column = _enumByName(_TableColumn.values, fieldKey);
    if (column == null || column == _TableColumn.actions) return;

    final value = displayValue.trim();
    final isQuantity = fieldKey == _TableColumn.quantity.name;
    final isAccount =
        _isAccountColumn(column) && value.isNotEmpty && value != '-';
    final canUseCalculator = _isCalculatorColumn(column);
    final canOpenUrl = _isUrl(value);

    final action = await showModalBottomSheet<_CellAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              _cellActionTile(
                icon: Icons.content_paste_outlined,
                label: 'لصق',
                action: _CellAction.paste,
              ),
              _cellActionTile(
                icon: Icons.copy_outlined,
                label: 'نسخ',
                action: _CellAction.copy,
              ),
              _cellActionTile(
                icon: Icons.edit_outlined,
                label: 'تعديل',
                action: _CellAction.edit,
              ),
              if (isAccount)
                _cellActionTile(
                  icon: Icons.manage_accounts_outlined,
                  label: 'إجراءات الحساب',
                  action: _CellAction.accountActions,
                ),
              if (canUseCalculator)
                _cellActionTile(
                  icon: Icons.calculate_outlined,
                  label: 'آلة حاسبة',
                  action: _CellAction.calculator,
                ),
              if (isQuantity)
                _cellActionTile(
                  icon: Icons.medical_services_outlined,
                  label: 'أشعة',
                  action: _CellAction.radiology,
                ),
              _cellActionTile(
                icon: Icons.select_all_outlined,
                label: 'تحديد الكل',
                action: _CellAction.selectAll,
              ),
              _cellActionTile(
                icon: Icons.ios_share_outlined,
                label: 'مشاركة',
                action: _CellAction.share,
              ),
              if (isAccount)
                _cellActionTile(
                  icon: Icons.sms_outlined,
                  label: 'إرسال رسالة نصية SMS',
                  action: _CellAction.sms,
                ),
              if (isAccount)
                _cellActionTile(
                  icon: Icons.chat_outlined,
                  label: 'إرسال عبر WhatsApp',
                  action: _CellAction.whatsapp,
                ),
              if (canOpenUrl)
                _cellActionTile(
                  icon: Icons.open_in_browser_outlined,
                  label: 'الفتح في متصفح الويب',
                  action: _CellAction.openInBrowser,
                ),
              _cellActionTile(
                icon: Icons.delete_outline,
                label: 'حذف',
                action: _CellAction.delete,
                destructive: true,
              ),
            ],
          ),
        );
      },
    );

    if (action == null || !mounted) return;

    switch (action) {
      case _CellAction.paste:
        await _pasteIntoCell(record, column, editable);
        break;
      case _CellAction.copy:
        await _copyCellValue(value);
        break;
      case _CellAction.edit:
        _editCellFromMenu(record, column, displayValue, editable);
        break;
      case _CellAction.radiology:
        await _addRadiologyFee(record);
        break;
      case _CellAction.calculator:
        await _openCellCalculator(
          record: record,
          column: column,
          displayValue: displayValue,
        );
        break;
      case _CellAction.accountActions:
        await _showAccountActionsMenu(
          accountType: column == _TableColumn.merchant ? 'merchant' : 'agent',
          name: value,
        );
        break;
      case _CellAction.selectAll:
        _selectAllCellValue(record, column, displayValue, editable);
        break;
      case _CellAction.share:
        await _shareCellValue(value);
        break;
      case _CellAction.sms:
        await _sendCellAccountSms(column, value);
        break;
      case _CellAction.whatsapp:
        await _sendCellAccountWhatsApp(column, value);
        break;
      case _CellAction.openInBrowser:
        _message('فتح المتصفح غير متاح بدون مكتبة url_launcher.');
        break;
      case _CellAction.delete:
        await _deleteRecord(record);
        break;
    }
  }

  ListTile _cellActionTile({
    required IconData icon,
    required String label,
    required _CellAction action,
    bool destructive = false,
  }) {
    final color = destructive ? Colors.red : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: () => Navigator.pop(context, action),
    );
  }

  Future<void> _copyCellValue(String value) async {
    if (value.trim().isEmpty) {
      _message('لا يوجد نص للنسخ.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));
    _message('تم نسخ النص.');
  }

  Future<void> _pasteIntoCell(
    CustomsRecord record,
    _TableColumn column,
    bool editable,
  ) async {
    if (!editable || !_isInlineEditable(column)) {
      _message('هذا الحقل غير قابل للتعديل.');
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      _message('لا يوجد نص للصق.');
      return;
    }

    setState(() {
      _editingRecord = record;
      _editingColumn = column;
      _inlineEditController.text = text;
    });
    await _submitInlineEdit(record, column);
  }

  void _editCellFromMenu(
    CustomsRecord record,
    _TableColumn column,
    String displayValue,
    bool editable,
  ) {
    if (!editable || !_isInlineEditable(column)) {
      _message('هذا الحقل غير قابل للتعديل.');
      return;
    }

    _startInlineEdit(record, column, displayValue);
  }

  void _selectAllCellValue(
    CustomsRecord record,
    _TableColumn column,
    String displayValue,
    bool editable,
  ) {
    if (editable && _isInlineEditable(column)) {
      _startInlineEdit(record, column, displayValue);
      return;
    }

    _copyCellValue(displayValue);
  }

  Future<void> _shareCellValue(String value) async {
    if (value.trim().isEmpty) {
      _message('لا يوجد نص للمشاركة.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));
    _message('تم نسخ النص للمشاركة.');
  }

  Future<void> _sendCellAccountSms(_TableColumn column, String name) async {
    if (!_isAccountColumn(column)) return;
    final summary = await _loadAccountSummary(
      accountType: column == _TableColumn.merchant ? 'merchant' : 'agent',
      name: name,
    );
    final phone = await _requireAccountPhone(summary);
    if (phone == null) return;
    await _openSms(phone: phone, message: _accountStatementMessage(summary));
  }

  Future<void> _sendCellAccountWhatsApp(
      _TableColumn column, String name) async {
    if (!_isAccountColumn(column)) return;
    final summary = await _loadAccountSummary(
      accountType: column == _TableColumn.merchant ? 'merchant' : 'agent',
      name: name,
    );
    final whatsapp = await _requireAccountWhatsApp(summary);
    if (whatsapp == null) return;
    await _openWhatsApp(
      phone: whatsapp,
      message: _accountStatementMessage(summary),
    );
  }

  bool _isCalculatorColumn(_TableColumn column) {
    return switch (column) {
      _TableColumn.customsAmount ||
      _TableColumn.clearanceFee ||
      _TableColumn.driverAdvance ||
      _TableColumn.unitPrice ||
      _TableColumn.paidAmount =>
        true,
      _TableColumn.date ||
      _TableColumn.agent ||
      _TableColumn.driver ||
      _TableColumn.plate ||
      _TableColumn.quantity ||
      _TableColumn.unit ||
      _TableColumn.merchant ||
      _TableColumn.balance ||
      _TableColumn.status ||
      _TableColumn.actions =>
        false,
    };
  }

  bool _isAccountColumn(_TableColumn column) {
    return column == _TableColumn.agent || column == _TableColumn.merchant;
  }

  Future<List<CustomsRecord>> _recordsForAccount(
    String accountType,
    String name,
  ) {
    if (accountType == 'merchant') {
      return _customsRepository.getRecordsByMerchantName(name);
    }
    return _customsRepository.getRecordsByAgentName(name);
  }

  _AccountSummary _accountSummary({
    required String accountType,
    required String name,
    required List<CustomsRecord> records,
  }) {
    final totalCustoms = records.fold(
      0.0,
      (sum, record) => sum + _recordGrandTotal(record),
    );
    final totalPaid = records.fold(
      0.0,
      (sum, record) => sum + record.paidAmount,
    );

    return _AccountSummary(
      accountType: accountType,
      name: name,
      records: records,
      totalCustoms: totalCustoms,
      totalPaid: totalPaid,
      balance: totalCustoms - totalPaid,
    );
  }

  Future<_AccountSummary> _loadAccountSummary({
    required String accountType,
    required String name,
  }) async {
    final records = await _recordsForAccount(accountType, name);
    return _accountSummary(
      accountType: accountType,
      name: name,
      records: records,
    );
  }

  String _accountStatementMessage(_AccountSummary summary) {
    final isMerchant = summary.accountType == 'merchant';
    final rows = _rowsWithRunningBalance(summary.records);
    final grandTotal = rows.fold(
      0.0,
      (sum, row) => sum + _recordGrandTotal(row.record),
    );
    final lines = <String>[
      'الأخ/ ${summary.name}',
      'هذا كشف بتفاصيل عملية التخليص الخاصة بكم.',
      '',
      'إجمالي المبلغ: ${_messageMoney(grandTotal)} ريال',
      '',
    ];

    for (final row in rows) {
      final record = row.record;
      final radiologyFee = _radiologyAmount(record);
      final customsAndClearanceAmount = _customsAndClearanceAmount(record);
      lines.add(
        rows.length > 1 ? 'العملية رقم ${row.index + 1}:' : 'بيانات العملية:',
      );

      if (isMerchant) {
        lines.add('الوكيل: ${record.agentName}');
      } else {
        lines.add('التاجر: ${record.beneficiaryMerchant ?? '-'}');
      }

      lines
        ..add('السائق: ${record.driverName}')
        ..add('رقم اللوحة: ${record.plateNumber}')
        ..add('الكمية: ${_number(record.quantity)}')
        ..add('التاريخ: ${_date(record.createdAt)}')
        ..add('')
        ..add('تفاصيل المبلغ:')
        ..add(
          'مبلغ الجمارك والتخليص: ${_messageMoney(customsAndClearanceAmount)} ريال',
        );

      if (radiologyFee > 0) {
        lines.add('رسوم الأشعة: ${_messageMoney(radiologyFee)} ريال');
      }

      if (record.driverAdvance > 0) {
        lines.add(
          'سلفة بيد السائق: ${_messageMoney(record.driverAdvance)} ريال',
        );
      }

      if (rows.length > 1) {
        lines.add('');
      }
    }

    return lines.join('\n');
  }

  Future<void> _showAccountActionsMenu({
    required String accountType,
    required String name,
    String? accountId,
  }) async {
    final title =
        accountType == 'merchant' ? 'إجراءات التاجر' : 'إجراءات الوكيل';
    final action = await showModalBottomSheet<_AccountAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(name),
                subtitle: Text(title),
                leading: Icon(
                  accountType == 'merchant'
                      ? Icons.storefront_outlined
                      : Icons.badge_outlined,
                ),
              ),
              const Divider(height: 1),
              _accountActionTile(
                icon: Icons.manage_search_outlined,
                label: 'بحث متقدم',
                action: _AccountAction.advancedSearch,
              ),
              _accountActionTile(
                icon: Icons.receipt_long_outlined,
                label: 'طابعة حرارية',
                action: _AccountAction.thermalPrint,
              ),
              _accountActionTile(
                icon: Icons.ios_share_outlined,
                label: 'مشاركة',
                action: _AccountAction.share,
              ),
              _accountActionTile(
                icon: Icons.table_chart_outlined,
                label: 'إكسل',
                action: _AccountAction.excel,
              ),
              _accountActionTile(
                icon: Icons.sms_outlined,
                label: 'إرسال رسالة نصية',
                action: _AccountAction.sms,
              ),
              _accountActionTile(
                icon: Icons.chat_outlined,
                label: 'إرسال رسالة واتساب',
                action: _AccountAction.whatsapp,
              ),
              _accountActionTile(
                icon: Icons.forum_outlined,
                label: 'إرسال رسالة نصية + واتساب',
                action: _AccountAction.smsAndWhatsapp,
              ),
              _accountActionTile(
                icon: Icons.verified_outlined,
                label: 'مصادقة على الحساب واتساب',
                action: _AccountAction.whatsappConfirmation,
              ),
              _accountActionTile(
                icon: Icons.lock_outline,
                label: 'إغلاق الرصيد',
                action: _AccountAction.closeBalance,
              ),
              _accountActionTile(
                icon: Icons.compare_arrows_outlined,
                label: 'تحويل من حساب إلى حساب',
                action: _AccountAction.transfer,
              ),
              _accountActionTile(
                icon: Icons.notifications_active_outlined,
                label: 'التنبيهات',
                action: _AccountAction.alerts,
              ),
              _accountActionTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'سقف الحساب',
                action: _AccountAction.creditLimit,
              ),
              _accountActionTile(
                icon: Icons.contact_phone_outlined,
                label: 'بيانات الاتصال',
                action: _AccountAction.contactInfo,
              ),
            ],
          ),
        );
      },
    );

    if (action == null || !mounted) return;
    await _handleAccountAction(
      action: action,
      accountType: accountType,
      name: name,
      accountId: accountId,
    );
  }

  ListTile _accountActionTile({
    required IconData icon,
    required String label,
    required _AccountAction action,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.pop(context, action),
    );
  }

  Future<void> _handleAccountAction({
    required _AccountAction action,
    required String accountType,
    required String name,
    String? accountId,
  }) async {
    final summary = await _loadAccountSummary(
      accountType: accountType,
      name: name,
    );

    try {
      switch (action) {
        case _AccountAction.advancedSearch:
          await _showAdvancedAccountSearch(summary);
          break;
        case _AccountAction.thermalPrint:
          await _exportService.printPdf(_accountExportData(summary));
          break;
        case _AccountAction.share:
          await Clipboard.setData(
            ClipboardData(text: _accountStatementMessage(summary)),
          );
          _message('تم نسخ الملخص للمشاركة.');
          break;
        case _AccountAction.excel:
          final path = await _exportService.exportExcel(
            _accountExportData(summary),
          );
          _message('تم تصدير Excel: $path');
          break;
        case _AccountAction.sms:
          final phone = await _requireAccountPhone(summary);
          if (phone == null) return;
          await _openSms(
            phone: phone,
            message: _accountStatementMessage(summary),
          );
          break;
        case _AccountAction.whatsapp:
          final whatsapp = await _requireAccountWhatsApp(summary);
          if (whatsapp == null) return;
          await _openWhatsApp(
            phone: whatsapp,
            message: _accountStatementMessage(summary),
          );
          break;
        case _AccountAction.smsAndWhatsapp:
          final phone = await _requireAccountPhone(summary);
          final whatsapp = await _requireAccountWhatsApp(summary);
          if (phone == null || whatsapp == null) return;
          await _showSmsAndWhatsAppDialog(
            phone: phone,
            whatsapp: whatsapp,
            message: _accountStatementMessage(summary),
          );
          break;
        case _AccountAction.whatsappConfirmation:
          final whatsapp = await _requireAccountWhatsApp(summary);
          if (whatsapp == null) return;
          await _openWhatsApp(
            phone: whatsapp,
            message: 'مصادقة حساب\n${_accountStatementMessage(summary)}',
          );
          break;
        case _AccountAction.closeBalance:
          await _confirmCloseBalance(summary);
          break;
        case _AccountAction.transfer:
          await _showSafePlaceholder(
            title: 'تحويل من حساب إلى حساب',
            message:
                'يحتاج التحويل إلى قيد يومية متوازن. لم يتم تغيير بيانات التخليص أو الرصيد.',
          );
          break;
        case _AccountAction.alerts:
          await _showAccountAlertDialog(summary);
          break;
        case _AccountAction.creditLimit:
          await _showCreditLimitDialog(summary);
          break;
        case _AccountAction.contactInfo:
          await _showAccountContactDialog(summary);
          break;
      }
    } catch (error) {
      _message(error.toString());
    }
  }

  SmartTableExportData _accountExportData(_AccountSummary summary) {
    return _buildExportData(
      title: 'كشف حساب: ${summary.name}',
      rows: _rowsWithRunningBalance(summary.records),
    );
  }

  Future<void> _showAdvancedAccountSearch(_AccountSummary summary) async {
    var query = '';
    var statusName = 'all';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final rows = _rowsWithRunningBalance(summary.records).where((row) {
              final record = row.record;
              final statusMatches =
                  statusName == 'all' || row.status.name == statusName;
              final queryText = query.trim().toLowerCase();
              if (queryText.isEmpty) return statusMatches;

              final haystack = [
                _date(record.createdAt),
                record.driverName,
                record.plateNumber,
                _money(record.customsAmount),
                _money(record.paidAmount),
                _money(row.runningBalance),
                row.status.label,
              ].join(' ').toLowerCase();

              return statusMatches && haystack.contains(queryText);
            }).toList();

            return AlertDialog(
              title: Text('بحث متقدم: ${summary.name}'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText:
                              'بحث بالتاريخ، السائق، اللوحة، المبلغ، السداد',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            query = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: statusName,
                        decoration: const InputDecoration(
                          labelText: 'الحالة',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('كل الحالات'),
                          ),
                          ..._RecordStatus.values.map(
                            (status) => DropdownMenuItem(
                              value: status.name,
                              child: Text(status.label),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            statusName = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('النتائج: ${rows.length}'),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 260,
                        child: rows.isEmpty
                            ? const Center(child: Text('لا توجد نتائج'))
                            : ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final row = rows[index];
                                  final record = row.record;
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      '${record.driverName} / ${record.plateNumber}',
                                    ),
                                    subtitle: Text(
                                      '${_date(record.createdAt)} - ${row.status.label}',
                                    ),
                                    trailing: Text(
                                      _money(row.runningBalance),
                                      textDirection: TextDirection.ltr,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmCloseBalance(_AccountSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('إغلاق الرصيد'),
          content: const Text(
            'سيتم إنشاء إجراء إغلاق/تسوية لهذا الحساب. هل أنت متأكد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('متابعة'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _showSafePlaceholder(
      title: 'إغلاق الرصيد',
      message:
          'سيتم تنفيذ إغلاق الرصيد في مرحلة لاحقة بعد اعتماد قيد التسوية. لم يتم تعديل الرصيد أو القيود.',
    );
  }

  Future<void> _showSafePlaceholder({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('موافق'),
            ),
          ],
        );
      },
    );
  }

  String _accountPrefsKey(_AccountSummary summary, String field) {
    return 'account_actions.${summary.accountType}.${summary.name}.$field';
  }

  Future<void> _showAccountAlertDialog(_AccountSummary summary) async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final noteController = TextEditingController(
      text:
          preferences.getString(_accountPrefsKey(summary, 'alert_note')) ?? '',
    );
    final dateController = TextEditingController(
      text:
          preferences.getString(_accountPrefsKey(summary, 'alert_date')) ?? '',
    );
    var enabled =
        preferences.getBool(_accountPrefsKey(summary, 'alert_enabled')) ??
            false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('التنبيهات: ${summary.name}'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      value: enabled,
                      title: const Text('تفعيل التنبيه'),
                      onChanged: (value) {
                        setDialogState(() {
                          enabled = value;
                        });
                      },
                    ),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'نص التنبيه',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: dateController,
                      decoration: const InputDecoration(
                        labelText: 'تاريخ التنبيه',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await preferences.setBool(
                      _accountPrefsKey(summary, 'alert_enabled'),
                      enabled,
                    );
                    await preferences.setString(
                      _accountPrefsKey(summary, 'alert_note'),
                      noteController.text,
                    );
                    await preferences.setString(
                      _accountPrefsKey(summary, 'alert_date'),
                      dateController.text,
                    );
                    navigator.pop();
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
    noteController.dispose();
    dateController.dispose();
  }

  Future<void> _showCreditLimitDialog(_AccountSummary summary) async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final controller = TextEditingController(
      text: preferences
              .getDouble(_accountPrefsKey(summary, 'credit_limit'))
              ?.toStringAsFixed(2) ??
          '',
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('سقف الحساب: ${summary.name}'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'السقف الائتماني',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final value = double.tryParse(
                  controller.text.trim().replaceAll(',', ''),
                );
                if (value == null || value < 0) {
                  _message('أدخل سقفاً صحيحاً.');
                  return;
                }
                await preferences.setDouble(
                  _accountPrefsKey(summary, 'credit_limit'),
                  value,
                );
                navigator.pop();
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showAccountContactDialog(_AccountSummary summary) async {
    final contact = await _customsRepository.getAccountContact(
      summary.accountType,
      summary.name,
    );
    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _AccountContactDialog(
        accountType: summary.accountType,
        accountName: summary.name,
        contact: contact,
        repository: _customsRepository,
      ),
    );

    if (saved == true) {
      if (!mounted) return;
      _message('تم حفظ بيانات الاتصال بنجاح');
    }
  }

  Future<String?> _requireAccountPhone(_AccountSummary summary) async {
    final phone = await _customsRepository.getAccountPhone(
      summary.accountType,
      summary.name,
    );
    if (phone != null) return phone;

    _message(
        'لا يوجد رقم هاتف محفوظ لهذا الحساب. الرجاء إدخال رقم الهاتف أولاً.');
    await _showAccountContactDialog(summary);
    return _customsRepository.getAccountPhone(
        summary.accountType, summary.name);
  }

  Future<String?> _requireAccountWhatsApp(_AccountSummary summary) async {
    final whatsapp = await _customsRepository.getAccountWhatsApp(
      summary.accountType,
      summary.name,
    );
    if (whatsapp != null) return whatsapp;

    _message('لا يوجد رقم واتساب محفوظ لهذا الحساب. الرجاء إدخال الرقم أولاً.');
    await _showAccountContactDialog(summary);
    return _customsRepository.getAccountWhatsApp(
      summary.accountType,
      summary.name,
    );
  }

  String _cleanPhoneNumber(String value, {required bool forWhatsApp}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    final buffer = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];
      final isDigit = RegExp(r'\d').hasMatch(char);
      if (isDigit) {
        buffer.write(char);
      } else if (!forWhatsApp && char == '+' && buffer.isEmpty) {
        buffer.write(char);
      }
    }

    return buffer.toString();
  }

  bool _looksLikeInternationalWhatsAppNumber(String phone) {
    return phone.length >= 10 && !phone.startsWith('0');
  }

  Future<void> _openSms({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = _cleanPhoneNumber(phone, forWhatsApp: false);
    if (cleanPhone.isEmpty) {
      _message('لا يوجد رقم هاتف محفوظ لهذا الحساب. الرجاء إدخال الرقم أولاً.');
      return;
    }

    final encodedMessage = Uri.encodeComponent(message);
    final uri = Uri.parse('sms:$cleanPhone?body=$encodedMessage');

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      // Fall back to the clipboard message below.
    }

    await _copyPreparedMessage(
      message: message,
      fallbackMessage: 'تعذر فتح تطبيق الرسائل. تم نسخ الرسالة.',
    );
  }

  Future<void> _openWhatsApp({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = _cleanPhoneNumber(phone, forWhatsApp: true);
    if (cleanPhone.isEmpty) {
      _message('لا يوجد رقم واتساب محفوظ لهذا الحساب.');
      return;
    }
    if (!_looksLikeInternationalWhatsAppNumber(cleanPhone)) {
      _message('رقم واتساب يجب أن يتضمن مفتاح الدولة، مثال: 967xxxxxxxxx');
      return;
    }

    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUri = Uri.parse(
      'whatsapp://send?phone=$cleanPhone&text=$encodedMessage',
    );
    try {
      final canOpenWhatsApp = await canLaunchUrl(whatsappUri);
      if (canOpenWhatsApp) {
        final opened = await launchUrl(
          whatsappUri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) return;
      }
    } catch (_) {
      // Fall back to the web link below.
    }

    final webUri = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');
    try {
      final opened = await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      // Fall back to the clipboard message below.
    }

    await _copyPreparedMessage(
      message: message,
      fallbackMessage: 'تعذر فتح واتساب. تم نسخ الرسالة.',
    );
  }

  Future<void> _showSmsAndWhatsAppDialog({
    required String phone,
    required String whatsapp,
    required String message,
  }) async {
    final action = await showDialog<_AccountMessageAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('إرسال رسالة'),
          content: const Text('اختر التطبيق الذي تريد فتحه لإرسال الرسالة.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(context, _AccountMessageAction.sms),
              icon: const Icon(Icons.sms_outlined),
              label: const Text('إرسال SMS'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(context, _AccountMessageAction.whatsapp),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('إرسال واتساب'),
            ),
          ],
        );
      },
    );

    if (action == null) return;
    switch (action) {
      case _AccountMessageAction.sms:
        await _openSms(phone: phone, message: message);
        break;
      case _AccountMessageAction.whatsapp:
        await _openWhatsApp(phone: whatsapp, message: message);
        break;
    }
  }

  Future<void> _copyPreparedMessage({
    required String message,
    required String fallbackMessage,
  }) async {
    await Clipboard.setData(ClipboardData(text: message));
    _message(fallbackMessage);
  }

  Future<void> _openCellCalculator({
    required CustomsRecord record,
    required _TableColumn column,
    required String displayValue,
  }) async {
    await _openNumericCellEditor(
      record: record,
      column: column,
      displayValue: displayValue,
    );
  }

  Future<void> _openNumericCellEditor({
    required CustomsRecord record,
    required _TableColumn column,
    required String displayValue,
  }) async {
    final parsedValue = double.tryParse(displayValue.replaceAll(',', ''));
    final initialValue =
        parsedValue == null || parsedValue == 0 ? null : parsedValue;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => _NumericAmountDialog(
        title: column.label,
        initialValue: initialValue,
      ),
    );

    if (result == null) return;
    await _applyFinancialCellValue(
        record: record, column: column, value: result);
  }

  Future<void> _applyFinancialCellValue({
    required CustomsRecord record,
    required _TableColumn column,
    required double value,
  }) async {
    if (value < 0) {
      _message('لا يمكن حفظ مبلغ أقل من صفر.');
      return;
    }

    try {
      switch (column) {
        case _TableColumn.customsAmount:
          await _customsRepository.updateCustomsRecordInline(
            record: record,
            customsAmount: value,
          );
          _message('تم تحديث مبلغ الجمارك.');
          break;
        case _TableColumn.clearanceFee:
          await _customsRepository.updateCustomsRecordInline(
            record: record,
            clearanceFee: value,
          );
          _message('تم تحديث رسوم التخليص.');
          break;
        case _TableColumn.driverAdvance:
          await _customsRepository.updateCustomsRecordInline(
            record: record,
            driverAdvance: value,
          );
          _message('تم تحديث سلفة السائق.');
          break;
        case _TableColumn.unitPrice:
          if (value <= 0) {
            _message('سعر الوحدة يجب أن يكون أكبر من صفر.');
            return;
          }
          await _customsRepository.updateCustomsRecordInline(
            record: record,
            unitPrice: value,
          );
          _message('تم تحديث سعر الوحدة.');
          break;
        case _TableColumn.paidAmount:
          if (value <= 0) {
            _message('مبلغ السداد يجب أن يكون أكبر من صفر.');
            return;
          }
          await _customsRepository.addPaymentForRecordId(
            customsRecordId: record.id,
            amount: value,
            note: 'دفعة من الإدخال الرقمي',
          );
          _message('تم حفظ السداد عبر سجل السداد.');
          break;
        case _TableColumn.date:
        case _TableColumn.agent:
        case _TableColumn.driver:
        case _TableColumn.plate:
        case _TableColumn.quantity:
        case _TableColumn.unit:
        case _TableColumn.merchant:
        case _TableColumn.balance:
        case _TableColumn.status:
        case _TableColumn.actions:
          return;
      }

      await refreshFromDatabase();
      widget.onChanged?.call();
    } catch (error) {
      _message(error.toString());
    }
  }

  void _scheduleCellCalculator({
    required CustomsRecord record,
    required _TableColumn column,
    required String displayValue,
  }) {
    final ignoreUntil = _ignoreSingleTapUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
      return;
    }

    _singleTapTimer?.cancel();
    _singleTapTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      final ignoreUntil = _ignoreSingleTapUntil;
      if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
        return;
      }
      _openNumericCellEditor(
        record: record,
        column: column,
        displayValue: displayValue,
      );
    });
  }

  void _cancelPendingSingleTap() {
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
    _ignoreSingleTapUntil = DateTime.now().add(
      const Duration(milliseconds: 350),
    );
  }

  Future<void> _addRadiologyFee(CustomsRecord record) async {
    const fee = 10000.0;
    final oldCustomsAmount = record.customsAmount;

    try {
      final newCustomsAmount = await _customsRepository.addRadiologyFeeToRecord(
        record.id,
        amount: fee,
      );
      if (newCustomsAmount == null) {
        _message('تم إضافة مبلغ الأشعة لهذه الحركة مسبقاً.');
        return;
      }

      debugPrint(
        'recordId=${record.id}, oldCustomsAmount=$oldCustomsAmount, '
        'newCustomsAmount=$newCustomsAmount, addedRadiologyFee=10000',
      );
      _message('تمت إضافة رسوم الأشعة.');
      await refreshFromDatabase();
      widget.onChanged?.call();
    } catch (error) {
      _message(error.toString());
    }
  }

  bool _isUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _showColumnsDialog() async {
    final result = await showDialog<Set<_TableColumn>>(
      context: context,
      builder: (context) {
        final selected = {..._visibleColumns};

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('الأعمدة'),
              content: SizedBox(
                width: 360,
                child: ListView(
                  shrinkWrap: true,
                  children: _TableColumn.values.map((column) {
                    return CheckboxListTile(
                      value: selected.contains(column),
                      title: Text(column.label),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(column);
                          } else {
                            selected.remove(column);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, selected),
                  child: const Text('تطبيق'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() {
      _visibleColumns
        ..clear()
        ..addAll(result);
    });
    await _saveVisibleColumns();
  }

  Future<void> _handleExportAction(_ExportAction action) async {
    if (_visibleRows.isEmpty) {
      _message('لا توجد صفوف ظاهرة للتصدير');
      return;
    }

    try {
      switch (action) {
        case _ExportAction.excel:
          final path = await _exportService.exportExcel(
            _buildExportData(title: 'كشف الجدول الذكي', rows: _visibleRows),
          );
          _message('تم تصدير Excel: $path');
        case _ExportAction.pdf:
          final path = await _exportService.exportPdf(
            _buildExportData(title: 'كشف الجدول الذكي', rows: _visibleRows),
          );
          _message('تم تصدير PDF: $path');
        case _ExportAction.print:
          await _exportService.printPdf(
            _buildExportData(title: 'كشف الجدول الذكي', rows: _visibleRows),
          );
        case _ExportAction.agentStatement:
          await _printStatementByAgent();
        case _ExportAction.merchantStatement:
          await _printStatementByMerchant();
      }
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _printStatementByAgent() async {
    final agents = _visibleRows
        .map((row) => row.record.agentName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final agentName = await _chooseValueDialog(
      title: 'كشف وكيل',
      label: 'اختر الوكيل',
      values: agents,
    );
    if (agentName == null) return;

    final records = _visibleRows
        .map((row) => row.record)
        .where((record) => record.agentName.trim() == agentName)
        .toList();

    await _exportService.printPdf(
      _buildExportData(
        title: 'كشف وكيل: $agentName',
        rows: _rowsWithRunningBalance(records),
      ),
    );
  }

  Future<void> _printStatementByMerchant() async {
    final merchants = _visibleRows
        .map((row) => row.record.beneficiaryMerchant?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final merchantName = await _chooseValueDialog(
      title: 'كشف تاجر',
      label: 'اختر التاجر',
      values: merchants,
    );
    if (merchantName == null) return;

    final records = _visibleRows
        .map((row) => row.record)
        .where((record) => record.beneficiaryMerchant?.trim() == merchantName)
        .toList();

    await _exportService.printPdf(
      _buildExportData(
        title: 'كشف تاجر: $merchantName',
        rows: _rowsWithRunningBalance(records),
      ),
    );
  }

  Future<String?> _chooseValueDialog({
    required String title,
    required String label,
    required List<String> values,
  }) {
    if (values.isEmpty) {
      _message('لا توجد بيانات متاحة');
      return Future.value();
    }

    var selectedValue = values.first;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selectedValue,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            items: values.map((value) {
              return DropdownMenuItem(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) return;
              selectedValue = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selectedValue),
              child: const Text('عرض'),
            ),
          ],
        );
      },
    );
  }

  SmartTableExportData _buildExportData({
    required String title,
    required List<_TableRowModel> rows,
    bool includeRowNumber = false,
    bool excludeActionsColumn = false,
  }) {
    final totalCustoms = rows.fold(
      0.0,
      (sum, row) => sum + _recordGrandTotal(row.record),
    );
    final totalPaid = rows.fold(
      0.0,
      (sum, row) => sum + row.record.paidAmount,
    );
    final finalBalance = rows.fold(
      0.0,
      (sum, row) => sum + _recordBalance(row.record),
    );

    final exportColumns = _visibleColumns
        .where(
          (column) => !excludeActionsColumn || column != _TableColumn.actions,
        )
        .toList();
    final columns = [
      if (includeRowNumber)
        const SmartTableExportColumn(
          id: 'row_number',
          label: 'رقم الصف',
        ),
      ...exportColumns.map((column) => SmartTableExportColumn(
            id: column.name,
            label: column.label,
          )),
    ];

    return SmartTableExportData(
      title: title,
      generatedAtLabel: _dateTime(DateTime.now()),
      periodLabel: _dateFilter.label,
      filterLabel: _filter.label,
      sortLabel: _sort.label,
      totalCustoms: totalCustoms,
      totalPaid: totalPaid,
      finalBalance: finalBalance,
      columns: columns,
      rows: rows.map((row) {
        return SmartTableExportRow(
          cells: {
            if (includeRowNumber) 'row_number': (row.index + 1).toString(),
            for (final column in exportColumns)
              column.name: _exportCellValue(column, row),
          },
        );
      }).toList(),
    );
  }

  String _exportCellValue(_TableColumn column, _TableRowModel row) {
    final record = row.record;

    return switch (column) {
      _TableColumn.date => _date(record.createdAt),
      _TableColumn.agent => record.agentName,
      _TableColumn.driver => record.driverName,
      _TableColumn.plate => record.plateNumber,
      _TableColumn.quantity => _number(record.quantity),
      _TableColumn.unit => record.pricingUnit ?? '-',
      _TableColumn.unitPrice => _nullableMoney(record.unitPrice),
      _TableColumn.customsAmount => _money(record.customsAmount),
      _TableColumn.clearanceFee => _money(record.clearanceFee),
      _TableColumn.driverAdvance => _money(record.driverAdvance),
      _TableColumn.merchant => record.beneficiaryMerchant ?? '-',
      _TableColumn.paidAmount => _money(record.paidAmount),
      _TableColumn.balance => _money(row.runningBalance),
      _TableColumn.status => row.status.label,
      _TableColumn.actions => '',
    };
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _filters(List<CustomsRecord> records, {bool compact = false}) {
    final dateRecords = _recordsForDate(records);
    final agents = _agents(dateRecords);
    final merchants = _merchants(dateRecords);

    if (_filter == _TableFilter.byAgent &&
        _selectedAgent != null &&
        !agents.contains(_selectedAgent)) {
      _selectedAgent = null;
    }
    if (_filter == _TableFilter.byMerchant &&
        _selectedMerchant != null &&
        !merchants.contains(_selectedMerchant)) {
      _selectedMerchant = null;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final fieldWidth = compact
            ? availableWidth.clamp(220.0, 340.0).toDouble()
            : availableWidth < 1000
                ? 200.0
                : 220.0;
        final searchWidth = compact
            ? availableWidth.clamp(220.0, 340.0).toDouble()
            : availableWidth < 1000
                ? 280.0
                : 320.0;
        final dateWidth = compact ? fieldWidth : 170.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!compact)
                  FilledButton.icon(
                    onPressed: _addQuickRecord,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة عملية'),
                  ),
                SizedBox(
                  width: dateWidth,
                  child: DropdownButtonFormField<_DateFilter>(
                    isExpanded: true,
                    initialValue: _dateFilter,
                    decoration: const InputDecoration(
                      labelText: 'الفترة',
                      border: OutlineInputBorder(),
                    ),
                    items: _DateFilter.values.map((filter) {
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(filter.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _dateFilter = value;
                      });
                      _settingsRepository.saveDateFilter(value.name);
                    },
                  ),
                ),
                SizedBox(
                  width: searchWidth,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'بحث سريع',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<_TableFilter>(
                    isExpanded: true,
                    initialValue: _filter,
                    decoration: const InputDecoration(
                      labelText: 'فلتر',
                      border: OutlineInputBorder(),
                    ),
                    items: _TableFilter.values.map((filter) {
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(filter.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _filter = value;
                      });
                      _settingsRepository.saveStatusFilter(value.name);
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<_TableSort>(
                    isExpanded: true,
                    initialValue: _sort,
                    decoration: const InputDecoration(
                      labelText: 'ترتيب',
                      border: OutlineInputBorder(),
                    ),
                    items: _TableSort.values.map((sort) {
                      return DropdownMenuItem(
                        value: sort,
                        child: Text(sort.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _sort = value;
                      });
                      _settingsRepository.saveSort(value.name);
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showColumnsDialog,
                  icon: const Icon(Icons.view_column_outlined),
                  label: const Text('الأعمدة'),
                ),
                OutlinedButton.icon(
                  onPressed: _showAllRecords,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('إظهار الكل'),
                ),
                if (!compact)
                  PopupMenuButton<_ExportAction>(
                    tooltip: 'تصدير / طباعة',
                    onSelected: _handleExportAction,
                    itemBuilder: (context) {
                      return _ExportAction.values.map((action) {
                        return PopupMenuItem(
                          value: action,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(action.icon, size: 20),
                              const SizedBox(width: 8),
                              Text(action.label),
                            ],
                          ),
                        );
                      }).toList();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.ios_share_outlined, size: 20),
                          SizedBox(width: 8),
                          Text('تصدير / طباعة'),
                        ],
                      ),
                    ),
                  ),
                if (!compact)
                  FilterChip(
                    selected: _groupByAgent,
                    label: const Text('تجميع حسب الوكيل'),
                    avatar: const Icon(Icons.account_tree_outlined, size: 18),
                    onSelected: (value) {
                      setState(() {
                        _groupByAgent = value;
                      });
                      _settingsRepository.saveGroupByAgent(value);
                    },
                  ),
                if (!compact)
                  IconButton.outlined(
                    tooltip: 'تحديث',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                OutlinedButton(
                  onPressed: _resetTableZoom,
                  child: const Text('100%'),
                ),
                if (!compact)
                  IconButton.outlined(
                    tooltip: 'ملء الشاشة',
                    onPressed: _openFullscreenTable,
                    icon: const Icon(Icons.fullscreen),
                  ),
              ],
            ),
            if (_filter == _TableFilter.byAgent) ...[
              const SizedBox(height: 8),
              _valueDropdown(
                label: 'اختر الوكيل',
                value: _selectedAgent,
                values: agents,
                width: compact ? searchWidth : 320,
                onChanged: (value) => setState(() => _selectedAgent = value),
              ),
            ],
            if (_filter == _TableFilter.byMerchant) ...[
              const SizedBox(height: 8),
              _valueDropdown(
                label: 'اختر التاجر',
                value: _selectedMerchant,
                values: merchants,
                width: compact ? searchWidth : 320,
                onChanged: (value) => setState(() => _selectedMerchant = value),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _valueDropdown({
    required String label,
    required String? value,
    required List<String> values,
    required double width,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: values.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(item),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  _VisibleSummary _calculateVisibleSummary(List<_TableRowModel> rows) {
    final agents = <String>{};
    final merchants = <String>{};
    var totalCustomsAndClearance = 0.0;
    var totalRadiology = 0.0;
    var totalDriverAdvance = 0.0;
    var totalGrand = 0.0;
    var totalPaid = 0.0;
    var missingPricingCount = 0;
    var missingMerchantCount = 0;
    var unpaidCount = 0;
    var creditCount = 0;

    for (final row in rows) {
      final record = row.record;
      final merchantName = record.beneficiaryMerchant?.trim();
      final grandTotal = _recordGrandTotal(record);

      totalCustomsAndClearance += _customsAndClearanceAmount(record);
      totalRadiology += _radiologyAmount(record);
      totalDriverAdvance += record.driverAdvance;
      totalGrand += grandTotal;
      totalPaid += record.paidAmount;
      agents.add(record.agentName.trim());

      if (merchantName != null && merchantName.isNotEmpty) {
        merchants.add(merchantName);
      }

      if (!_hasPricing(record)) missingPricingCount++;
      if (!_hasMerchant(record)) missingMerchantCount++;
      if (record.paidAmount <= 0.01 && grandTotal > 0.01) {
        unpaidCount++;
      }
      if (row.status == _RecordStatus.credit) creditCount++;
    }

    return _VisibleSummary(
      operationsCount: rows.length,
      totalCustomsAndClearance: totalCustomsAndClearance,
      totalRadiology: totalRadiology,
      totalDriverAdvance: totalDriverAdvance,
      totalGrand: totalGrand,
      totalPaid: totalPaid,
      finalBalance: rows.isEmpty ? 0 : rows.last.runningBalance,
      agentsCount: agents.where((name) => name.isNotEmpty).length,
      merchantsCount: merchants.length,
      missingPricingCount: missingPricingCount,
      missingMerchantCount: missingMerchantCount,
      unpaidCount: unpaidCount,
      creditCount: creditCount,
    );
  }

  Widget _buildSummaryPanel(
    List<_TableRowModel> rows, {
    required bool compact,
    required bool medium,
    required double availableWidth,
  }) {
    if (rows.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('لا توجد بيانات ضمن الفلاتر الحالية'),
        ),
      );
    }

    final summary = _calculateVisibleSummary(rows);
    final balanceColor = summary.finalBalance > 0 ? Colors.red : Colors.blue;
    final cardWidth = compact
        ? ((availableWidth - 8) / 2).clamp(136.0, 190.0).toDouble()
        : medium
            ? ((availableWidth - 16) / 3).clamp(150.0, 180.0).toDouble()
            : 170.0;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildSummaryCard(
          width: cardWidth,
          title: 'عدد العمليات',
          value: summary.operationsCount.toString(),
          icon: Icons.table_rows_outlined,
          color: Colors.blueGrey,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'جمارك وتخليص',
          value: _money(summary.totalCustomsAndClearance),
          icon: Icons.account_balance_wallet_outlined,
          color: Colors.blue,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'إجمالي الأشعة',
          value: _money(summary.totalRadiology),
          icon: Icons.medical_services_outlined,
          color: Colors.deepPurple,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'سلف السائقين',
          value: _money(summary.totalDriverAdvance),
          icon: Icons.person_pin_circle_outlined,
          color: Colors.brown,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'إجمالي المبلغ',
          value: _money(summary.totalGrand),
          icon: Icons.summarize_outlined,
          color: Colors.cyan.shade700,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'إجمالي السداد',
          value: _money(summary.totalPaid),
          icon: Icons.payments_outlined,
          color: Colors.green,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'الرصيد النهائي',
          value: _money(summary.finalBalance),
          icon: Icons.balance_outlined,
          color: balanceColor,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'عدد الوكلاء',
          value: summary.agentsCount.toString(),
          icon: Icons.badge_outlined,
          color: Colors.indigo,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'عدد التجار',
          value: summary.merchantsCount.toString(),
          icon: Icons.storefront_outlined,
          color: Colors.teal,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'ناقص تسعير',
          value: summary.missingPricingCount.toString(),
          icon: Icons.price_change_outlined,
          color: Colors.amber.shade700,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'ناقص تاجر',
          value: summary.missingMerchantCount.toString(),
          icon: Icons.person_off_outlined,
          color: Colors.deepOrange,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'غير مسدد',
          value: summary.unpaidCount.toString(),
          icon: Icons.money_off_outlined,
          color: Colors.red,
        ),
        _buildSummaryCard(
          width: cardWidth,
          title: 'دائن / دفع زيادة',
          value: summary.creditCount.toString(),
          icon: Icons.trending_down_outlined,
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required double width,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: color.withAlpha(28),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyRowsState(List<CustomsRecord> allRecords) {
    final hasRecords = allRecords.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasRecords
                  ? Icons.filter_alt_off_outlined
                  : Icons.table_rows_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              hasRecords
                  ? 'لا توجد نتائج حسب الفلاتر الحالية'
                  : 'لا توجد عمليات تخليص',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (hasRecords) ...[
              const SizedBox(height: 8),
              Text(
                'توجد عمليات في قاعدة البيانات، لكن الفترة أو البحث أو فلتر الحالة يخفيها.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _showAllRecords,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('إظهار الكل'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _table(List<_TableRowModel> rows) {
    if (rows.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.table_rows_outlined),
          title: Text('لا توجد عمليات مطابقة'),
        ),
      );
    }

    if (_groupByAgent) {
      final grouped = _groupRowsByAgent(rows);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: grouped.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: Theme.of(context).colorScheme.primary.withAlpha(20),
                child: Text(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              _plainTable(entry.value),
            ],
          );
        }).toList(),
      );
    }

    return _plainTable(rows);
  }

  void _resetTableZoom() {
    _tableTransformationController.value = Matrix4.identity();
  }

  // ignore: unused_element
  Widget _zoomableTable(List<_TableRowModel> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveWidth =
            _visibleTableWidth().clamp(constraints.maxWidth, double.infinity);

        return ClipRect(
          child: InteractiveViewer(
            transformationController: _tableTransformationController,
            minScale: 0.7,
            maxScale: 2.0,
            boundaryMargin: const EdgeInsets.all(200),
            constrained: false,
            panEnabled: true,
            panAxis: PanAxis.horizontal,
            scaleEnabled: true,
            child: Align(
              alignment: Alignment.topRight,
              widthFactor: 1,
              heightFactor: 1,
              child: SizedBox(
                width: effectiveWidth.toDouble(),
                child: _table(rows),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tableViewport({
    required List<_TableRowModel> rows,
    required List<CustomsRecord> records,
  }) {
    return Expanded(
      child: rows.isEmpty
          ? SingleChildScrollView(
              controller: _scrollController,
              child: _emptyRowsState(records),
            )
          : Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.vertical,
                primary: false,
                child: _scrollableTableContent(rows),
              ),
            ),
    );
  }

  Widget _tableViewportBox({
    required List<_TableRowModel> rows,
    required List<CustomsRecord> records,
    required double height,
  }) {
    return SizedBox(
      height: height,
      child: rows.isEmpty
          ? SingleChildScrollView(
              controller: _scrollController,
              child: _emptyRowsState(records),
            )
          : Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.vertical,
                primary: false,
                child: _scrollableTableContent(rows),
              ),
            ),
    );
  }

  Widget _scrollableTableContent(List<_TableRowModel> rows) {
    return _table(rows);
  }

  Widget _plainTable(List<_TableRowModel> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveWidth =
            _visibleTableWidth().clamp(constraints.maxWidth, double.infinity);

        return SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: effectiveWidth.toDouble(),
              child: DataTable(
                border: TableBorder.all(
                  color: Theme.of(context).dividerColor.withAlpha(150),
                  width: 0.7,
                ),
                columnSpacing: 14,
                horizontalMargin: 8,
                headingRowHeight: 38,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 42,
                dividerThickness: 0.7,
                headingRowColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.primary.withAlpha(35),
                ),
                columns: [
                  DataColumn(label: _rowNumberHeader()),
                  ..._visibleColumns.map(
                    (column) => DataColumn(
                      label: _columnHeader(column),
                    ),
                  ),
                ],
                rows: rows.map((row) {
                  final record = row.record;
                  final isSelected = record.id == _selectedRecordId;
                  void rowLongPress() => _showRowLongPressMenu(row);
                  return DataRow(
                    onLongPress: () => _showRowLongPressMenu(row),
                    color: WidgetStateProperty.resolveWith((states) {
                      final baseColor = row.status.backgroundColor;
                      if (isSelected) {
                        return Color.alphaBlend(
                          Theme.of(context).colorScheme.primary.withAlpha(70),
                          baseColor,
                        );
                      }

                      return baseColor;
                    }),
                    cells: [
                      DataCell(
                        _rowContextMenuRegion(
                          row: row,
                          child: _rowNumberCell(row),
                        ),
                        onTap: () => _selectRow(row),
                        onLongPress: rowLongPress,
                      ),
                      ..._visibleColumns.map((column) {
                        switch (column) {
                          case _TableColumn.date:
                            final value = _date(record.createdAt);
                            return DataCell(
                              _rowContextMenuRegion(
                                row: row,
                                child: _sizedCell(column, _cellText(value)),
                              ),
                              onLongPress: rowLongPress,
                              onDoubleTap: () => _showCellActionSheet(
                                record: record,
                                fieldKey: column.name,
                                displayValue: value,
                                editable: false,
                              ),
                            );
                          case _TableColumn.agent:
                            return _editableDataCell(
                              record,
                              column,
                              record.agentName,
                              onTap: () => _openAgent(record),
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                              isLink: true,
                            );
                          case _TableColumn.driver:
                            return _editableDataCell(
                              record,
                              column,
                              record.driverName,
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                            );
                          case _TableColumn.plate:
                            return _editableDataCell(
                              record,
                              column,
                              record.plateNumber,
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                            );
                          case _TableColumn.quantity:
                            return _editableDataCell(
                              record,
                              column,
                              _number(record.quantity),
                              numeric: true,
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                            );
                          case _TableColumn.unit:
                            return _editableDataCell(
                              record,
                              column,
                              record.pricingUnit ?? '',
                              placeholder: '-',
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                            );
                          case _TableColumn.unitPrice:
                            return _editableDataCell(
                              record,
                              column,
                              record.unitPrice == null
                                  ? ''
                                  : _number(record.unitPrice!),
                              placeholder: _nullableMoney(record.unitPrice),
                              numeric: true,
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                            );
                          case _TableColumn.customsAmount:
                            final value = _money(record.customsAmount);
                            return _editableDataCell(
                              record,
                              column,
                              value,
                              numeric: true,
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                            );
                          case _TableColumn.clearanceFee:
                            final value = _money(record.clearanceFee);
                            return _editableDataCell(
                              record,
                              column,
                              value,
                              numeric: true,
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                            );
                          case _TableColumn.driverAdvance:
                            final value = _money(record.driverAdvance);
                            return _editableDataCell(
                              record,
                              column,
                              value,
                              numeric: true,
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                            );
                          case _TableColumn.merchant:
                            final merchantName =
                                record.beneficiaryMerchant?.trim();
                            return _editableDataCell(
                              record,
                              column,
                              merchantName ?? '',
                              placeholder:
                                  merchantName == null || merchantName.isEmpty
                                      ? '-'
                                      : merchantName,
                              onTap:
                                  merchantName == null || merchantName.isEmpty
                                      ? null
                                      : () => _openMerchant(record),
                              onLongPress: rowLongPress,
                              contextMenuRow: row,
                              isLink: merchantName != null &&
                                  merchantName.isNotEmpty,
                            );
                          case _TableColumn.paidAmount:
                            final value = _money(record.paidAmount);
                            return DataCell(
                              _rowContextMenuRegion(
                                row: row,
                                child: _sizedCell(
                                  column,
                                  _linkText(
                                    value,
                                    numeric: true,
                                  ),
                                ),
                              ),
                              onTap: () => _scheduleCellCalculator(
                                record: record,
                                column: column,
                                displayValue: value,
                              ),
                              onLongPress: rowLongPress,
                              onDoubleTap: () {
                                _cancelPendingSingleTap();
                                _showCellActionSheet(
                                  record: record,
                                  fieldKey: column.name,
                                  displayValue: value,
                                  editable: false,
                                );
                              },
                            );
                          case _TableColumn.balance:
                            final value = _money(row.runningBalance);
                            return DataCell(
                              _rowContextMenuRegion(
                                row: row,
                                child: _sizedCell(
                                  column,
                                  _numberText(
                                    value,
                                    color: row.runningBalance < 0
                                        ? Colors.green
                                        : Colors.red,
                                    bold: true,
                                  ),
                                ),
                              ),
                              onLongPress: rowLongPress,
                              onDoubleTap: () => _showCellActionSheet(
                                record: record,
                                fieldKey: column.name,
                                displayValue: value,
                                editable: false,
                              ),
                            );
                          case _TableColumn.status:
                            return DataCell(
                              _rowContextMenuRegion(
                                row: row,
                                child: _sizedCell(
                                  column,
                                  _StatusChip(status: row.status),
                                ),
                              ),
                              onLongPress: rowLongPress,
                              onDoubleTap: () => _showCellActionSheet(
                                record: record,
                                fieldKey: column.name,
                                displayValue: row.status.label,
                                editable: false,
                              ),
                            );
                          case _TableColumn.actions:
                            return DataCell(
                              _rowContextMenuRegion(
                                row: row,
                                child: _sizedCell(column, _actions(record)),
                              ),
                              onLongPress: rowLongPress,
                            );
                        }
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _columnHeader(_TableColumn column) {
    return SizedBox(
      width: _columnWidth(column),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Center(
              child: Text(
                column.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  _resizeColumn(column, details.delta.dx);
                },
                child: Container(
                  width: 12,
                  alignment: Alignment.center,
                  child: Container(
                    width: 3,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withAlpha(120),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sizedCell(_TableColumn column, Widget child) {
    return SizedBox(
      width: _columnWidth(column),
      child: child,
    );
  }

  Widget _rowNumberHeader() {
    return const SizedBox(
      width: _rowNumberColumnWidth,
      child: Center(
        child: Text(
          'م',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _rowNumberCell(_TableRowModel row) {
    return SizedBox(
      width: _rowNumberColumnWidth,
      child: Center(
        child: Text(
          (row.index + 1).toString(),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  DataCell _editableDataCell(
    CustomsRecord record,
    _TableColumn column,
    String value, {
    String? placeholder,
    bool numeric = false,
    bool isLink = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    _TableRowModel? contextMenuRow,
  }) {
    if (_editingRecord?.id == record.id && _editingColumn == column) {
      final child = _sizedCell(
        column,
        _inlineEditor(record, column, numeric: numeric),
      );
      return DataCell(
        contextMenuRow == null
            ? child
            : _rowContextMenuRegion(row: contextMenuRow, child: child),
        onLongPress: onLongPress,
      );
    }

    final child = _sizedCell(
      column,
      _editableText(
        placeholder ?? value,
        numeric: numeric,
        isLink: isLink,
      ),
    );

    return DataCell(
      contextMenuRow == null
          ? child
          : _rowContextMenuRegion(row: contextMenuRow, child: child),
      onTap: onTap ??
          (_isCalculatorColumn(column)
              ? () => _scheduleCellCalculator(
                    record: record,
                    column: column,
                    displayValue: value,
                  )
              : null),
      onLongPress: onLongPress,
      onDoubleTap: () {
        _cancelPendingSingleTap();
        if (_isCalculatorColumn(column)) {
          _showCellActionSheet(
            record: record,
            fieldKey: column.name,
            displayValue: value,
            editable: _isInlineEditable(column),
          );
          return;
        }

        _showCellActionSheet(
          record: record,
          fieldKey: column.name,
          displayValue: value,
          editable: _isInlineEditable(column),
        );
      },
    );
  }

  bool _isInlineEditable(_TableColumn column) {
    return switch (column) {
      _TableColumn.agent ||
      _TableColumn.driver ||
      _TableColumn.plate ||
      _TableColumn.quantity ||
      _TableColumn.unit ||
      _TableColumn.unitPrice ||
      _TableColumn.customsAmount ||
      _TableColumn.clearanceFee ||
      _TableColumn.driverAdvance ||
      _TableColumn.merchant =>
        true,
      _TableColumn.date ||
      _TableColumn.paidAmount ||
      _TableColumn.balance ||
      _TableColumn.status ||
      _TableColumn.actions =>
        false,
    };
  }

  Widget _inlineEditor(
    CustomsRecord record,
    _TableColumn column, {
    bool numeric = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _cancelInlineEdit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _inlineEditController,
          focusNode: _inlineEditFocusNode,
          autofocus: true,
          textAlign: numeric ? TextAlign.center : TextAlign.right,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          onSubmitted: (_) => _submitInlineEdit(record, column),
          onTapOutside: (_) => _inlineEditFocusNode.unfocus(),
        ),
      ),
    );
  }

  Widget _editableText(
    String value, {
    bool numeric = false,
    bool isLink = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = isLink ? colorScheme.primary : null;

    return Align(
      alignment: numeric ? Alignment.center : Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(45),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value.isEmpty ? '-' : value,
                textAlign: numeric ? TextAlign.center : TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  decoration: isLink ? TextDecoration.underline : null,
                  fontWeight: isLink ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.edit_outlined,
              size: 12,
              color: colorScheme.onSurfaceVariant.withAlpha(150),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions(CustomsRecord record) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'فتح الوكيل',
            onPressed: () => _openAgent(record),
            icon: const Icon(Icons.badge_outlined),
          ),
          IconButton(
            tooltip: 'فتح التاجر',
            onPressed:
                _hasMerchant(record) ? () => _openMerchant(record) : null,
            icon: const Icon(Icons.storefront_outlined),
          ),
          IconButton(
            tooltip: 'سجل الدفعات',
            onPressed: () => _editPayment(record),
            icon: const Icon(Icons.payments_outlined),
          ),
          IconButton(
            tooltip: 'تسعير',
            onPressed: () => _editPricing(record),
            icon: const Icon(Icons.price_change_outlined),
          ),
          IconButton(
            tooltip: _hasMerchant(record) ? 'فتح التاجر' : 'إضافة التاجر',
            onPressed: () => _editMerchant(record),
            icon: const Icon(Icons.person_add_alt_outlined),
          ),
          IconButton(
            tooltip: 'توزيع كمية',
            onPressed: () => _splitQuantity(record),
            icon: const Icon(Icons.call_split_outlined),
          ),
          IconButton(
            tooltip: 'تعديل',
            onPressed: () => _editRecord(record),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'حذف',
            onPressed: () => _deleteRecord(record),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _cellText(String value, {TextAlign textAlign = TextAlign.center}) {
    return Align(
      alignment: textAlign == TextAlign.right
          ? Alignment.centerRight
          : Alignment.center,
      child: Text(
        value,
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _numberText(String value, {Color? color, bool bold = false}) {
    return Align(
      alignment: Alignment.center,
      child: Text(
        value,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _linkText(String value, {bool numeric = false}) {
    return Align(
      alignment: numeric ? Alignment.center : Alignment.centerRight,
      child: Text(
        value,
        textAlign: numeric ? TextAlign.center : TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _rowNavigatorPanel(List<_TableRowModel> rows) {
    final selectedIndex = _selectedRowIndex;
    if (selectedIndex == null || rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final canGoPrevious = selectedIndex > 0;
    final canGoNext = selectedIndex < rows.length - 1;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        elevation: 12,
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withAlpha(160),
                ),
              ),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                Text(
                  'رقم الصف: ${selectedIndex + 1} من ${rows.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(
                  width: 92,
                  child: TextField(
                    controller: _jumpController,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'انقل إلى',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _moveSelectedRowToTypedNumber(),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'نقل',
                  onPressed: _moveSelectedRowToTypedNumber,
                  icon: const Icon(Icons.drive_file_move_outline),
                ),
                IconButton.outlined(
                  tooltip: 'إلى الأول',
                  onPressed:
                      rows.isEmpty ? null : () => _goToVisibleRowIndex(0),
                  icon: const Icon(Icons.keyboard_double_arrow_up),
                ),
                IconButton.outlined(
                  tooltip: 'السابق',
                  onPressed: canGoPrevious
                      ? () => _goToVisibleRowIndex(selectedIndex - 1)
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton.outlined(
                  tooltip: 'التالي',
                  onPressed: canGoNext
                      ? () => _goToVisibleRowIndex(selectedIndex + 1)
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton.outlined(
                  tooltip: 'إلى الأخير',
                  onPressed: rows.isEmpty
                      ? null
                      : () => _goToVisibleRowIndex(rows.length - 1),
                  icon: const Icon(Icons.keyboard_double_arrow_down),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: _closeRowNavigator,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: widget._isFullscreen
          ? Scaffold(
              appBar: AppBar(
                title: const Text('الجدول الذكي'),
                actions: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showFullscreenSummary = !_showFullscreenSummary;
                      });
                    },
                    icon: Icon(
                      _showFullscreenSummary
                          ? Icons.visibility_off_outlined
                          : Icons.summarize_outlined,
                    ),
                    label: const Text('الملخص'),
                  ),
                  IconButton(
                    tooltip: '100%',
                    onPressed: _resetTableZoom,
                    icon: const Icon(Icons.fit_screen_outlined),
                  ),
                  IconButton(
                    tooltip: 'خروج من ملء الشاشة',
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                ],
              ),
              body: _recordsBuilder(
                forceCompactToolbar: true,
                showSummary: _showFullscreenSummary,
              ),
            )
          : _recordsBuilder(
              showSummary: true,
            ),
    );
  }

  Widget _recordsBuilder({
    bool forceCompactToolbar = false,
    required bool showSummary,
  }) {
    return FutureBuilder<List<CustomsRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data ?? [];
        final visibleRecords = _visibleRecords(records);
        _debugRowsPipeline(records, visibleRecords);
        _scheduleShowAllIfFiltersHideRecords(records, visibleRecords);
        final rows = _rowsWithRunningBalance(visibleRecords);
        _syncSelectionWithRows(rows);

        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final medium =
                  constraints.maxWidth >= 600 && constraints.maxWidth < 1000;
              final compactToolbar = forceCompactToolbar || compact;
              final verticalGap = compact ? 8.0 : 10.0;
              final bottomPadding = _selectedRecordId == null ? 12.0 : 128.0;
              final scrollTopArea = compact || constraints.maxHeight < 620;

              return Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      compact ? 8 : 12,
                      12,
                      bottomPadding,
                    ),
                    child: scrollTopArea
                        ? _compactRecordsLayout(
                            constraints: constraints,
                            records: records,
                            rows: rows,
                            compactToolbar: compactToolbar,
                            showSummary: showSummary,
                            verticalGap: verticalGap,
                          )
                        : _wideRecordsLayout(
                            records: records,
                            rows: rows,
                            compact: compact,
                            medium: medium,
                            compactToolbar: compactToolbar,
                            showSummary: showSummary,
                            verticalGap: verticalGap,
                            availableWidth: constraints.maxWidth,
                          ),
                  ),
                  if (_selectedRecordId != null) _rowNavigatorPanel(rows),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _compactRecordsLayout({
    required BoxConstraints constraints,
    required List<CustomsRecord> records,
    required List<_TableRowModel> rows,
    required bool compactToolbar,
    required bool showSummary,
    required double verticalGap,
  }) {
    final minTableHeight =
        constraints.maxHeight < 260 ? constraints.maxHeight : 260.0;
    final tableHeight = (constraints.maxHeight * 0.58)
        .clamp(minTableHeight, constraints.maxHeight)
        .toDouble();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _filters(records, compact: compactToolbar),
        ),
        if (showSummary) ...[
          SliverToBoxAdapter(child: SizedBox(height: verticalGap)),
          SliverToBoxAdapter(
            child: _buildSummaryPanel(
              rows,
              compact: true,
              medium: false,
              availableWidth: constraints.maxWidth - 24,
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: verticalGap)),
        SliverToBoxAdapter(
          child: _tableViewportBox(
            rows: rows,
            records: records,
            height: tableHeight,
          ),
        ),
      ],
    );
  }

  Widget _wideRecordsLayout({
    required List<CustomsRecord> records,
    required List<_TableRowModel> rows,
    required bool compact,
    required bool medium,
    required bool compactToolbar,
    required bool showSummary,
    required double verticalGap,
    required double availableWidth,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filters(records, compact: compactToolbar),
        if (showSummary) ...[
          SizedBox(height: verticalGap),
          _buildSummaryPanel(
            rows,
            compact: compact,
            medium: medium,
            availableWidth: availableWidth - 24,
          ),
        ],
        SizedBox(height: verticalGap),
        _tableViewport(rows: rows, records: records),
      ],
    );
  }

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String _date(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  static String _dateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  static String _money(double value) => value.toStringAsFixed(2);

  static String _messageMoney(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  static String _nullableMoney(double? value) {
    if (value == null) return '-';
    return _money(value);
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class _QuickRecordDialog extends StatefulWidget {
  const _QuickRecordDialog();

  @override
  State<_QuickRecordDialog> createState() => _QuickRecordDialogState();
}

class _QuickRecordDialogState extends State<_QuickRecordDialog> {
  final _agentController = TextEditingController();
  final _driverController = TextEditingController();
  final _plateController = TextEditingController();
  final _quantityController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _agentController.dispose();
    _driverController.dispose();
    _plateController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    final agentName = _agentController.text.trim();
    final driverName = _driverController.text.trim();
    final plateNumber = _plateController.text.trim();
    final quantity = double.tryParse(
      _quantityController.text.trim().replaceAll(',', ''),
    );

    if (agentName.isEmpty || driverName.isEmpty || plateNumber.isEmpty) {
      setState(() => _error = 'أدخل اسم الوكيل والسائق ورقم اللوحة');
      return;
    }

    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'أدخل كمية صحيحة أكبر من صفر');
      return;
    }

    Navigator.pop(
      context,
      _QuickRecordInput(
        agentName: agentName,
        driverName: driverName,
        plateNumber: plateNumber,
        quantity: quantity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة عملية'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _agentController,
              autofocus: true,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'اسم الوكيل',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _driverController,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'اسم السائق',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _plateController,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'رقم اللوحة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'الكمية',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('حفظ واعتماد'),
        ),
      ],
    );
  }
}

class _QuickRecordInput {
  const _QuickRecordInput({
    required this.agentName,
    required this.driverName,
    required this.plateNumber,
    required this.quantity,
  });

  final String agentName;
  final String driverName;
  final String plateNumber;
  final double quantity;
}

class _EditRecordDialog extends StatefulWidget {
  const _EditRecordDialog({required this.record});

  final CustomsRecord record;

  @override
  State<_EditRecordDialog> createState() => _EditRecordDialogState();
}

class _EditRecordDialogState extends State<_EditRecordDialog> {
  late final TextEditingController _agentController;
  late final TextEditingController _driverController;
  late final TextEditingController _plateController;
  late final TextEditingController _quantityController;
  late final TextEditingController _unitController;
  late final TextEditingController _unitPriceController;
  late final TextEditingController _clearanceFeeController;
  late final TextEditingController _driverAdvanceController;
  late final TextEditingController _merchantController;
  late final TextEditingController _noteController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _agentController = TextEditingController(text: record.agentName);
    _driverController = TextEditingController(text: record.driverName);
    _plateController = TextEditingController(text: record.plateNumber);
    _quantityController = TextEditingController(text: _number(record.quantity));
    _unitController = TextEditingController(text: record.pricingUnit ?? '');
    _unitPriceController = TextEditingController(
      text: record.unitPrice == null ? '' : _number(record.unitPrice!),
    );
    _clearanceFeeController =
        TextEditingController(text: _number(record.clearanceFee));
    _driverAdvanceController =
        TextEditingController(text: _number(record.driverAdvance));
    _merchantController = TextEditingController(
      text: record.beneficiaryMerchant ?? '',
    );
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _agentController.dispose();
    _driverController.dispose();
    _plateController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _unitPriceController.dispose();
    _clearanceFeeController.dispose();
    _driverAdvanceController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final agentName = _agentController.text.trim();
    final driverName = _driverController.text.trim();
    final plateNumber = _plateController.text.trim();
    final quantity = double.tryParse(
      _quantityController.text.trim().replaceAll(',', ''),
    );
    final unit = _unitController.text.trim();
    final unitPriceText = _unitPriceController.text.trim().replaceAll(',', '');
    final unitPrice =
        unitPriceText.isEmpty ? null : double.tryParse(unitPriceText);
    final clearanceFee = double.tryParse(
      _clearanceFeeController.text.trim().replaceAll(',', ''),
    );
    final driverAdvance = double.tryParse(
      _driverAdvanceController.text.trim().replaceAll(',', ''),
    );
    final merchantName = _merchantController.text.trim();

    if (agentName.isEmpty || driverName.isEmpty || plateNumber.isEmpty) {
      setState(() => _error = 'أدخل اسم الوكيل والسائق ورقم اللوحة');
      return;
    }

    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'أدخل كمية صحيحة أكبر من صفر');
      return;
    }

    if (unitPriceText.isNotEmpty && (unitPrice == null || unitPrice < 0)) {
      setState(() => _error = 'أدخل سعر وحدة صحيح');
      return;
    }

    if (clearanceFee == null || clearanceFee < 0) {
      setState(() => _error = 'أدخل رسوم تخليص صحيحة');
      return;
    }

    if (driverAdvance == null || driverAdvance < 0) {
      setState(() => _error = 'أدخل سلفة سائق صحيحة');
      return;
    }

    Navigator.pop(
      context,
      _EditRecordInput(
        agentName: agentName,
        driverName: driverName,
        plateNumber: plateNumber,
        quantity: quantity,
        unit: unit.isEmpty ? null : unit,
        unitPrice: unitPrice,
        clearanceFee: clearanceFee,
        driverAdvance: driverAdvance,
        merchantName: merchantName.isEmpty ? null : merchantName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل العملية'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_agentController, 'اسم الوكيل', autofocus: true),
              const SizedBox(height: 12),
              _field(_driverController, 'اسم السائق'),
              const SizedBox(height: 12),
              _field(_plateController, 'رقم اللوحة'),
              const SizedBox(height: 12),
              _field(_quantityController, 'الكمية', number: true),
              const SizedBox(height: 12),
              _field(_unitController, 'الوحدة'),
              const SizedBox(height: 12),
              _field(_unitPriceController, 'سعر الوحدة', number: true),
              const SizedBox(height: 12),
              _field(_clearanceFeeController, 'رسوم التخليص', number: true),
              const SizedBox(height: 12),
              _field(_driverAdvanceController, 'سلفة السائق', number: true),
              const SizedBox(height: 12),
              _field(_merchantController, 'اسم التاجر'),
              const SizedBox(height: 12),
              _field(_noteController, 'ملاحظة اختيارية'),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool autofocus = false,
    bool number = false,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textDirection: TextDirection.rtl,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class _EditRecordInput {
  const _EditRecordInput({
    required this.agentName,
    required this.driverName,
    required this.plateNumber,
    required this.quantity,
    this.unit,
    this.unitPrice,
    required this.clearanceFee,
    required this.driverAdvance,
    this.merchantName,
  });

  final String agentName;
  final String driverName;
  final String plateNumber;
  final double quantity;
  final String? unit;
  final double? unitPrice;
  final double clearanceFee;
  final double driverAdvance;
  final String? merchantName;
}

class _NumericAmountDialog extends StatefulWidget {
  const _NumericAmountDialog({
    required this.title,
    required this.initialValue,
  });

  final String title;
  final double? initialValue;

  @override
  State<_NumericAmountDialog> createState() => _NumericAmountDialogState();
}

class _NumericAmountDialogState extends State<_NumericAmountDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue == null
          ? ''
          : _formatNumber(widget.initialValue!),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  Future<void> _openCalculator() async {
    final current = double.tryParse(_controller.text.replaceAll(',', ''));
    final calculatorInitialValue =
        current == null || current == 0 ? null : current;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => _CalculatorDialog(
        initialValue: calculatorInitialValue,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _controller.text = _formatNumber(result);
      _error = null;
    });
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim().replaceAll(',', ''));
    if (value == null || value < 0) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً غير سالب');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _controller,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            errorText: _error,
            suffixIcon: IconButton(
              tooltip: 'آلة حاسبة',
              onPressed: _openCalculator,
              icon: const Icon(Icons.calculate_outlined),
            ),
          ),
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _CalculatorDialog extends StatefulWidget {
  const _CalculatorDialog({required this.initialValue});

  final double? initialValue;

  @override
  State<_CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<_CalculatorDialog> {
  late String _expression;
  String? _error;
  bool _justCalculated = false;

  @override
  void initState() {
    super.initState();
    _expression =
        widget.initialValue == null ? '' : _formatNumber(widget.initialValue!);
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  bool _isDigit(String value) => RegExp(r'^\d$').hasMatch(value);

  bool _isOperator(String value) => '+-*/'.contains(value);

  String _currentNumber() {
    final match = RegExp(r'[-+]?\d*\.?\d*$').firstMatch(_expression);
    return match?.group(0) ?? '';
  }

  void _append(String value) {
    setState(() {
      if (_justCalculated && (_isDigit(value) || value == '.')) {
        _expression = value == '.' ? '0.' : value;
      } else if (_isDigit(value)) {
        if (_expression == '0') {
          _expression = value;
        } else if (_expression == '-0') {
          _expression = '-$value';
        } else {
          _expression += value;
        }
      } else if (value == '.') {
        if (_expression.isEmpty ||
            _isOperator(_expression[_expression.length - 1])) {
          _expression += '0.';
        } else if (!_currentNumber().contains('.')) {
          _expression += value;
        }
      } else if (_isOperator(value)) {
        if (_expression.isEmpty) {
          _expression = value == '-' ? '-' : '0$value';
        } else if (_isOperator(_expression[_expression.length - 1])) {
          _expression =
              _expression.substring(0, _expression.length - 1) + value;
        } else {
          _expression += value;
        }
      } else {
        _expression += value;
      }
      _justCalculated = false;
      _error = null;
    });
  }

  void _clear() {
    setState(() {
      _expression = '0';
      _justCalculated = false;
      _error = null;
    });
  }

  void _backspace() {
    setState(() {
      if (_justCalculated || _expression.length <= 1) {
        _expression = '0';
      } else {
        _expression = _expression.substring(0, _expression.length - 1);
        if (_expression.isEmpty || _expression == '-') {
          _expression = '0';
        }
      }
      _justCalculated = false;
      _error = null;
    });
  }

  double? _calculate() {
    try {
      final result = _ExpressionParser(_expression).parse();
      if (result.isNaN || result.isInfinite) {
        throw const FormatException();
      }
      setState(() {
        _expression = _formatNumber(result);
        _justCalculated = true;
        _error = null;
      });
      return result;
    } catch (_) {
      setState(() {
        _error = 'عملية حسابية غير صحيحة';
      });
      return null;
    }
  }

  void _save() {
    final result = _calculate();
    if (result == null) return;
    Navigator.pop(context, result);
  }

  Widget _key(String label, {VoidCallback? onPressed, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: onPressed ?? () => _append(label),
            child: Text(
              label,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) {
    return Row(children: children);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('آلة حاسبة'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: TextEditingController(text: _expression)
                  ..selection = TextSelection.collapsed(
                    offset: _expression.length,
                  ),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onChanged: (value) {
                  _expression = value.isEmpty ? '0' : value;
                  _justCalculated = false;
                },
              ),
              const SizedBox(height: 10),
              _row([
                _key('C', onPressed: _clear),
                _key('⌫', onPressed: _backspace),
                _key('('),
                _key(')'),
              ]),
              _row([_key('7'), _key('8'), _key('9'), _key('/')]),
              _row([_key('4'), _key('5'), _key('6'), _key('*')]),
              _row([_key('1'), _key('2'), _key('3'), _key('-')]),
              _row([
                _key('0'),
                _key('.'),
                _key('=', onPressed: _calculate),
                _key('+')
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _ExpressionParser {
  _ExpressionParser(String source)
      : _source = source
            .replaceAll(',', '')
            .replaceAll('أ—', '*')
            .replaceAll('÷', '/');

  final String _source;
  int _index = 0;

  double parse() {
    final value = _parseExpression();
    _skipWhitespace();
    if (_index != _source.length) {
      throw const FormatException();
    }
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipWhitespace();
      if (_match('+')) {
        value += _parseTerm();
      } else if (_match('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipWhitespace();
      if (_match('*')) {
        value *= _parseFactor();
      } else if (_match('/')) {
        final divisor = _parseFactor();
        if (divisor == 0) throw const FormatException();
        value /= divisor;
      } else {
        return value;
      }
    }
  }

  double _parseFactor() {
    _skipWhitespace();
    if (_match('+')) return _parseFactor();
    if (_match('-')) return -_parseFactor();

    if (_match('(')) {
      final value = _parseExpression();
      if (!_match(')')) throw const FormatException();
      return value;
    }

    return _parseNumber();
  }

  double _parseNumber() {
    _skipWhitespace();
    final start = _index;
    var hasDigit = false;
    var hasDot = false;

    while (_index < _source.length) {
      final char = _source[_index];
      if (_isDigit(char)) {
        hasDigit = true;
        _index++;
      } else if (char == '.' && !hasDot) {
        hasDot = true;
        _index++;
      } else {
        break;
      }
    }

    if (!hasDigit) throw const FormatException();
    return double.parse(_source.substring(start, _index));
  }

  bool _match(String char) {
    _skipWhitespace();
    if (_index >= _source.length || _source[_index] != char) return false;
    _index++;
    return true;
  }

  void _skipWhitespace() {
    while (_index < _source.length && _source[_index].trim().isEmpty) {
      _index++;
    }
  }

  bool _isDigit(String char) {
    return char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;
  }
}

class _AccountSummary {
  const _AccountSummary({
    required this.accountType,
    required this.name,
    required this.records,
    required this.totalCustoms,
    required this.totalPaid,
    required this.balance,
  });

  final String accountType;
  final String name;
  final List<CustomsRecord> records;
  final double totalCustoms;
  final double totalPaid;
  final double balance;
}

class _TableRowModel {
  const _TableRowModel({
    required this.index,
    required this.record,
    required this.runningBalance,
    required this.status,
  });

  final int index;
  final CustomsRecord record;
  final double runningBalance;
  final _RecordStatus status;
}

class _SmartTableViewState {
  const _SmartTableViewState({
    required this.searchText,
    required this.dateFilter,
    required this.filter,
    required this.sort,
    required this.selectedAgent,
    required this.selectedMerchant,
    required this.groupByAgent,
    required this.visibleColumns,
    required this.columnWidths,
  });

  final String searchText;
  final _DateFilter dateFilter;
  final _TableFilter filter;
  final _TableSort sort;
  final String? selectedAgent;
  final String? selectedMerchant;
  final bool groupByAgent;
  final Set<_TableColumn> visibleColumns;
  final Map<_TableColumn, double> columnWidths;
}

class _VisibleSummary {
  const _VisibleSummary({
    required this.operationsCount,
    required this.totalCustomsAndClearance,
    required this.totalRadiology,
    required this.totalDriverAdvance,
    required this.totalGrand,
    required this.totalPaid,
    required this.finalBalance,
    required this.agentsCount,
    required this.merchantsCount,
    required this.missingPricingCount,
    required this.missingMerchantCount,
    required this.unpaidCount,
    required this.creditCount,
  });

  final int operationsCount;
  final double totalCustomsAndClearance;
  final double totalRadiology;
  final double totalDriverAdvance;
  final double totalGrand;
  final double totalPaid;
  final double finalBalance;
  final int agentsCount;
  final int merchantsCount;
  final int missingPricingCount;
  final int missingMerchantCount;
  final int unpaidCount;
  final int creditCount;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _RecordStatus status;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(status.label),
      backgroundColor: status.color.withAlpha(30),
      labelStyle: TextStyle(
        color: status.color,
        fontWeight: FontWeight.bold,
      ),
      side: BorderSide(color: status.color.withAlpha(80)),
    );
  }
}

class _AccountContactDialog extends StatefulWidget {
  const _AccountContactDialog({
    required this.accountType,
    required this.accountName,
    required this.contact,
    required this.repository,
  });

  final String accountType;
  final String accountName;
  final AccountContact? contact;
  final CustomsRepository repository;

  @override
  State<_AccountContactDialog> createState() => _AccountContactDialogState();
}

class _AccountContactDialogState extends State<_AccountContactDialog> {
  late final TextEditingController _phoneController;
  late final TextEditingController _whatsappController;
  late final TextEditingController _notesController;
  late final FocusNode _phoneFocus;
  late final FocusNode _whatsappFocus;
  late final FocusNode _notesFocus;

  late bool _whatsappSameAsPhone;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    _phoneController = TextEditingController(text: contact?.phone ?? '');
    _whatsappController = TextEditingController(text: contact?.whatsapp ?? '');
    _notesController = TextEditingController(text: contact?.notes ?? '');
    _phoneFocus = FocusNode();
    _whatsappFocus = FocusNode();
    _notesFocus = FocusNode();
    _whatsappSameAsPhone = contact?.whatsappSameAsPhone ?? true;
    if (_whatsappSameAsPhone) {
      _whatsappController.text = _phoneController.text;
    }
    _phoneController.addListener(_syncWhatsappWithPhone);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_syncWhatsappWithPhone);
    _phoneController.dispose();
    _whatsappController.dispose();
    _notesController.dispose();
    _phoneFocus.dispose();
    _whatsappFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _syncWhatsappWithPhone() {
    if (!_whatsappSameAsPhone) return;
    if (_whatsappController.text == _phoneController.text) return;
    _whatsappController.text = _phoneController.text;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(Duration.zero);

    try {
      await widget.repository.saveAccountContact(
        accountType: widget.accountType,
        accountName: widget.accountName,
        phone: _phoneController.text,
        whatsapp: _whatsappSameAsPhone
            ? _phoneController.text
            : _whatsappController.text,
        whatsappSameAsPhone: _whatsappSameAsPhone,
        notes: _notesController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('بيانات الاتصال: ${widget.accountName}'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.accountName),
                subtitle: Text(
                  widget.accountType == 'merchant' ? 'تاجر' : 'وكيل',
                ),
              ),
              TextField(
                controller: _phoneController,
                focusNode: _phoneFocus,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _whatsappSameAsPhone,
                title: const Text('واتساب نفس رقم الهاتف'),
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _whatsappSameAsPhone = value ?? true;
                          if (_whatsappSameAsPhone) {
                            _whatsappController.text = _phoneController.text;
                          }
                        });
                      },
              ),
              TextField(
                controller: _whatsappController,
                focusNode: _whatsappFocus,
                enabled: !_whatsappSameAsPhone && !_isSaving,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم واتساب',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                focusNode: _notesFocus,
                enabled: !_isSaving,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

enum _TableFilter {
  all('الكل'),
  missingPricing('ناقص تسعير'),
  missingMerchant('ناقص تاجر'),
  unpaid('غير مسدد'),
  paid('مسدد'),
  credit('دائن'),
  byAgent('حسب الوكيل'),
  byMerchant('حسب التاجر');

  const _TableFilter(this.label);

  final String label;
}

enum _DateFilter {
  today('اليوم'),
  yesterday('أمس'),
  allDays('كل الأيام');

  const _DateFilter(this.label);

  final String label;
}

enum _TableSort {
  manual('ترتيب يدوي'),
  newest('التاريخ الأحدث'),
  oldest('التاريخ الأقدم'),
  agent('اسم الوكيل'),
  merchant('اسم التاجر'),
  balanceDesc('الرصيد الأكبر');

  const _TableSort(this.label);

  final String label;
}

enum _TableColumn {
  date('التاريخ'),
  agent('الوكيل'),
  driver('السائق'),
  plate('اللوحة'),
  quantity('الكمية'),
  unit('الوحدة'),
  unitPrice('سعر الوحدة'),
  customsAmount('مبلغ الجمارك'),
  clearanceFee('رسوم التخليص'),
  driverAdvance('سلفة السائق'),
  merchant('التاجر'),
  paidAmount('مبلغ السداد'),
  balance('الرصيد'),
  status('الحالة'),
  actions('إجراءات');

  const _TableColumn(this.label);

  final String label;

  double get defaultWidth {
    return switch (this) {
      _TableColumn.date => 105,
      _TableColumn.agent => 170,
      _TableColumn.driver => 140,
      _TableColumn.plate => 110,
      _TableColumn.quantity => 90,
      _TableColumn.unit => 100,
      _TableColumn.unitPrice => 115,
      _TableColumn.customsAmount => 130,
      _TableColumn.clearanceFee => 125,
      _TableColumn.driverAdvance => 125,
      _TableColumn.merchant => 155,
      _TableColumn.paidAmount => 125,
      _TableColumn.balance => 125,
      _TableColumn.status => 130,
      _TableColumn.actions => 280,
    };
  }
}

enum _CellAction {
  paste,
  copy,
  edit,
  accountActions,
  radiology,
  calculator,
  selectAll,
  share,
  sms,
  whatsapp,
  openInBrowser,
  delete,
}

enum _RowAction {
  move,
  copy,
  info,
  delete,
  exportExcel,
  exportPdf,
  print,
  cancel,
}

enum _RowExportAction {
  excel,
  pdf,
  print,
}

class _RowMenuEntry {
  const _RowMenuEntry.action({
    required this.action,
    required this.icon,
    required this.label,
    this.destructive = false,
  }) : isDivider = false;

  const _RowMenuEntry.header({
    required this.icon,
    required this.label,
  })  : action = null,
        destructive = false,
        isDivider = false;

  const _RowMenuEntry.divider()
      : action = null,
        icon = null,
        label = '',
        destructive = false,
        isDivider = true;

  final _RowAction? action;
  final IconData? icon;
  final String label;
  final bool destructive;
  final bool isDivider;
}

enum _AccountAction {
  advancedSearch,
  thermalPrint,
  share,
  excel,
  sms,
  whatsapp,
  smsAndWhatsapp,
  whatsappConfirmation,
  closeBalance,
  transfer,
  alerts,
  creditLimit,
  contactInfo,
}

enum _AccountMessageAction {
  sms,
  whatsapp,
}

enum _ExportAction {
  excel('Excel', Icons.table_chart_outlined),
  pdf('PDF', Icons.picture_as_pdf_outlined),
  print('طباعة', Icons.print_outlined),
  agentStatement('كشف وكيل', Icons.badge_outlined),
  merchantStatement('كشف تاجر', Icons.storefront_outlined);

  const _ExportAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _RecordStatus {
  missingPricing('ناقص تسعير', Colors.orange),
  missingMerchant('ناقص تاجر', Colors.deepOrange),
  unpaid('غير مسدد', Colors.red),
  partial('مسدد جزئي', Colors.blue),
  paid('مسدد كامل', Colors.green),
  credit('دائن / دفع زيادة', Colors.teal);

  const _RecordStatus(this.label, this.color);

  final String label;
  final Color color;

  Color get backgroundColor {
    return switch (this) {
      _RecordStatus.missingPricing => Colors.yellow.withAlpha(35),
      _RecordStatus.missingMerchant => Colors.orange.withAlpha(35),
      _RecordStatus.unpaid => Colors.red.withAlpha(28),
      _RecordStatus.partial => Colors.blue.withAlpha(24),
      _RecordStatus.paid => Colors.green.withAlpha(28),
      _RecordStatus.credit => Colors.purple.withAlpha(28),
    };
  }
}
