import { useEffect, useRef } from 'react';
import { ShieldCheck, Smartphone, Monitor, Sparkles } from 'lucide-react';
import DownloadButtons from './DownloadButtons';
import { release } from '../data/releases';

const base = import.meta.env.BASE_URL;

const facts = [
  { icon: ShieldCheck, label: 'Sin publicidad intrusiva' },
  { icon: Smartphone, label: 'Android 5.0 o superior' },
  { icon: Monitor, label: 'Windows 10 / 11 (64-bit)' },
];

export default function Hero() {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const slowMotion = () => {
      video.playbackRate = 0.2;
    };

    slowMotion();
    video.addEventListener('loadedmetadata', slowMotion);
    video.addEventListener('play', slowMotion);

    return () => {
      video.removeEventListener('loadedmetadata', slowMotion);
      video.removeEventListener('play', slowMotion);
    };
  }, []);

  return (
    <section className="relative overflow-hidden">
      <video
        ref={videoRef}
        autoPlay
        muted
        loop
        playsInline
        preload="auto"
        aria-hidden="true"
        className="absolute inset-0 h-full w-full object-cover opacity-65"
      >
        <source src={`${base}mascota.mp4`} type="video/mp4" />
      </video>
      <div
        className="absolute inset-0 bg-gradient-to-b from-[#07070a]/55 via-[#07070a]/75 to-[#07070a]"
        aria-hidden="true"
      />
      <div
        className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(7,7,10,0.15)_0%,rgba(7,7,10,0.65)_75%)]"
        aria-hidden="true"
      />
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
