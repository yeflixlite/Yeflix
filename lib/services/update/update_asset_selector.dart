/// Reglas puras de comparación de versiones y selección de paquetes.
///
/// No usa Flutter ni `dart:io`, de modo que puede probarse con `flutter test`
/// sin emuladores ni red.
library jiruhub.update_asset_selector;

import 'dart:math' as math;

import 'package:jiruhub/services/update/update_models.dart';

class UpdateAssetSelector {
  UpdateAssetSelector._();

  /// Deriva el build real de una instalación Android.
  ///
  /// `android/app/build.gradle` añade un offset al `versionCode` según la ABI:
  /// `x86_64 = +1`, `armeabi-v7a = +2`, `arm64-v8a = +3`; el APK de tablet usa
  /// el `versionCode` base. Por eso una instalación arm64 del build 9 reporta
  /// `93` y no `9`.
  ///
  /// Se generan los candidatos (`versionCode` y `versionCode ~/ 10` cuando el
  /// último dígito es 1–3) y se elige el más cercano al build remoto. En caso
  /// de empate se prefiere el mayor. Así se evitan tanto falsos positivos como
  /// no detectar una actualización.
  static int deriveLocalBuild({
    required int rawVersionCode,
    int? remoteBuild,
    bool? installedUniversalApk,
  }) {
    if (rawVersionCode <= 0) return 0;

    // APK universal (o sin librerías nativas): Gradle no aplica el override.
    if (installedUniversalApk == true) return rawVersionCode;

    final lastDigit = rawVersionCode % 10;
    final looksLikeAbiSplit =
        rawVersionCode >= 10 && lastDigit >= 1 && lastDigit <= 3;

    // Split por ABI: versionCode = build * 10 + offset (1–3).
    if (installedUniversalApk == false) {
      return looksLikeAbiSplit ? rawVersionCode ~/ 10 : rawVersionCode;
    }

    // Variante desconocida: se usan candidatos y se elige el más cercano al
    // build remoto (en caso de empate, el mayor).
    final candidates = <int>{rawVersionCode};
    if (looksLikeAbiSplit) {
      candidates.add(rawVersionCode ~/ 10);
    }
    if (remoteBuild == null || remoteBuild <= 0) {
      return candidates.reduce(math.max);
    }
    var best = candidates.first;
    for (final candidate in candidates) {
      final distance = (candidate - remoteBuild).abs();
      final bestDistance = (best - remoteBuild).abs();
      if (distance < bestDistance ||
          (distance == bestDistance && candidate > best)) {
        best = candidate;
      }
    }
    return best;
  }

  /// Evalúa un release contra el entorno local y elige el paquete adecuado.
  static UpdateCheckResult evaluate({
    required RemoteRelease release,
    required UpdateEnvironment environment,
  }) {
    final remoteBuild = release.resolvedBuild;
    final rawLocalBuild = environment.localBuildNumber;
    final localBuild = environment.isAndroid && rawLocalBuild != null
        ? deriveLocalBuild(
            rawVersionCode: rawLocalBuild,
            remoteBuild: remoteBuild,
            installedUniversalApk: environment.installedUniversalApk,
          )
        : rawLocalBuild;

    final localVersion = environment.localVersion.copyWith(
      build: localBuild ?? 0,
    );
    final remoteVersion = release.version.copyWith(build: remoteBuild ?? 0);
    final hasUpdate = remoteVersion.isNewerThan(localVersion);

    UpdateAsset? asset;
    if (hasUpdate) {
      switch (environment.platform) {
        case UpdatePlatform.android:
          asset = selectAndroidAsset(
            assets: release.assets,
            remoteVersion: release.version.display,
            remoteBuild: remoteBuild,
            installedVersionCode: rawLocalBuild ?? 0,
            supportedAbis: environment.supportedAbis,
            isTablet: environment.isTablet,
          );
          break;
        case UpdatePlatform.windowsPortable:
          asset = selectWindowsAsset(
            assets: release.assets,
            remoteVersion: release.version.display,
            installed: false,
          );
          break;
        case UpdatePlatform.windowsInstalled:
          asset = selectWindowsAsset(
            assets: release.assets,
            remoteVersion: release.version.display,
            installed: true,
          );
          break;
        case UpdatePlatform.linux:
          asset = selectLinuxAsset(
            assets: release.assets,
            remoteVersion: release.version.display,
          );
          break;
        case UpdatePlatform.unsupported:
          asset = null;
          break;
      }
    }

    return UpdateCheckResult(
      hasUpdate: hasUpdate,
      localVersion: environment.localVersion,
      platform: environment.platform,
      release: release,
      asset: asset,
      localBuild: localBuild,
      remoteBuild: remoteBuild,
      localVersionCode: rawLocalBuild,
    );
  }

