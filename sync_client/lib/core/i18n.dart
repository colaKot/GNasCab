import 'package:get/get.dart';

/// 极简多语言：独立同步客户端面向 Windows 中文用户，只内置简体中文。
///
/// 刻意保留 `.tr` 的调用方式，这样同步引擎的代码可以与主客户端保持一致，
/// 后续做多语言时只需把 [_zh] 扩展成多份 map 即可。
class SyncTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {'zh_CN': _zh};
}

const Map<String, String> _zh = {
  // ── 通用 ──
  'app_name': 'WaterNasOS 同步',
  'ok': '确定',
  'cancel': '取消',
  'save': '保存',
  'delete': '删除',
  'edit': '编辑',
  'retry': '重试',
  'close': '关闭',
  'refresh': '刷新',
  'loading': '加载中…',
  'tip': '提示',
  'network_failure': '网络请求失败，请检查与服务器的连接',
  'operation_failed': '操作失败',
  'all': '全部',

  // ── 登录 ──
  'login': '登录',
  'login_subtitle': '登录后即可同步电脑与 NAS 上的目录',
  'server_address': '服务器地址',
  'server_address_hint': '例如 http://192.168.1.100:8080',
  'username': '账号',
  'password': '密码',
  'server_address_required': '请输入服务器地址',
  'username_required': '请输入账号',
  'password_required': '请输入密码',
  'login_failed': '登录失败',
  'logging_in': '正在登录…',
  'logout': '退出登录',
  'logout_confirm': '确定要退出登录吗？退出后自动同步会停止。',
  'session_expired': '登录已过期，请重新登录',

  // ── 任务列表 ──
  'sync_task_count': '共 @count 个同步任务',
  'sync_no_tasks': '还没有同步任务',
  'sync_no_tasks_desc': '点击下面的按钮创建第一个同步任务',
  'sync_create_task': '新建同步任务',
  'sync_edit_task': '编辑同步任务',
  'sync_delete_confirm': '确定删除该同步任务吗？只删除任务配置，电脑与 NAS 上的文件都会保留。',
  'sync_start_now': '立即同步',
  'sync_stop': '停止',
  'sync_stopping': '正在停止…',
  'sync_records': '同步记录',
  'sync_no_records': '暂无同步记录',
  'sync_last_sync': '上次同步',
  'sync_never_synced': '从未同步',

  // ── 任务编辑 ──
  'sync_task_name': '任务名称',
  'sync_task_name_hint': '例如：工作文档',
  'sync_task_name_required': '请输入任务名称',
  'sync_local_dir': '电脑目录',
  'sync_remote_dir': 'NAS 目录',
  'sync_local_dir_required': '请选择电脑目录',
  'sync_remote_dir_required': '请选择 NAS 目录',
  'sync_dir_same': '电脑目录与 NAS 目录不能相同',
  'sync_pick_local_failed': '选择本地目录失败',
  'sync_pick_remote': '选择 NAS 目录',
  'sync_mode': '同步模式',

  'sync_mode_bidirectional': '双向同步',
  'sync_mode_bidirectional_desc': '两边互相补齐，任一端的改动都会同步到另一端',
  'sync_mode_download_only': '仅下载',
  'sync_mode_download_only_desc': '只把 NAS 上的文件同步到电脑，电脑上的改动不会上传',
  'sync_mode_upload_only': '仅上传',
  'sync_mode_upload_only_desc': '只把电脑上的文件同步到 NAS，NAS 上的改动不会下载',

  'sync_rules': '同步规则',
  'sync_realtime': '按需同步',
  'sync_realtime_desc': '电脑目录有改动时自动触发同步',
  'sync_interval': '定时同步',
  'sync_interval_hint': '设为 0 表示不定时，只靠按需同步或手动同步',
  'sync_minutes': '分钟',
  'sync_manual_only': '仅手动同步',
  'sync_interval_every': '每 @minutes 分钟',
  'sync_delete_extra': '传播删除',
  'sync_delete_extra_hint': '一端删除文件时，另一端也一并删除（仅双向同步生效，请谨慎开启）',
  'sync_conflict_strategy': '冲突处理',
  'sync_conflict_prefer_newer': '保留较新的文件',
  'sync_conflict_prefer_local': '保留电脑上的文件',
  'sync_conflict_prefer_remote': '保留 NAS 上的文件',

  // ── 过滤规则 ──
  'sync_filter': '过滤规则',
  'sync_filter_hidden': '排除隐藏文件',
  'sync_filter_hidden_desc': '以 . 开头的文件与文件夹',
  'sync_filter_small': '排除小文件',
  'sync_filter_large': '排除大文件',
  'sync_filter_ext': '排除文件类型',
  'sync_filter_ext_hint': '英文逗号分隔，例如 lnk,pst,swp',

  // ── 状态 ──
  'sync_status_idle': '空闲',
  'sync_status_running': '同步中',
  'sync_status_paused': '已暂停',
  'sync_status_error': '出错',

  'sync_phase_scanning': '正在扫描本地文件',
  'sync_phase_planning': '正在比对两端差异',
  'sync_phase_transferring': '正在传输文件',
  'sync_phase_cleaning': '正在清理多余文件',
  'sync_phase_reporting': '正在回写结果',
  'sync_phase_done': '同步完成',
  'sync_phase_failed': '同步失败',

  // ── 同步引擎（key 与主客户端保持一致） ──
  'sync_already_running': '该任务正在同步中',
  'sync_up_to_date': '两端已一致，无需同步',
  'sync_completed': '同步完成',
  'sync_cancelled': '同步已取消',
  'sync_plan_failed': '获取同步计划失败',
  'sync_delete_remote_failed': '删除 NAS 上的文件失败',
  'sync_remote_not_directory': '选中的 NAS 路径不是文件夹',
  'sync_remote_no_permission': '没有访问该 NAS 路径的权限',
  'sync_task_required': '请先补全任务信息',

  // ── 同步结果 ──
  'sync_result_line': '上传 @up，下载 @down，删除 @del，跳过 @skip，失败 @fail',
  'sync_upload': '上传',
  'sync_download': '下载',
  'sync_delete': '删除',
  'sync_skip': '跳过',
  'sync_fail': '失败',
  'sync_bytes': '传输量',
  'sync_record_success': '同步成功',
  'sync_record_failed': '同步失败',
  'sync_record_stopped': '已停止',

  // ── 设置 ──
  'settings': '设置',
  'settings_general': '通用',
  'settings_account': '账号',
  'settings_server': '服务器',
  'settings_about': '关于',
  'settings_version': '版本',
  'auto_start': '开机自动启动',
  'auto_start_desc': '开机后自动在托盘运行并开始同步',
  'auto_start_failed': '设置开机自启失败',
  'sync_paused_all': '已暂停全部自动同步',
  'sync_resumed_all': '已恢复自动同步',
  'current_account': '当前账号',

  // ── 托盘 ──
  'tray_show_main_window': '显示主界面',
  'tray_sync_now': '立即同步全部',
  'tray_pause_auto': '暂停自动同步',
  'tray_resume_auto': '恢复自动同步',
  'tray_settings': '设置',
  'tray_exit_app': '退出',
  'tray_running_hint': 'WaterNasOS 同步正在后台运行',
};
