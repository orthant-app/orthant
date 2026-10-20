# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(orthant LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "Orthant")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# WinSparkle, the updater, which the app opens over FFI from the directory
# it runs in. The release zip is pinned by its SHA-256 (the digest GitHub
# records for the asset) and fetched once per build directory; a download
# whose hash differs fails the configure step rather than shipping it.
set(WINSPARKLE_VERSION "0.9.4")
set(WINSPARKLE_SHA256
  "6037df37fc263bd1650a1c4949681a9d40ffe991d01f35892a406cb5d103c976")
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64")
  set(WINSPARKLE_ARCH "ARM64")
else()
  set(WINSPARKLE_ARCH "x64")
endif()
set(WINSPARKLE_DIR "${CMAKE_BINARY_DIR}/winsparkle-${WINSPARKLE_VERSION}")
set(WINSPARKLE_DLL
  "${WINSPARKLE_DIR}/WinSparkle-${WINSPARKLE_VERSION}/${WINSPARKLE_ARCH}/Release/WinSparkle.dll")
if(NOT EXISTS "${WINSPARKLE_DLL}")
  file(DOWNLOAD
    "https://github.com/vslavik/winsparkle/releases/download/v${WINSPARKLE_VERSION}/WinSparkle-${WINSPARKLE_VERSION}.zip"
    "${WINSPARKLE_DIR}/WinSparkle-${WINSPARKLE_VERSION}.zip"
    EXPECTED_HASH SHA256=${WINSPARKLE_SHA256}
    TLS_VERIFY ON
    SHOW_PROGRESS)
  file(ARCHIVE_EXTRACT
    INPUT "${WINSPARKLE_DIR}/WinSparkle-${WINSPARKLE_VERSION}.zip"
    DESTINATION "${WINSPARKLE_DIR}"
    PATTERNS "WinSparkle-${WINSPARKLE_VERSION}/${WINSPARKLE_ARCH}/Release/WinSparkle.dll")
endif()
install(FILES "${WINSPARKLE_DLL}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# The Visual C++ runtime the runner and its plugins link against, beside the
# executable: a per-user install cannot run Microsoft's runtime installer,
# which needs administrator rights, and a machine without the runtime could
# not start the app. The copies come from the compiler's own redistributable
# folder, so they match what the binaries were built with; configuring fails
# if any of the three is not there.
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
include(InstallRequiredSystemLibraries)
set(VC_RUNTIME_DLLS "")
foreach(lib ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS})
  get_filename_component(name "${lib}" NAME)
  string(TOLOWER "${name}" name)
  if(name MATCHES "^(msvcp140|vcruntime140|vcruntime140_1)\\.dll$")
    list(APPEND VC_RUNTIME_DLLS "${lib}")
  endif()
endforeach()
list(LENGTH VC_RUNTIME_DLLS VC_RUNTIME_COUNT)
if(NOT VC_RUNTIME_COUNT EQUAL 3)
  message(FATAL_ERROR "The Visual C++ runtime (msvcp140.dll, vcruntime140.dll, "
    "vcruntime140_1.dll) was not found beside the compiler; found: "
    "${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}")
endif()
install(FILES ${VC_RUNTIME_DLLS} DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
