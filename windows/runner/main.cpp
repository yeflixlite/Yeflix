#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Asegurar una sola instancia activa de Yeflix
  HANDLE hMutex = ::CreateMutex(nullptr, TRUE, L"Yeflix_Single_Instance_Mutex");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existingHwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", L"yeflix");
    if (!existingHwnd) {
      existingHwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    }
    if (existingHwnd) {
      if (::IsIconic(existingHwnd)) {
        ::ShowWindow(existingHwnd, SW_RESTORE);
      }
      ::SetForegroundWindow(existingHwnd);
    }
    if (hMutex) {
      ::CloseHandle(hMutex);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  // No se crea consola al abrir la app normalmente: el usuario solo debe ver
  // la ventana de Yeflix. Los logs se guardan en Documents\jiruhub\jiruhub.log.
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
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"yeflix", origin, size)) {
    if (hMutex) {
      ::ReleaseMutex(hMutex);
      ::CloseHandle(hMutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (hMutex) {
    ::ReleaseMutex(hMutex);
    ::CloseHandle(hMutex);
  }
  // Terminar de inmediato todos los hilos secundarios (media_kit / mpv, isolate, worker threads)
  ::ExitProcess(EXIT_SUCCESS);
  return EXIT_SUCCESS;
}
