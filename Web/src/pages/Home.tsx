import { ArrowRight, Download, Monitor, Puzzle, Smartphone, WifiOff, Zap } from 'lucide-react';
import { Link } from 'react-router-dom';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import Hero from '../components/Hero';
import { release } from '../data/releases';

const features = [
  {
    icon: Zap,
    title: 'Reproductor rápido',
    text: 'Cambia de servidor sin cortes y empieza a ver en segundos.',
  },
  {
    icon: WifiOff,
    title: 'Descargas offline',
    text: 'Guarda películas y episodios para verlos sin conexión.',
  },
  {
    icon: Puzzle,
    title: 'Extensiones',
    text: 'Agrega el repositorio oficial y amplía el catálogo cuando quieras.',
  },
  {
    icon: Download,
    title: 'Actualizaciones',
    text: 'La app detecta nuevas versiones y te avisa para instalarlas.',
  },
];

export default function Home() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />

        <section className="border-t border-white/[0.06] bg-[#08080c]">
          <div className="mx-auto w-full max-w-6xl px-4 py-16 sm:px-6">
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {features.map((feature) => (
                <article
                  key={feature.title}
                  className="rounded-2xl border border-white/[0.07] bg-[#0d0d13] p-5"
                >
                  <feature.icon className="h-5 w-5 text-brand-strong" />
                  <h2 className="mt-4 text-sm font-semibold text-white">{feature.title}</h2>
                  <p className="mt-1.5 text-sm leading-relaxed text-white/45">{feature.text}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="bg-[#07070a]">
          <div className="mx-auto w-full max-w-6xl px-4 py-16 sm:px-6">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
              <div>
                <h2 className="text-2xl font-bold tracking-tight text-white sm:text-3xl">
                  Elige tu plataforma
                </h2>
                <p className="mt-2 text-sm text-white/50">
                  Descarga la versión más reciente: {release.version} (build {release.build}).
                </p>
              </div>
              <a
                href={release.releases}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1.5 text-sm text-white/50 transition-colors hover:text-white"
              >
                Ver todas las versiones <ArrowRight className="h-4 w-4" />
              </a>
            </div>

            <div className="mt-8 grid gap-4 md:grid-cols-2">
              <Link
                to="/android"
                className="group rounded-3xl border border-white/[0.08] bg-gradient-to-br from-[#15151d] to-[#0c0c12] p-7 transition-colors hover:border-brand/40"
              >
                <div className="flex items-center justify-between">
                  <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-brand/15 ring-1 ring-brand/25">
                    <Smartphone className="h-6 w-6 text-brand-strong" />
                  </div>
                  <ArrowRight className="h-5 w-5 text-white/30 transition-transform group-hover:translate-x-1 group-hover:text-white" />
                </div>
                <h3 className="mt-6 text-xl font-bold text-white">Android</h3>
                <p className="mt-2 text-sm leading-relaxed text-white/50">
                  APK por arquitectura: ARM64, ARM 32 bits, Intel x86_64 y una versión
                  optimizada para tablets.
                </p>
                <span className="mt-5 inline-flex items-center gap-2 text-sm font-semibold text-brand-strong">
                  <Download className="h-4 w-4" /> Ver descargas
                </span>
              </Link>

              <Link
                to="/windows"
                className="group rounded-3xl border border-white/[0.08] bg-gradient-to-br from-[#15151d] to-[#0c0c12] p-7 transition-colors hover:border-white/25"
              >
                <div className="flex items-center justify-between">
                  <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-white/[0.07] ring-1 ring-white/10">
                    <Monitor className="h-6 w-6 text-white/80" />
                  </div>
                  <ArrowRight className="h-5 w-5 text-white/30 transition-transform group-hover:translate-x-1 group-hover:text-white" />
                </div>
                <h3 className="mt-6 text-xl font-bold text-white">Windows</h3>
                <p className="mt-2 text-sm leading-relaxed text-white/50">
                  Instalador con accesos directos o versión portable en ZIP para ejecutar
                  sin instalar nada.
                </p>
                <span className="mt-5 inline-flex items-center gap-2 text-sm font-semibold text-white/80">
                  <Download className="h-4 w-4" /> Ver descargas
                </span>
              </Link>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
