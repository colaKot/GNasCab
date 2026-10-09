import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:GNasCab/modules/auth/service/auth_api_service.dart';

class CustomUserFormController extends GetxController {
  final Map<String, dynamic>? user;
  final Future<bool> Function(
    String username,
    String password, {
    String? userRemark,
    String? phone,
  })
  onCreate;
  final Future<bool> Function(
    int id, {
    String? username,
    String? password,
    String? userRemark,
    String? phone,
  })
  onUpdate;

  final usernameController = TextEditingController().obs;
  final passwordController = TextEditingController().obs;
  final phoneController = TextEditingController().obs;
  final remarkController = TextEditingController().obs;

  CustomUserFormController({
    this.user,
    required this.onCreate,
    required this.onUpdate,
  });

  @override
  void onInit() {
    super.onInit();
    if (user != null) {
      usernameController.value.text = user!['username'] ?? '';
      phoneController.value.text = (user!['phone'] as String?) ?? '';
      remarkController.value.text = (user!['user_remark'] as String?) ?? '';
    }
  }

  String? validateUsername(String? v) {
    return (v == null || v.isEmpty) ? 'input_please'.tr : null;
  }

  /// 子账号密码不做强度校验（与服务端 /user/create、/user/update 规则保持一致）：
  /// 密码强度要求只对超级管理员账号生效，普通子账号可以是简单密码、也可以多个账号用同一个密码。
  /// 新建时仅要求非空；编辑时留空表示不修改密码。
  String? validatePassword(String? v) {
    final isEdit = user != null;
    if (isEdit && (v == null || v.isEmpty)) {
      return null;
    }
    return ((v == null || v.isEmpty) ? 'input_please'.tr : null);
  }

  String? validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (v.trim().length > 32) return 'user_mgmt_field_length_invalid'.tr;
    return null;
  }

  String? validateRemark(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (v.trim().length > 500) return 'user_mgmt_field_length_invalid'.tr;
    return null;
  }

  Future<void> submitForm() async {
    final username = usernameController.value.text.trim();
    final password = passwordController.value.text.trim();
    final phone = phoneController.value.text.trim();
    final remark = remarkController.value.text.trim();

    bool ok = false;
    if (user != null) {
      ok = await onUpdate(
        user!['id'] as int,
        username: username,
        password: password.isEmpty
            ? null
            : AuthApiService.obfuscatePassword(password),
        userRemark: remark,
        phone: phone,
      );
    } else {
      ok = await onCreate(
        username,
        password,
        userRemark: remark.isEmpty ? null : remark,
        phone: phone.isEmpty ? null : phone,
      );
    }
    if (ok) {
      Navigator.pop(Get.context!, true);
    }
  }
}
