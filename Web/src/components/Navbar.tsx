import { Link, useLocation } from 'react-router-dom';
import Logo from './Logo';
import GithubIcon from './GithubIcon';
import { release } from '../data/releases';

const links = [
  { label: 'Inicio', to: '/' },
  { label: 'Android', to: '/android' },
  { label: 'Windows', to: '/windows' },
  { label: 'Preguntas', to: '/faq' },
];

export default function Navbar() {
  const { pathname } = useLocation();

  return (
    <header className="sticky top-0 z-50 border-b border-white/[0.06] bg-[#07070a]/85 backdrop-blur-xl">
      <nav className="mx-auto flex h-16 w-full max-w-6xl items-center justify-between px-4 sm:px-6">
        <Link to="/" className="shrink-0" aria-label="Yeflix inicio">
          <Logo />
        </Link>

        <ul className="hidden items-center gap-1 md:flex">
          {links.map((link) => {
            const active = link.to === '/' ? pathname === '/' : pathname.startsWith(link.to);
            return (
              <li key={link.to}>
                <Link
                  to={link.to}
                  className={`rounded-full px-4 py-2 text-sm transition-colors ${
                    active
                      ? 'bg-white/10 text-white'
                      : 'text-white/60 hover:bg-white/5 hover:text-white'
                  }`}
                >
                  {link.label}
                </Link>
              </li>
            );
          })}
        </ul>

        <a
          href={release.repo}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3.5 py-2 text-sm text-white/80 transition-colors hover:border-white/20 hover:bg-white/10 hover:text-white"
        >
          <GithubIcon className="h-4 w-4" />
          <span className="hidden sm:inline">GitHub</span>
        </a>
      </nav>

      <div className="flex gap-1 overflow-x-auto px-4 pb-2 md:hidden">
        {links.map((link) => {
          const active = link.to === '/' ? pathname === '/' : pathname.startsWith(link.to);
          return (
            <Link
              key={link.to}
              to={link.to}
              className={`shrink-0 rounded-full px-3.5 py-1.5 text-sm transition-colors ${
                active
                  ? 'bg-white/10 text-white'
                  : 'text-white/55 hover:bg-white/5 hover:text-white'
              }`}
            >
              {link.label}
            </Link>
          );
        })}
      </div>
    </header>
  );
}
