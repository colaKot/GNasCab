import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/auth_theme_background.dart';
import 'admin_create_controller.dart';
import 'admin_create_view.dart';

/// 管理员创建视图
class AdminCreatePage extends GetView<AdminCreateController> {
  const AdminCreatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AdminCreateController>(
      init: AdminCreateController(),
      builder: (controller) {
        return _buildContent(context, controller);
      },
    );
  }

  Widget _buildContent(BuildContext context, AdminCreateController controller) {
    return Theme(
      data: Theme.of(context),
      child: Builder(
        builder: (context) {
          return Scaffold(
            body: Obx(
              () => AuthThemeBackground(
                child: _buildCenterView(context),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenterView(BuildContext context) {
    return AdminCreateView();
  }
}
