import { Monitor, ShieldCheck, AlertTriangle } from 'lucide-react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import DownloadCard from '../components/DownloadCard';
import { release, windowsAssets } from '../data/releases';

const steps = [
  'Descarga el instalador (.exe) o el portable (.zip).',
  'Si elegiste el instalador, ejecútalo y sigue el asistente.',
  'Si elegiste el portable, descomprime el ZIP y ejecuta yeflix.exe.',
  'Abre Yeflix y configura el repositorio de extensiones desde Ajustes.',
];

export default function Windows() {
  return (
    <>
      <Navbar />
      <main className="mx-auto w-full max-w-6xl px-4 py-14 sm:px-6">
        <div className="max-w-2xl">
          <span className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.05] px-3 py-1 text-xs font-medium text-white/60">
            <Monitor className="h-3.5 w-3.5" /> Windows · v{release.version} build {release.build}
          </span>
          <h1 className="mt-5 text-3xl font-extrabold tracking-tight text-white sm:text-5xl">
            Descargar para Windows
          </h1>
          <p className="mt-4 text-base leading-relaxed text-white/55">
            Dos opciones: el instalador clásico o la versión portable que no necesita
            instalación. Ambas son para Windows de 64 bits.
          </p>
        </div>

        <section className="mt-10">
          <h2 className="text-lg font-semibold text-white">Elige el formato</h2>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            {windowsAssets.map((asset) => (
              <DownloadCard key={asset.id} asset={asset} />
            ))}
          </div>
        </section>

        <section className="mt-14 grid gap-8 md:grid-cols-[1.1fr_1fr]">
          <div>
            <h2 className="text-lg font-semibold text-white">Cómo instalarlo</h2>
            <ol className="mt-4 space-y-4">
              {steps.map((step, index) => (
                <li key={step} className="flex gap-3 text-sm leading-relaxed text-white/55">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-white/[0.07] text-xs font-semibold text-white/80">
                    {index + 1}
                  </span>
                  {step}
                </li>
              ))}
            </ol>

            <div className="mt-6 flex items-start gap-3 rounded-2xl border border-amber-400/20 bg-amber-400/[0.06] p-4 text-sm text-white/60">
              <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-amber-300" />
              <p>
                Si Windows SmartScreen muestra una advertencia, pulsa
                <span className="text-white"> “Más información” → “Ejecutar de todos modos”</span>.
                El instalador no está firmado con un certificado comercial.
              </p>
            </div>
          </div>

          <aside className="rounded-2xl border border-white/[0.08] bg-[#0d0d13] p-5">
            <div className="flex items-center gap-2 text-sm font-semibold text-white">
              <ShieldCheck className="h-4 w-4 text-brand-strong" /> Requisitos
            </div>
            <ul className="mt-3 space-y-2 text-sm text-white/50">
              <li>Windows 10 u 11 de 64 bits.</li>
              <li>~150 MB libres para instalar.</li>
              <li>Reproductor y descargas incluidos; no requiere programas extra.</li>
            </ul>
            <p className="mt-4 text-xs leading-relaxed text-white/35">
              La versión portable se ejecuta desde cualquier carpeta y puedes moverla
              con una USB.
            </p>
          </aside>
        </section>
      </main>
      <Footer />
    </>
  );
}
