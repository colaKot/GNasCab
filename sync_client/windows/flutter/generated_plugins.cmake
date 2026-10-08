#
# Generated file, do not edit.
#
# 本文件由 `flutter pub get` 自动生成。
# 首次构建前请先执行一次 `flutter pub get`，工具会把本项目实际用到的插件
# （file_selector_windows / screen_retriever_windows / sqlite3_flutter_libs /
#  tray_manager / window_manager）自动填进下面的列表。
#
# 这里刻意留空：若沿用主客户端的插件列表，CMake 会因为找不到对应的
# flutter/ephemeral/.plugin_symlinks/<plugin> 目录而直接报错。
#

list(APPEND FLUTTER_PLUGIN_LIST
)

list(APPEND FLUTTER_FFI_PLUGIN_LIST
)

set(PLUGIN_BUNDLED_LIBRARIES)

foreach(plugin ${FLUTTER_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${plugin}/windows plugins/${plugin})
  target_link_libraries(${BINARY_NAME} PRIVATE ${plugin}_plugin)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES $<TARGET_FILE:${plugin}_plugin>)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${${plugin}_bundled_libraries})
endforeach(plugin)

foreach(ffi_plugin ${FLUTTER_FFI_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${ffi_plugin}/windows plugins/${ffi_plugin})
  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${${ffi_plugin}_bundled_libraries})
endforeach(ffi_plugin)
