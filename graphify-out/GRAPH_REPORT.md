# Graph Report - apps  (2026-11-05)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 317 nodes · 399 edges · 20 communities (14 shown, 6 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 17 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ce99e362`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- win32_window.cpp
- my_application.cc
- engine_factory.dart
- transcriber_screen.dart
- ios/RunnerTests/RunnerTests.swift
- FlutterWindow
- utils.cpp
- pubspec.yaml
- app_locale.dart
- AppDelegate
- dependencies
- manifest.json
- main.js
- app_theme.dart
- analysis_options.yaml
- MainActivity.kt

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 21 edges
2. `FlutterWindow` - 10 edges
3. `WindowClassRegistrar` - 9 edges
4. `dependencies` - 9 edges
5. `_MyApplication` - 7 edges
6. `Point` - 5 edges
7. `Size` - 5 edges
8. `AppDelegate` - 5 edges
9. `wWinMain()` - 5 edges
10. `GetCommandLineArguments()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  client/windows/runner/main.cpp → client/windows/runner/utils.cpp
- `FlutterWindow` --inherits--> `Win32Window`  [EXTRACTED]
  client/windows/runner/flutter_window.h → client/windows/runner/win32_window.h
- `my_application_activate()` --calls--> `fl_register_plugins()`  [INFERRED]
  client/linux/runner/my_application.cc → client/linux/flutter/generated_plugin_registrant.cc
- `main()` --calls--> `my_application_new()`  [INFERRED]
  client/linux/runner/main.cc → client/linux/runner/my_application.cc
- `wWinMain()` --calls--> `GetCommandLineArguments()`  [INFERRED]
  client/windows/runner/main.cpp → client/windows/runner/utils.cpp

## Import Cycles
- None detected.

## Communities (20 total, 6 thin omitted)

### Community 0 - "win32_window.cpp"
Cohesion: 0.07
Nodes (19): EnableFullDpiSupportIfAvailable(), EnableNonClientDpiScaling, Point, x, y, Scale(), Size, height (+11 more)

### Community 1 - "my_application.cc"
Cohesion: 0.08
Nodes (14): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+6 more)

### Community 2 - "engine_factory.dart"
Cohesion: 0.07
Nodes (20): dispose, loadModel, state, TranscriberEngine, transcribeStream, confidence, end, EngineState (+12 more)

### Community 3 - "transcriber_screen.dart"
Cohesion: 0.09
Nodes (12): localeProvider, build, createState, _isRecording, _toggleRecording, _transcribedText, TranscriberScreen, _TranscriberScreenState (+4 more)

### Community 4 - "ios/RunnerTests/RunnerTests.swift"
Cohesion: 0.10
Nodes (12): SceneDelegate, RunnerTests, RegisterGeneratedPlugins(), MainFlutterWindow, RunnerTests, Cocoa, Flutter, FlutterMacOS (+4 more)

### Community 5 - "FlutterWindow"
Cohesion: 0.09
Nodes (5): RegisterPlugins(), FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 6 - "utils.cpp"
Cohesion: 0.13
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 7 - "pubspec.yaml"
Cohesion: 0.10
Nodes (19): description, dev_dependencies, flutter_lints, flutter_test, environment, flutter, sdk, flutter (+11 more)

### Community 8 - "app_locale.dart"
Cohesion: 0.11
Nodes (15): AppLanguage, AppStrings, clearText, copyText, direction, emptyTranscription, label, locale (+7 more)

### Community 10 - "dependencies"
Cohesion: 0.18
Nodes (11): dependencies, ffi, flutter, flutter_localizations, flutter_riverpod, intl, path, path_provider (+3 more)

### Community 11 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 12 - "main.js"
Cohesion: 0.22
Nodes (6): config, languageButton, messages, releaseDialog, webAppButton, webStatus

### Community 13 - "app_theme.dart"
Cohesion: 0.25
Nodes (5): AppTheme, darkBackground, darkSurface, darkTheme, primaryColor

### Community 14 - "analysis_options.yaml"
Cohesion: 0.33
Nodes (5): analyzer, exclude, include, linter, rules

## Knowledge Gaps
- **54 isolated node(s):** `x`, `y`, `height`, `width`, `child_content_` (+49 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 172 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Win32Window` connect `win32_window.cpp` to `FlutterWindow`, `utils.cpp`?**
  _High betweenness centrality (0.029) - this node is a cross-community bridge._
- **What connects `x`, `y`, `height` to the rest of the system?**
  _54 weakly-connected nodes found - possible missing edges._
- **Should `win32_window.cpp` be split into smaller, more focused modules?**
  _Cohesion score 0.07428571428571429 - nodes in this community are weakly interconnected._
- **Why does `FlutterWindow` connect `FlutterWindow` to `win32_window.cpp`, `utils.cpp`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **Should `my_application.cc` be split into smaller, more focused modules?**
  _Cohesion score 0.08387096774193549 - nodes in this community are weakly interconnected._
- **Should `engine_factory.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.0735632183908046 - nodes in this community are weakly interconnected._
- **Should `transcriber_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.09116809116809117 - nodes in this community are weakly interconnected._