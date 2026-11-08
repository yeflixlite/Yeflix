import { ShieldCheck, Smartphone, Monitor, Sparkles } from 'lucide-react';
import DownloadButtons from './DownloadButtons';
import { release } from '../data/releases';

const facts = [
  { icon: ShieldCheck, label: 'Sin publicidad intrusiva' },
  { icon: Smartphone, label: 'Android 5.0 o superior' },
  { icon: Monitor, label: 'Windows 10 / 11 (64-bit)' },
];

export default function Hero() {
  return (
    <section className="relative overflow-hidden">
      <div className="bg-grid absolute inset-0 opacity-40" aria-hidden="true" />
      <div
        className="absolute left-1/2 top-[-20rem] h-[36rem] w-[36rem] -translate-x-1/2 rounded-full bg-brand/20 blur-[140px]"
        aria-hidden="true"
      />

      <div className="relative mx-auto flex w-full max-w-5xl flex-col items-center px-4 pb-16 pt-20 text-center sm:px-6 sm:pt-28">
        <span className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.05] px-3.5 py-1.5 text-xs font-medium text-white/70">
          <Sparkles className="h-3.5 w-3.5 text-brand-strong" />
          Versión {release.version} · build {release.build}
        </span>

        <h1 className="mt-6 max-w-3xl text-4xl font-extrabold leading-[1.05] tracking-tight text-white sm:text-6xl md:text-7xl">
          Todo tu entretenimiento,
          <span className="block text-brand">en una sola app.</span>
        </h1>

        <p className="mt-6 max-w-2xl text-base leading-relaxed text-white/60 sm:text-lg">
          Yeflix reúne anime, películas y series en español con un reproductor rápido,
          descargas offline y soporte de extensiones. Disponible para Android y Windows.
        </p>

        <div className="mt-9 w-full max-w-2xl">
          <DownloadButtons />
        </div>

        <ul className="mt-10 flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
          {facts.map((fact) => (
            <li key={fact.label} className="inline-flex items-center gap-2 text-sm text-white/45">
              <fact.icon className="h-4 w-4 text-white/30" />
              {fact.label}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
