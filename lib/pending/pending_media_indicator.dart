// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'package:flutter/material.dart';

import 'pending_media_page.dart';
import 'pending_media_retry_service.dart';
import 'pending_media_store.dart';

class PendingMediaIndicator extends StatelessWidget {
  const PendingMediaIndicator({
    super.key,
    required this.retryService,
  });

  final PendingMediaRetryService retryService;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PendingMediaStore.I.pendingCount,
      builder: (context, count, _) {
        return IconButton(
          tooltip: count > 0 ? 'Mídias pendentes: $count' : 'Sem mídias pendentes',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PendingMediaPage(retryService: retryService),
              ),
            );
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.cloud_upload_outlined),
              if (count > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}