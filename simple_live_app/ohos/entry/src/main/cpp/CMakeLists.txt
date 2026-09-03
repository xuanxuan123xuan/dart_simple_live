# libmpv NAPI bridge (milestone 0 verification) — based on
# libmpv-ohos-master/integration/CMakeLists.sample.txt
#
# Iron rule 1: file name must equal SONAME (libmpv.so, not libmpv.so.2).
# Iron rule 2: $ORIGIN rpath + --disable-new-dtags + -z lazy.
# Iron rule 3: link only libace_napi.z.so (+ libnative_window.so for
#              SET_BUFFER_GEOMETRY); codec/native_image libs are pulled in
#              by libmpv.so's own DT_NEEDED — re-linking them here breaks
#              relocation in the app namespace ("mpv_create not found").
cmake_minimum_required(VERSION 3.16)
project(mpv_napi)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}/include)

set(LIBMPV_DIR "${NATIVERENDER_ROOT_PATH}/third_party/libmpv")
set(LIBMPV_SONAME "libmpv.so")

if(NOT EXISTS "${LIBMPV_DIR}/${LIBMPV_SONAME}")
    message(FATAL_ERROR "Missing ${LIBMPV_DIR}/${LIBMPV_SONAME}")
endif()

add_library(mpv_napi SHARED mpv_napi.cpp)

target_compile_options(mpv_napi PRIVATE -Wno-unused-command-line-argument)

target_link_libraries(mpv_napi PUBLIC libace_napi.z.so libnative_window.so libhilog_ndk.z.so)

get_filename_component(LIBMPV_DIR_ABS "${LIBMPV_DIR}" ABSOLUTE)

target_link_options(mpv_napi PRIVATE
    "LINKER:-rpath,\$ORIGIN"
    "LINKER:--disable-new-dtags"
    "LINKER:-L${LIBMPV_DIR_ABS}"
    "LINKER:--no-as-needed"
    "-l:${LIBMPV_SONAME}"
    "LINKER:--as-needed"
    "LINKER:-z,lazy"
)

# libmpv.so is linked via -l:; without LINK_DEPENDS replacing the prebuilt
# library would not trigger a relink and the HAP would keep the stale copy.
set_property(TARGET mpv_napi APPEND PROPERTY LINK_DEPENDS "${LIBMPV_DIR_ABS}/${LIBMPV_SONAME}")

add_custom_command(TARGET mpv_napi POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${LIBMPV_DIR}/${LIBMPV_SONAME}"
    "$<TARGET_FILE_DIR:mpv_napi>/${LIBMPV_SONAME}"
)
