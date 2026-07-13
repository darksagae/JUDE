import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:apex_retail_core/data/app_state.dart';
import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/theme.dart';
import 'package:apex_retail_core/utils/format.dart';

class AuditLogsView extends StatefulWidget {
  const AuditLogsView({super.key});
  @override
  State<AuditLogsView> createState() => _AuditLogsViewState();
}

class _AuditLogsViewState extends State<AuditLogsView> {
  final _search = TextEditingController();
  String _type = 'All';
  bool _refreshing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // `neutral` is for expected offline/no-connection states — this app is
  // designed to keep working without internet, so that isn't an error and
  // shouldn't be flagged red like one.
  void _msg(String text, {bool err = false, bool neutral = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor:
          err ? AppColors.rose : (neutral ? AppColors.amber600 : AppColors.emerald),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();
    setState(() => _refreshing = true);
    try {
      if (app.offlineMode) {
        _msg('Offline Mode: showing local audit trail.', neutral: true);
      } else {
        await app.triggerSync();
        _msg('Audit trail synced with the cloud.');
      }
    } catch (_) {
      _msg('No connection — showing local audit trail.', neutral: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _refreshBtn() => OutlinedButton.icon(
        onPressed: _refreshing ? null : _refresh,
        icon: _refreshing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh, size: 14),
        label: const Text('Pull Cloud Updates'),
      );

  Color _typeColor(String t) {
    switch (t) {
      case 'LOGIN':
        return const Color(0xFF7C3AED);
      case 'SALE':
        return AppColors.emerald;
      case 'STOCK_IN':
        return AppColors.amber600;
      case 'PRODUCT_UPDATE':
        return AppColors.indigo;
      case 'PRODUCT_CREATE':
        return const Color(0xFF059669);
      case 'PRODUCT_DELETE':
        return AppColors.rose;
      case 'CATEGORY_CREATE':
      case 'CATEGORY_UPDATE':
      case 'CATEGORY_DELETE':
        return const Color(0xFF7C3AED);
      case 'SYNC':
        return const Color(0xFF0284C7);
      default:
        return AppColors.slate600;
    }
  }

  /// Mirrors the Staff Directory hierarchy rule: a worker sees only their own
  /// actions, a manager sees everyone except the Top Manager (fellow managers
  /// included — hiding peer managers' edits was an oversight, not intended
  /// privacy), and the top manager sees everything.
  bool _visibleToRole(UserSession me, AuditLog l) {
    switch (me.role) {
      case UserRole.topManager:
        return true;
      case UserRole.manager:
        return l.userRole != UserRole.topManager;
      case UserRole.worker:
        return l.userId == me.userId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final authorized =
        app.auditLogs.where((l) => _visibleToRole(app.session, l)).toList();
    final types = <String>['All', ...{for (final l in authorized) l.actionType}];
    final term = _search.text.toLowerCase();
    final logs = authorized.where((l) {
      final matchS = l.userName.toLowerCase().contains(term) ||
          l.details.toLowerCase().contains(term);
      final matchT = _type == 'All' || l.actionType == _type;
      return matchS && matchT;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 560;
            final titleRow = Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.verified_user_outlined,
                    size: 18, color: AppColors.emerald),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Detailed Audit Ledger',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate800)),
                    Text('Deletions, edits, restocks and staff actions — workers see their own; managers see everyone except the top manager; the top manager sees everything',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.slate400)),
                  ],
                ),
              ),
              if (!narrow) ...[const SizedBox(width: 10), _refreshBtn()],
            ]);
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titleRow,
                  const SizedBox(height: 10),
                  _refreshBtn(),
                ],
              );
            }
            return titleRow;
          }),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search logs by staff name or details...',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: types.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final t = types[i];
                final active = _type == t;
                return GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? AppColors.slate900 : Colors.white,
                      border: Border.all(color: AppColors.slate200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: active ? Colors.white : AppColors.slate600)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (logs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                  child: Text('No actions logged under current criteria',
                      style: TextStyle(color: AppColors.slate400))),
            )
          else
            ...logs.map(_logRow),
        ],
      ),
    );
  }

  Widget _logRow(AuditLog log) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.slate100))),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 560;
        final badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: _typeColor(log.actionType).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6)),
          child: Text(log.actionType,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: _typeColor(log.actionType))),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fmtDateTime(log.timestamp),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.slate400)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(log.userName,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                badge,
              ]),
              const SizedBox(height: 4),
              Text(log.details,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.slate600)),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(fmtDateTime(log.timestamp),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.slate400)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(log.userName,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(log.userRole.wire.toUpperCase(),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: log.userRole == UserRole.topManager
                              ? AppColors.amber600
                              : log.userRole == UserRole.manager
                                  ? AppColors.indigo
                                  : AppColors.slate400)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            badge,
            const SizedBox(width: 10),
            Expanded(
              child: Text(log.details,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.slate600)),
            ),
          ],
        );
      }),
    );
  }
}
