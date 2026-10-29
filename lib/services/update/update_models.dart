/// Modelos del sistema de actualizaciones.
///
/// Todo el cálculo de versiones vive aquí para poder probarlo sin Flutter ni
/// acceso a red. La comparación tiene en cuenta el número de compilación
/// (`build`), no solo el `versionName`, porque varias compilaciones de Yeflix
/// comparten `1.0.2`.
library jiruhub.update_models;

/// Distribución desde la que se está ejecutando la app.
enum UpdatePlatform {
  android,
  windowsPortable,
  windowsInstalled,
  linux,
  unsupported;

  bool get isWindows =>
      this == UpdatePlatform.windowsPortable ||
      this == UpdatePlatform.windowsInstalled;

  String get label {
    switch (this) {
      case UpdatePlatform.android:
        return 'Android';
      case UpdatePlatform.windowsPortable:
        return 'Windows (portable)';
      case UpdatePlatform.windowsInstalled:
        return 'Windows (instalado)';
      case UpdatePlatform.linux:
        return 'Linux';
      case UpdatePlatform.unsupported:
        return 'Plataforma no compatible';
    }
  }
}

/// Tipo de archivo publicado en el release.
enum UpdateAssetKind {
  apk,
  windowsZip,
  windowsInstaller,
  linuxArchive,
  versionJson,
  other,
}

/// Versión semántica con compilación opcional.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build = 0,
    this.raw = '',
  });

  final int major;
  final int minor;
  final int patch;

  /// Número de compilación. `0` significa desconocido.
  final int build;
  final String raw;

  static final RegExp _versionPattern = RegExp(
    r'(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-+.](\d+))?',
  );

  /// Acepta `1.0.2`, `v1.0.2`, `1.0.2+10`, `1.0.2-10` y similares.
  ///
  /// [build] tiene prioridad sobre el sufijo numérico del texto.
  factory AppVersion.parse(String? input, {int? build}) {
    final text = (input ?? '').trim();
    final match = _versionPattern.firstMatch(text);
    if (match == null) {
      return AppVersion(
          major: 0, minor: 0, patch: 0, build: build ?? 0, raw: text);
    }
    final suffixBuild = int.tryParse(match.group(4) ?? '');
    return AppVersion(
      major: int.tryParse(match.group(1) ?? '') ?? 0,
      minor: int.tryParse(match.group(2) ?? '') ?? 0,
      patch: int.tryParse(match.group(3) ?? '') ?? 0,
      build: build ?? suffixBuild ?? 0,
      raw: text,
    );
  }

  bool get isValid => major > 0 || minor > 0 || patch > 0;

  /// `1.0.2`
  String get display => '$major.$minor.$patch';

  /// `1.0.2 (compilación 10)`
  String get displayWithBuild =>
      build > 0 ? '$display (compilación $build)' : display;

  AppVersion copyWith({int? build}) => AppVersion(
        major: major,
        minor: minor,
        patch: patch,
        build: build ?? this.build,
        raw: raw,
      );

  /// Compara solo `major.minor.patch`.
  int compareVersion(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  int compareTo(AppVersion other) {
    final version = compareVersion(other);
    if (version != 0) return version;
    return build.compareTo(other.build);
  }

  /// `true` solo si esta versión es realmente más nueva.
  ///
  /// Si las versiones son iguales y alguna compilación es desconocida (`0`) no
  /// se declara actualización: así se evitan avisos falsos cuando GitHub no
  /// publica `version.json` ni el build en el nombre del archivo.
  bool isNewerThan(AppVersion local) {
    final version = compareVersion(local);
    if (version != 0) return version > 0;
    if (build <= 0 || local.build <= 0) return false;
    return build > local.build;
  }

  @override
  String toString() => displayWithBuild;

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.build == build;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);
}

