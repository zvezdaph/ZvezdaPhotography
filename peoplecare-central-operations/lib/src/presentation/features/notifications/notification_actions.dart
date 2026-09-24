import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/navigation_controller.dart';
import '../operators/operator_detail_panel.dart';
import '../service_detail/service_detail_panel.dart';

/// Apre ciò a cui si riferisce una notifica e la segna come letta.
void openNotificationTarget(
  BuildContext context,
  AppNotification notification,
) {
  final deps = context.deps;
  if (!notification.isRead) {
    unawaited(
      deps.notifications.markRead(notification.id).catchError((Object _) {}),
    );
  }
  switch (notification.type) {
    case NotificationType.richiestaModifica:
      deps.navigation.go(
        AppSection.changeRequests,
        intent: ChangeRequestIntent(
          changeRequestId: notification.changeRequestId,
        ),
      );
    case NotificationType.documentoRicevuto:
      final serviceId = notification.serviceId;
      if (serviceId != null) {
        unawaited(
          showServiceDetail(
            context,
            serviceId,
            initialTab: ServiceDetailTab.documenti,
          ),
        );
      } else {
        deps.navigation.go(
          AppSection.documents,
          intent: const DocumentsIntent(pendingReviewOnly: true),
        );
      }
    default:
      final serviceId = notification.serviceId;
      final operatorId = notification.operatorId;
      if (serviceId != null) {
        unawaited(showServiceDetail(context, serviceId));
      } else if (operatorId != null) {
        unawaited(showOperatorDetail(context, operatorId));
      } else {
        deps.navigation.go(AppSection.notifications);
      }
  }
}
