cmake_minimum_required(VERSION 3.10)

project(fastdev_quickjs_runtime LANGUAGES C CXX)

set(CXX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../cxx")
set(QUICKJS_DIR "${CXX_DIR}/quickjs")
file(STRINGS "${QUICKJS_DIR}/VERSION" QUICKJS_VERSION)

add_library(fastdev_quickjs_runtime SHARED
  "${QUICKJS_DIR}/cutils.c"
  "${QUICKJS_DIR}/libregexp.c"
  "${QUICKJS_DIR}/libunicode.c"
  "${QUICKJS_DIR}/quickjs.c"
  "${CXX_DIR}/libfastdev_quickjs_runtime.cpp"
)

target_include_directories(fastdev_quickjs_runtime PRIVATE "${QUICKJS_DIR}")
target_compile_definitions(fastdev_quickjs_runtime PRIVATE
  CONFIG_VERSION="${QUICKJS_VERSION}"
)
target_compile_options(fastdev_quickjs_runtime PRIVATE
  -fPIC
  -Wno-int-conversion
  -Wno-unused-variable
  -Wno-unused-but-set-variable
)
target_compile_features(fastdev_quickjs_runtime PRIVATE cxx_std_17)
target_link_libraries(fastdev_quickjs_runtime PRIVATE m)

set_target_properties(fastdev_quickjs_runtime PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../../ohos/entry/libs/arm64-v8a"
)