/// Archivo descargable de un release de GitHub.
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.kind,
    this.size = 0,
    this.digest,
    this.version,
    this.build,
    this.abi,
    this.isTablet = false,
  });

  final String name;
  final String url;
  final UpdateAssetKind kind;
  final int size;

  /// Digest de GitHub, p. ej. `sha256:abc...`.
  final String? digest;
  final String? version;
  final int? build;

  /// ABI normalizada (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`,
  /// `universal`).
  final String? abi;
  final bool isTablet;

  bool get isApk => kind == UpdateAssetKind.apk;

  bool get isUniversalApk => isTablet || abi == 'universal';

  /// `sha256:...` → `...`
  String? get sha256 {
    final value = digest;
    if (value == null) return null;
    final lower = value.toLowerCase();
    if (lower.startsWith('sha256:')) return lower.substring(7);
    if (RegExp(r'^[a-f0-9]{64}$').hasMatch(lower)) return lower;
    return null;
  }

  static String? normalizeAbi(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final value = raw.toLowerCase();
    if (value.contains('arm64')) return 'arm64-v8a';
    if (value.contains('armeabi-v7a') || value == 'arm' || value == 'armeabi') {
      return 'armeabi-v7a';
    }
    if (value.contains('x86_64') || value.contains('x64')) return 'x86_64';
    if (value.contains('x86')) return 'x86';
    if (value.contains('tablet') || value.contains('universal')) {
      return 'universal';
    }
    return null;
  }

  /// Offset del `versionCode` por ABI usado por `android/app/build.gradle`.
  static int abiVersionCodeOffset(String? abi) {
    switch (normalizeAbi(abi)) {
      case 'x86_64':
        return 1;
      case 'armeabi-v7a':
        return 2;
      case 'arm64-v8a':
        return 3;
      default:
        return 0;
    }
  }

  /// `versionCode` que tendría este APK si se instalara.
  ///
  /// El override por ABI de Gradle solo se aplica a los splits: el APK
  /// universal (tablet) conserva el `versionCode` base del build.
  int? get androidVersionCode {
    final assetBuild = build;
    if (assetBuild == null || assetBuild <= 0) return null;
    final normalizedAbi = normalizeAbi(abi);
    if (normalizedAbi == null || normalizedAbi == 'universal') {
      return assetBuild;
    }
    return assetBuild * 10 + abiVersionCodeOffset(normalizedAbi);
  }

  static UpdateAsset? fromGitHub(
    Map<String, dynamic> json, {
    String? fallbackVersion,
  }) {
    final name = (json['name'] as String?)?.trim() ?? '';
    final url = (json['browser_download_url'] as String?)?.trim() ?? '';
    if (name.isEmpty || url.isEmpty) return null;

    final lower = name.toLowerCase();
    final size = (json['size'] as num?)?.toInt() ?? 0;
    final digest = json['digest'] as String?;

    String? version;
    int? build;
    String? abi;
    var isTablet = false;
    var kind = UpdateAssetKind.other;

    if (lower.endsWith('.apk')) {
      kind = UpdateAssetKind.apk;
      final match = RegExp(
        r'^yeflix-v?(\d+\.\d+\.\d+)-(?:(\d+)-)?([a-z0-9_\-]+)\.apk$',
      ).firstMatch(lower);
      if (match != null) {
        version = match.group(1);
        build = int.tryParse(match.group(2) ?? '');
        abi = normalizeAbi(match.group(3));
        isTablet = abi == 'universal';
      } else {
        version = _firstVersion(lower);
        abi = normalizeAbi(lower);
        isTablet = lower.contains('tablet');
      }
    } else if (lower == 'version.json') {
      kind = UpdateAssetKind.versionJson;
    } else if (lower.endsWith('.zip') && lower.contains('windows')) {
      kind = UpdateAssetKind.windowsZip;
      version = _firstVersion(lower);
    } else if (lower.endsWith('.exe') && lower.contains('windows')) {
      kind = UpdateAssetKind.windowsInstaller;
      version = _firstVersion(lower);
    } else if ((lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) &&
        (lower.contains('linux') || lower.contains('yeflix'))) {
      kind = UpdateAssetKind.linuxArchive;
      version = _firstVersion(lower);
    }

    if (version == null && kind != UpdateAssetKind.versionJson) {
      version = fallbackVersion;
    }

    return UpdateAsset(
      name: name,
      url: url,
      kind: kind,
      size: size,
      digest: digest,
      version: version,
      build: build,
      abi: abi,
      isTablet: isTablet,
    );
  }

  static String? _firstVersion(String text) {
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(text);
    return match?.group(1);
  }

  @override
  String toString() => '$name ($kind)';
}

/// Release remoto ya interpretado.
class RemoteRelease {
  const RemoteRelease({
    required this.tagName,
    required this.version,
    required this.htmlUrl,
    required this.body,
    required this.assets,
    this.build,
    this.publishedAt,
    this.raw = const {},
  });