  /// Selecciona el APK para un dispositivo Android.
  ///
  /// - Teléfono: solo APK de su ABI; nunca el de tablet.
  /// - Tablet: prefiere el APK universal, pero solo si su `versionCode` no es
  ///   inferior al instalado (evita un downgrade al cruzar variantes); si no,
  ///   usa el APK de ABI.
  static UpdateAsset? selectAndroidAsset({
    required List<UpdateAsset> assets,
    required String remoteVersion,
    required int? remoteBuild,
    required int installedVersionCode,
    required List<String> supportedAbis,
    required bool isTablet,
  }) {
    final apks = assets
        .where(
          (asset) =>
              asset.kind == UpdateAssetKind.apk &&
              _matchesVersion(asset, remoteVersion, remoteBuild),
        )
        .toList();

    UpdateAsset? abiAsset;
    for (final abi in supportedAbis) {
      final normalized = UpdateAsset.normalizeAbi(abi);
      if (normalized == null || normalized == 'universal') continue;
      for (final asset in apks) {
        if (asset.abi == normalized) {
          abiAsset = asset;
          break;
        }
      }
      if (abiAsset != null) break;
    }
    if (abiAsset != null && !_isUpgrade(abiAsset, installedVersionCode)) {
      abiAsset = null;
    }

    if (!isTablet) return abiAsset;

    final tablet = _firstWhere(apks, (asset) => asset.isUniversalApk);
    if (tablet == null) return abiAsset;

    final tabletCode = tablet.androidVersionCode;
    if (tabletCode == null || installedVersionCode <= 0) return tablet;
    if (tabletCode >= installedVersionCode) return tablet;

    // El APK universal tiene un versionCode base (build * 10) y el teléfono
    // instalado puede llevar offset de ABI. Si no se puede instalar encima,
    // se usa el APK de ABI.
    return abiAsset;
  }

  /// Selecciona el paquete de Windows según sea portable o instalado.
  static UpdateAsset? selectWindowsAsset({
    required List<UpdateAsset> assets,
    required String remoteVersion,
    required bool installed,
  }) {
    UpdateAsset? best;
    var bestScore = 1 << 20;

    for (final asset in assets) {
      var score = 0;
      if (asset.version != null && asset.version != remoteVersion) {
        score += 50;
      }
      final name = asset.name.toLowerCase();

      if (installed) {
        if (asset.kind != UpdateAssetKind.windowsInstaller) continue;
        if (name.contains('installer')) score -= 10;
        if (name.contains('portable')) score += 40;
      } else {
        if (asset.kind != UpdateAssetKind.windowsZip) continue;
        if (name.contains('portable')) score -= 5;
        if (name.contains('x64') || name.contains('win64')) score -= 3;
      }

      if (score < bestScore) {
        bestScore = score;
        best = asset;
      }
    }
    return best;
  }

  /// Selecciona el archivo `.tar.gz` de Linux.
  static UpdateAsset? selectLinuxAsset({
    required List<UpdateAsset> assets,
    required String remoteVersion,
  }) {
    for (final asset in assets) {
      if (asset.kind != UpdateAssetKind.linuxArchive) continue;
      if (asset.version == null || asset.version == remoteVersion) {
        return asset;
      }
    }
    return null;
  }

  /// Detecta si la copia de Windows es una instalación (Inno Setup) o portable.
  ///
  /// Es instalada si existe `unins000.exe` junto al ejecutable o si el
  /// ejecutable está dentro de `Program Files` o `%LOCALAPPDATA%\Programs`.
  static bool isInstalledWindows({
    required String executablePath,
    required bool hasUninstaller,
    String? programFiles,
    String? programFilesX86,
    String? localAppData,
  }) {
    if (hasUninstaller) return true;

    String normalize(String value) {
      var result = value.replaceAll('\\', '/').toLowerCase();
      while (result.endsWith('/')) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    }

    final exe = normalize(executablePath);
    for (final root in [programFiles, programFilesX86]) {
      if (root == null || root.trim().isEmpty) continue;
      final prefix = '${normalize(root)}/';
      if (exe.startsWith(prefix)) return true;
    }
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      final prefix = '${normalize(localAppData)}/programs/';
      if (exe.startsWith(prefix)) return true;
    }
    return false;
  }

  static bool _matchesVersion(
    UpdateAsset asset,
    String remoteVersion,
    int? remoteBuild,
  ) {
    if (asset.version != null && asset.version != remoteVersion) return false;
    if (remoteBuild != null &&
        remoteBuild > 0 &&
        asset.build != null &&
        asset.build! > 0 &&
        asset.build != remoteBuild) {
      return false;
    }
    return true;
  }

  static bool _isUpgrade(UpdateAsset asset, int installedVersionCode) {
    final code = asset.androidVersionCode;
    if (code == null || installedVersionCode <= 0) return true;
    return code > installedVersionCode;
  }

  static UpdateAsset? _firstWhere(
    List<UpdateAsset> assets,
    bool Function(UpdateAsset) predicate,
  ) {
    for (final asset in assets) {
      if (predicate(asset)) return asset;
    }
    return null;
  }
}
