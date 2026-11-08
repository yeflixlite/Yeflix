import { Info, ShieldCheck, Smartphone } from 'lucide-react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import DownloadCard from '../components/DownloadCard';
import { androidAssets, release } from '../data/releases';

const steps = [
  'Descarga el APK que corresponda a tu dispositivo.',
  'Abre el archivo desde la notificación o desde tu gestor de archivos.',
  'Si Android lo pide, activa “Instalar apps desconocidas” para tu navegador.',
  'Confirma la instalación y abre Yeflix.',
];

export default function Android() {
  return (
    <>
      <Navbar />
      <main className="mx-auto w-full max-w-6xl px-4 py-14 sm:px-6">
        <div className="max-w-2xl">
          <span className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.05] px-3 py-1 text-xs font-medium text-white/60">
            <Smartphone className="h-3.5 w-3.5" /> Android · v{release.version} build {release.build}
          </span>
          <h1 className="mt-5 text-3xl font-extrabold tracking-tight text-white sm:text-5xl">
            Descargar para Android
          </h1>
          <p className="mt-4 text-base leading-relaxed text-white/55">
            Elige la arquitectura de tu dispositivo. Si no estás seguro, empieza por
            <strong className="text-white"> ARM64</strong>: funciona en la mayoría de teléfonos
            y tablets modernos.
          </p>
        </div>

        <div className="mt-8 flex items-start gap-3 rounded-2xl border border-brand/25 bg-brand/[0.08] p-4 text-sm text-white/70">
          <Info className="mt-0.5 h-5 w-5 shrink-0 text-brand-strong" />
          <p>
            ¿Ves el error “Aplicación no instalada”? Desinstala una versión anterior,
            verifica el espacio libre o prueba con otra arquitectura (por ejemplo,
            <span className="text-white"> armeabi-v7a</span>).
          </p>
        </div>

        <section className="mt-10">
          <h2 className="text-lg font-semibold text-white">APK por arquitectura</h2>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            {androidAssets.map((asset) => (
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
          </div>

          <aside className="rounded-2xl border border-white/[0.08] bg-[#0d0d13] p-5">
            <div className="flex items-center gap-2 text-sm font-semibold text-white">
              <ShieldCheck className="h-4 w-4 text-brand-strong" /> Requisitos
            </div>
            <ul className="mt-3 space-y-2 text-sm text-white/50">
              <li>Android 5.0 (Lollipop) o superior.</li>
              <li>~60 MB libres para instalar; más espacio para descargas offline.</li>
              <li>Conexión a internet para el catálogo y las extensiones.</li>
            </ul>
            <p className="mt-4 text-xs leading-relaxed text-white/35">
              Los APK se publican firmados en el repositorio oficial de GitHub.
            </p>
          </aside>
        </section>
      </main>
      <Footer />
    </>
  );
}