  final String tagName;
  final AppVersion version;
  final String htmlUrl;
  final String body;
  final List<UpdateAsset> assets;
  final int? build;
  final DateTime? publishedAt;

  /// JSON original de GitHub (se guarda en caché).
  final Map<String, dynamic> raw;

  /// Número de compilación publicado en `version.json` o, si no existe, el
  /// que aparece en el nombre de los APK.
  int? get resolvedBuild {
    if (build != null && build! > 0) return build;
    for (final asset in assets) {
      if (asset.build != null && asset.build! > 0) return asset.build;
    }
    return null;
  }

  RemoteRelease copyWith({int? build}) => RemoteRelease(
        tagName: tagName,
        version: version,
        htmlUrl: htmlUrl,
        body: body,
        assets: assets,
        build: build ?? this.build,
        publishedAt: publishedAt,
        raw: raw,
      );

  static RemoteRelease? fromJson(Map<String, dynamic> json, {int? build}) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty) return null;
    final version = AppVersion.parse(tag);
    if (!version.isValid) return null;

    final assets = <UpdateAsset>[];
    for (final raw in (json['assets'] as List?) ?? const []) {
      if (raw is Map) {
        final asset = UpdateAsset.fromGitHub(
          Map<String, dynamic>.from(raw),
          fallbackVersion: version.display,
        );
        if (asset != null) assets.add(asset);
      }
    }

    DateTime? publishedAt;
    final published = json['published_at'] as String?;
    if (published != null) publishedAt = DateTime.tryParse(published);

    return RemoteRelease(
      tagName: tag,
      version: version,
      htmlUrl: (json['html_url'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      assets: assets,
      build: build,
      publishedAt: publishedAt,
      raw: json,
    );
  }
}

/// Entorno local usado para decidir si hay actualización.
class UpdateEnvironment {
  const UpdateEnvironment({
    required this.localVersion,
    required this.platform,
    this.localBuildNumber,
    this.supportedAbis = const [],
    this.isTablet = false,
    this.installedUniversalApk,
  });

  final AppVersion localVersion;

  /// `versionCode` en Android; `buildNumber` en escritorio.
  final int? localBuildNumber;
  final UpdatePlatform platform;
  final List<String> supportedAbis;
  final bool isTablet;

  /// `true` si el APK instalado es universal (sin override de `versionCode`),
  /// `false` si es un split por ABI, `null` si no se pudo determinar.
  final bool? installedUniversalApk;

  bool get isAndroid => platform == UpdatePlatform.android;
}

/// Resultado de una comprobación de actualización.
class UpdateCheckResult {
  UpdateCheckResult({
    required this.hasUpdate,
    required this.localVersion,
    required this.platform,
    this.release,
    this.asset,
    this.localBuild,
    this.remoteBuild,
    this.localVersionCode,
    this.error,
    this.fromCache = false,
    DateTime? checkedAt,
  }) : checkedAt = checkedAt ?? DateTime.now();

  final bool hasUpdate;
  final AppVersion localVersion;
  final UpdatePlatform platform;
  final RemoteRelease? release;

  /// Paquete recomendado para esta distribución. Puede ser `null` si el
  /// release no publica un archivo compatible.
  final UpdateAsset? asset;

  /// Build local efectivo (en Android ya normalizado desde el `versionCode`).
  final int? localBuild;
  final int? remoteBuild;

  /// `versionCode` bruto instalado (solo Android). Se usa para rechazar APKs
  /// que no se pueden instalar encima.
  final int? localVersionCode;
  final String? error;
  final bool fromCache;
  final DateTime checkedAt;

  bool get failed => error != null;
  bool get hasAsset => asset != null;

  String get localDescription => localBuild != null && localBuild! > 0
      ? '${localVersion.display} (build $localBuild)'
      : localVersion.display;

  String get remoteDescription {
    final version = release?.version.display ?? '—';
    return remoteBuild != null && remoteBuild! > 0
        ? '$version (build $remoteBuild)'
        : version;
  }

  static UpdateCheckResult failure({
    required UpdateEnvironment environment,
    required String error,
  }) =>
      UpdateCheckResult(
        hasUpdate: false,
        localVersion: environment.localVersion,
        platform: environment.platform,
        localBuild: environment.localBuildNumber,
        localVersionCode: environment.localBuildNumber,
        error: error,
      );
}
