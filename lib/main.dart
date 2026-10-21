import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:jiruhub/controllers/application_controller.dart';
import 'package:jiruhub/utils/log.dart';
import 'package:jiruhub/utils/jiruhub_directory.dart';
import 'package:jiruhub/utils/request.dart';
import 'package:jiruhub/views/pages/debug_page.dart';
import 'package:jiruhub/views/pages/main_page.dart';
import 'package:jiruhub/router/router.dart';
import 'package:jiruhub/utils/extension.dart';
import 'package:jiruhub/utils/i18n.dart';
import 'package:jiruhub/utils/jiruhub_storage.dart';
import 'package:jiruhub/utils/application.dart';
import 'package:jiruhub/utils/yeflix_style.dart';
import 'package:jiruhub/views/widgets/platform_widget.dart';
import 'package:window_manager/window_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main(List<String> args) async {
  if (args.contains('-version') || args.contains('--version')) {
    WidgetsFlutterBinding.ensureInitialized();
    final info = await PackageInfo.fromPlatform();
    print('Yeflix v${info.version}');
    exit(0);
  }

  runZonedGuarded(() async {
    FlutterError.onError = (FlutterErrorDetails details) {
      logger.severe("", details.exception, details.stack);
    };

    WidgetsFlutterBinding.ensureInitialized();

    // 多窗口
    if (args.firstOrNull == 'multi_window') {
      final windowId = int.parse(args[1]);
      final arguments = args[2].isEmpty
          ? const {}
          : jsonDecode(args[2]) as Map<String, dynamic>;

      Map windows = {
        "debug": ExtensionDebugWindow(
          windowController: WindowController.fromWindowId(windowId),
        ),
      };
      runApp(windows[arguments["name"]]);
      return;
    }

    // 主窗口
    await JiruHubDirectory.ensureInitialized();
    await JiruHubStorage.ensureInitialized();
    MiruLog.ensureInitialized();
    await ApplicationUtils.ensureInitialized();
    await MiruRequest.ensureInitialized();
    await ExtensionUtils.ensureInitialized();
    MediaKit.ensureInitialized();

    if (!Platform.isAndroid) {
      await windowManager.ensureInitialized();
      final sizeArr = JiruHubStorage.getSetting(SettingKey.windowSize).split(",");
      final size = Size(double.parse(sizeArr[0]), double.parse(sizeArr[1]));
      WindowOptions windowOptions = WindowOptions(
        size: size,
        center: true,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        final position = JiruHubStorage.getSetting(SettingKey.windowPosition);
        if (position != null) {
          final offsetArr = position.split(",");
          final offset = Offset(
            double.parse(offsetArr[0]),
            double.parse(offsetArr[1]),
          );
          await windowManager.setPosition(
            offset,
          );
        }
        await windowManager.show();
        await windowManager.focus();
      });
    }

    if (Platform.isAndroid) {
      SystemUiOverlayStyle style = const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      );
      SystemChrome.setSystemUIOverlayStyle(style);
    }

    runApp(const MainApp());
  }, (error, stack) {
    logger.severe("", error, stack);
  });
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late ApplicationController c;

  @override
  void initState() {
    c = Get.put(ApplicationController());
    super.initState();
  }

  Widget _buildMobileMain(BuildContext context) {
    final cjkFontFallback = const [
      "Noto Sans CJK JP",
      "Noto Sans CJK KR",
      "Noto Sans CJK TC",
      "Noto Sans CJK HK",
      "Microsoft Yahei",
      "SimSun",
      "Arial Unicode MS",
    ];
    return GetMaterialApp(
      title: "Yeflix",
      debugShowCheckedModeBanner: false,
      themeMode: c.theme,
      theme: _buildTheme(Brightness.light, cjkFontFallback),
      darkTheme: _buildTheme(Brightness.dark, cjkFontFallback),
      home: const AndroidMainPage(),
      localizationsDelegates: [
        I18nUtils.flutterI18nDelegate,
      ],
    );
  }

  ThemeData _buildTheme(Brightness brightness, List<String> fallback) {
    final isDark = brightness == Brightness.dark;
    const red = YeflixStyle.red;
    const redDark = YeflixStyle.redDark;
    final surface = isDark ? YeflixStyle.surface : Colors.white;
    final bg = isDark ? YeflixStyle.bg : const Color(0xFFF4F4F6);

    final scheme = isDark
        ? const ColorScheme.dark(
            primary: red,
            onPrimary: Colors.white,
            secondary: YeflixStyle.textMuted,
            onSecondary: Colors.black,
            surface: YeflixStyle.surface,
            onSurface: YeflixStyle.textPrimary,
            background: YeflixStyle.bg,
            onBackground: YeflixStyle.textPrimary,
            primaryContainer: Color(0xFF4A1414),
            onPrimaryContainer: Colors.white,
            surfaceTint: red,
          )
        : const ColorScheme.light(
            primary: redDark,
            onPrimary: Colors.white,
            secondary: Color(0xFF616161),
            onSecondary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF16161A),
            background: Color(0xFFF4F4F6),
            onBackground: Color(0xFF16161A),
            primaryContainer: Color(0xFFFFDAD6),
            onPrimaryContainer: Color(0xFF410002),
            surfaceTint: redDark,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: surface,
      dividerColor: isDark ? YeflixStyle.border : const Color(0xFFE2E2E8),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? YeflixStyle.bg : redDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: Colors.white,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? YeflixStyle.surface : Colors.white,
        indicatorColor: red.withOpacity(0.18),
        elevation: 0,
        height: 68,
      ),
      textTheme: _buildTextTheme(brightness, fallback),
    );
  }

  TextTheme _buildTextTheme(Brightness brightness, List<String> fallback) {
    final color = brightness == Brightness.dark ? Colors.white : Colors.black;
    return TextTheme(
      displayLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      displayMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      displaySmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      headlineLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      headlineMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      headlineSmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      titleLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      titleMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      titleSmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      bodyLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      bodyMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      bodySmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      labelLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      labelMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      labelSmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
    );
  }

  Widget _buildDesktopMain(BuildContext context) {
    return fluent.FluentApp.router(
      title: 'Yeflix',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: c.theme,
      darkTheme: fluent.FluentThemeData(
        brightness: Brightness.dark,
        visualDensity: VisualDensity.standard,
      ),
      theme: fluent.FluentThemeData(
        visualDensity: VisualDensity.standard,
      ),
      localizationsDelegates: [
        I18nUtils.flutterI18nDelegate,
      ],
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: "Noto Sans CJK SC",
                fontFamilyFallback: [
                  "Noto Sans CJK JP",
                  "Noto Sans CJK KR",
                  "Noto Sans CJK TC",
                  "Noto Sans CJK HK",
                  "Microsoft Yahei",
                  "SimSun",
                  "Arial Unicode MS",
                ],
              ),
              child: child ?? const SizedBox(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildMobileMain,
      desktopBuilder: _buildDesktopMain,
    );
  }
}
