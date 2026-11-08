import { Apple, Monitor, Smartphone, Terminal } from 'lucide-react';
import { Link } from 'react-router-dom';
import { release } from '../data/releases';

export default function DownloadButtons() {
  return (
    <div className="flex flex-col items-center gap-3 sm:flex-row sm:flex-wrap sm:justify-center">
      <Link
        to="/android"
        className="glow-brand inline-flex w-full items-center justify-center gap-2.5 rounded-full bg-brand px-6 py-3.5 text-sm font-semibold text-white transition-colors hover:bg-brand-strong sm:w-auto"
      >
        <Smartphone className="h-5 w-5" />
        Descargar para Android
      </Link>
      <Link
        to="/windows"
        className="inline-flex w-full items-center justify-center gap-2.5 rounded-full border border-white/15 bg-white/[0.06] px-6 py-3.5 text-sm font-semibold text-white transition-colors hover:border-white/30 hover:bg-white/10 sm:w-auto"
      >
        <Monitor className="h-5 w-5" />
        Descargar para Windows
      </Link>
      <Link
        to="/macos"
        className="inline-flex w-full items-center justify-center gap-2.5 rounded-full border border-white/15 bg-white/[0.06] px-6 py-3.5 text-sm font-semibold text-white transition-colors hover:border-white/30 hover:bg-white/10 sm:w-auto"
      >
        <Apple className="h-5 w-5" />
        Descargar para macOS
      </Link>
      <Link
        to="/linux"
        className="inline-flex w-full items-center justify-center gap-2.5 rounded-full border border-white/15 bg-white/[0.06] px-6 py-3.5 text-sm font-semibold text-white transition-colors hover:border-white/30 hover:bg-white/10 sm:w-auto"
      >
        <Terminal className="h-5 w-5" />
        Descargar para Linux
      </Link>
      <span className="sr-only">
        Versión {release.version} build {release.build}
      </span>
    </div>
  );
}
