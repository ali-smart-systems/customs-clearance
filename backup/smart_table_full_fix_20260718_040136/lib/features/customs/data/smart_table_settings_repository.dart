import 'package:shared_preferences/shared_preferences.dart';

class SmartTableSettingsRepository {
  static const _visibleColumnsKey = 'smart_table.visible_columns';
  static const _dateFilterKey = 'smart_table.date_filter';
  static const _statusFilterKey = 'smart_table.status_filter';
  static const _sortKey = 'smart_table.sort';
  static const _groupByAgentKey = 'smart_table.group_by_agent';
  static const _columnWidthsKey = 'smart_table.column_widths';

  Future<SmartTableSettings> load() async {
    final preferences = await SharedPreferences.getInstance();

    return SmartTableSettings(
      visibleColumns: preferences.getStringList(_visibleColumnsKey),
      dateFilter: preferences.getString(_dateFilterKey),
      statusFilter: preferences.getString(_statusFilterKey),
      sort: preferences.getString(_sortKey),
      groupByAgent: preferences.getBool(_groupByAgentKey),
      columnWidths: preferences.getStringList(_columnWidthsKey),
    );
  }

  Future<void> saveVisibleColumns(List<String> columns) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_visibleColumnsKey, columns);
  }

  Future<void> saveDateFilter(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_dateFilterKey, value);
  }

  Future<void> saveStatusFilter(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_statusFilterKey, value);
  }

  Future<void> saveSort(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sortKey, value);
  }

  Future<void> saveGroupByAgent(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_groupByAgentKey, value);
  }

  Future<void> saveColumnWidths(Map<String, double> widths) async {
    final preferences = await SharedPreferences.getInstance();
    final values = widths.entries
        .map((entry) => '${entry.key}:${entry.value.toStringAsFixed(1)}')
        .toList();
    await preferences.setStringList(_columnWidthsKey, values);
  }
}

class SmartTableSettings {
  const SmartTableSettings({
    this.visibleColumns,
    this.dateFilter,
    this.statusFilter,
    this.sort,
    this.groupByAgent,
    this.columnWidths,
  });

  final List<String>? visibleColumns;
  final String? dateFilter;
  final String? statusFilter;
  final String? sort;
  final bool? groupByAgent;
  final List<String>? columnWidths;
}
