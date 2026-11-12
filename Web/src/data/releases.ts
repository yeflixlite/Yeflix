export const release = {
  version: '1.0.0',
  build: 1,
  tag: 'v1.0',
  repo: 'https://github.com/yeflixlite/Yeflix',
  releases: 'https://github.com/yeflixlite/Yeflix/releases',
  extensions: 'https://raw.githubusercontent.com/yeflixlite/Anime/main',
  base: 'https://github.com/yeflixlite/Yeflix/releases/download/v1.0',
} as const;

export type AssetIcon = 'phone' | 'tablet' | 'cpu' | 'installer' | 'portable' | 'mac' | 'archive';

export type Asset = {
  id: string;
  name: string;
  description: string;
  file: string;
  size: string;
  badge?: string;
  icon: AssetIcon;
};

export const androidAssets: Asset[] = [
  {
    id: 'arm64',
    name: 'ARM64 (arm64-v8a)',
    description: 'Para la mayoría de teléfonos y tablets modernos. Es la opción recomendada.',
    file: 'Yeflix-1.0.0-1-arm64-v8a.apk',
    size: '19.0 MB',
    badge: 'Recomendado',
    icon: 'phone',
  },
  {
    id: 'armv7',
    name: 'ARM 32 bits (armeabi-v7a)',
    description: 'Para teléfonos y tablets antiguos que no aceptan la versión ARM64.',
    file: 'Yeflix-1.0.0-1-armeabi-v7a.apk',
    size: '18.4 MB',
    icon: 'phone',
  },
  {
    id: 'x86_64',
    name: 'Intel / AMD (x86_64)',
    description: 'Para emuladores Android, Chromebooks y dispositivos con procesador Intel.',
    file: 'Yeflix-1.0.0-1-x86_64.apk',
    size: '20.0 MB',
    icon: 'cpu',
  },
  {
    id: 'tablet',
    name: 'Tablet (universal)',
    description: 'Versión optimizada para pantallas grandes. Incluye todas las arquitecturas.',
    file: 'Yeflix-1.0.0-1-tablet.apk',
    size: '57.3 MB',
    badge: 'Pantallas grandes',
    icon: 'tablet',
  },
];

export const windowsAssets: Asset[] = [
  {
    id: 'installer',
    name: 'Instalador (.exe)',
    description: 'Instala Yeflix en tu PC, crea accesos directos y permite desinstalarlo desde Configuración.',
    file: 'Yeflix-v1.0.0-Windows-Installer.exe',
    size: '26.2 MB',
    badge: 'Recomendado',
    icon: 'installer',
  },
  {
    id: 'portable',
    name: 'Portable (.zip)',
    description: 'Descomprime el archivo y ejecuta yeflix.exe. No requiere instalación ni permisos de administrador.',
    file: 'Yeflix-Windows-x64-Portable.zip',
    size: '34.2 MB',
    icon: 'portable',
  },
];

/**
 * macOS todavía no tiene compilación oficial: no hay un Mac disponible para
 * probarla. La web muestra la sección como «Próximamente» y no se publica
 * ningún archivo en el release.
 */
export const macosAssets: Asset[] = [];

export const linuxAssets: Asset[] = [
  {
    id: 'appimage',
    name: 'AppImage (x86_64)',
    description:
      'Un solo archivo que funciona en la mayoría de distribuciones. No requiere instalación: dale permisos y ábrelo.',
    file: 'Yeflix-1.0.0-Linux-x86_64.AppImage',
    size: '116.6 MB',
    badge: 'Recomendado',
    icon: 'installer',
  },
  {
    id: 'portable',
    name: 'Portable (.tar.gz)',
    description:
      'Carpeta lista para usar: extrae, abre «yeflix» y listo. Incluye el reproductor y sus librerías.',
    file: 'Yeflix-1.0.0-Linux-x64.tar.gz',
    size: '124.5 MB',
    icon: 'archive',
  },
];

export function assetUrl(asset: Asset): string {
  return `${release.base}/${asset.file}`;
}
