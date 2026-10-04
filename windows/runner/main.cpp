#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <iostream>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // The settings window's floor (spec §5.5); W5 owns the frame rules proper.
  // Win32Window::Create leaves the window hidden until Show(), and nothing
  // here calls Show(): Dart asks for it over the channel when the user does.
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(560, 500);
  if (!window.Create(L"Orthant", origin, size)) {
    return EXIT_FAILURE;
  }
  // Closing the window hides it (FlutterWindow::MessageHandler). Quit is the
  // tray item, which exits the process from Dart.
  window.SetQuitOnClose(false);

#ifndef NDEBUG
  // W0's proof of per-monitor-v2 awareness at runtime (spec §5.2): the live
  // window's context, not the manifest that requested it. Debug builds only,
  // read from the acceptance log; NDEBUG is defined for Profile and Release.
  const bool per_monitor_v2 = AreDpiAwarenessContextsEqual(
      GetWindowDpiAwarenessContext(window.GetHandle()),
      DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  std::cout << "[orthant] per-monitor-v2 awareness: "
            << (per_monitor_v2 ? "yes" : "NO") << std::endl;
#endif

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
