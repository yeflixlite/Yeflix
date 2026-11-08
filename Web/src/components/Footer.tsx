import { Puzzle } from 'lucide-react';
import { Link } from 'react-router-dom';
import Logo from './Logo';
import GithubIcon from './GithubIcon';
import { release } from '../data/releases';

export default function Footer() {
  return (
    <footer className="border-t border-white/[0.06] bg-[#08080c]">
      <div className="mx-auto grid w-full max-w-6xl gap-10 px-4 py-12 sm:px-6 md:grid-cols-[1.4fr_1fr_1fr]">
        <div>
          <Logo />
          <p className="mt-4 max-w-sm text-sm leading-relaxed text-white/50">
            Anime, películas y series en español. Una app ligera para Android, Windows y macOS,
            con reproductor propio y soporte de extensiones.
          </p>
        </div>

        <div>
          <h3 className="text-xs font-semibold uppercase tracking-[0.18em] text-white/40">
            Descargas
          </h3>
          <ul className="mt-4 space-y-2 text-sm text-white/60">
            <li>
              <Link to="/android" className="transition-colors hover:text-white">
                Android
              </Link>
            </li>
            <li>
              <Link to="/windows" className="transition-colors hover:text-white">
                Windows
              </Link>
            </li>
            <li>
              <Link to="/macos" className="transition-colors hover:text-white">
                macOS
              </Link>
            </li>
            <li>
              <a
                href={release.releases}
                target="_blank"
                rel="noopener noreferrer"
                className="transition-colors hover:text-white"
              >
                Todas las versiones
              </a>
            </li>
          </ul>
        </div>

        <div>
          <h3 className="text-xs font-semibold uppercase tracking-[0.18em] text-white/40">
            Proyecto
          </h3>
          <ul className="mt-4 space-y-2 text-sm text-white/60">
            <li>
              <a
                href={release.repo}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 transition-colors hover:text-white"
              >
                <GithubIcon className="h-4 w-4" /> Repositorio
              </a>
            </li>
            <li>
              <a
                href={release.extensions}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 transition-colors hover:text-white"
              >
                <Puzzle className="h-4 w-4" /> Extensiones
              </a>
            </li>
          </ul>
        </div>
      </div>

      <div className="border-t border-white/[0.06]">
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-2 px-4 py-5 text-xs text-white/35 sm:flex-row sm:items-center sm:justify-between sm:px-6">
          <p>© {new Date().getFullYear()} Yeflix. Todos los derechos reservados.</p>
          <p>
            Yeflix no aloja contenido. Las extensiones y fuentes son de terceros.
          </p>
        </div>
      </div>
    </footer>
  );
}
