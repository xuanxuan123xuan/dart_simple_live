cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "desktop_webview_window")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "desktop_webview_window_plugin")
set(WEBKIT_BACKEND_NAME "desktop_webview_window_webkit")

find_package(PkgConfig REQUIRED)
pkg_check_modules(WebKit41 QUIET IMPORTED_TARGET webkit2gtk-4.1)
if (WebKit41_FOUND)
  set(WEBKIT_TARGET PkgConfig::WebKit41)
  pkg_check_modules(LibSoup REQUIRED IMPORTED_TARGET libsoup-3.0)
else()
  pkg_check_modules(WebKit40 REQUIRED IMPORTED_TARGET webkit2gtk-4.0)
  set(WEBKIT_TARGET PkgConfig::WebKit40)
  pkg_check_modules(LibSoup REQUIRED IMPORTED_TARGET libsoup-2.4)
endif()


add_library(${WEBKIT_BACKEND_NAME} SHARED
        desktop_webview_window_backend.cc
        desktop_webview_window_backend.h
        webview_window.cc
        webview_window.h
        message_channel_plugin.h
        message_channel_plugin.cc
        )
apply_standard_settings(${WEBKIT_BACKEND_NAME})
set_target_properties(${WEBKIT_BACKEND_NAME} PROPERTIES
        CXX_VISIBILITY_PRESET hidden)
target_link_libraries(${WEBKIT_BACKEND_NAME} PRIVATE
        flutter PkgConfig::GTK ${WEBKIT_TARGET} PkgConfig::LibSoup)

# Flutter links only this small registrar at app startup. WebKit stays in the
# dlopen backend so absent host libraries do not stop the rest of the app.
add_library(${PLUGIN_NAME} SHARED desktop_webview_window_plugin.cc)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK ${CMAKE_DL_LIBS})

# This is a build dependency, deliberately not a link dependency.
add_dependencies(${PLUGIN_NAME} ${WEBKIT_BACKEND_NAME})

# List of absolute paths to libraries that should be bundled with the plugin
set(desktop_webview_window_bundled_libraries
        "$<TARGET_FILE:${WEBKIT_BACKEND_NAME}>"
        PARENT_SCOPE
        )
