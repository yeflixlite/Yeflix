import { Apple, Clock, ShieldCheck } from 'lucide-react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';

export default function Macos() {
  return (
    <>
      <Navbar />
      <main className="mx-auto w-full max-w-6xl px-4 py-14 sm:px-6">
        <div className="max-w-2xl">
          <span className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.05] px-3 py-1 text-xs font-medium text-white/60">
            <Apple className="h-3.5 w-3.5" /> macOS · próximamente
          </span>
          <h1 className="mt-5 text-3xl font-extrabold tracking-tight text-white sm:text-5xl">
            macOS: próximamente
          </h1>
          <p className="mt-4 text-base leading-relaxed text-white/55">
            Todavía no hay una versión oficial de Yeflix para macOS. Estamos
            trabajando en ella, pero no tenemos un Mac para probarla y no
            queremos publicar algo que falle en tu equipo.
          </p>
        </div>

        <section className="mt-10 rounded-2xl border border-white/[0.08] bg-[#0d0d13] p-6">
          <div className="flex items-start gap-3">
            <Clock className="mt-0.5 h-6 w-6 shrink-0 text-brand-strong" />
            <div>
              <h2 className="text-base font-semibold text-white">
                Aún no hay descarga para macOS
              </h2>
              <p className="mt-2 text-sm leading-relaxed text-white/55">
                Cuando la compilación esté lista y probada, aparecerá aquí con su
                enlace de descarga. Mientras tanto, puedes usar Yeflix en Android,
                Windows o Linux.
              </p>
            </div>
          </div>
        </section>

        <section className="mt-10 grid gap-8 md:grid-cols-[1.1fr_1fr]">
          <div>
            <h2 className="text-lg font-semibold text-white">Lo que incluirá</h2>
            <ul className="mt-4 space-y-3 text-sm leading-relaxed text-white/55">
              <li className="flex gap-3">
                <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-brand-strong" />
                La misma app de Yeflix: reproductor, descargas offline y extensiones.
              </li>
              <li className="flex gap-3">
                <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-brand-strong" />
                Compatible con Apple Silicon (M1 o superior) y Mac con Intel.
              </li>
              <li className="flex gap-3">
                <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-brand-strong" />
                Sin programas extra: el reproductor y sus librerías van incluidos.
              </li>
            </ul>
          </div>

          <aside className="rounded-2xl border border-white/[0.08] bg-[#0d0d13] p-5">
            <div className="flex items-center gap-2 text-sm font-semibold text-white">
              <ShieldCheck className="h-4 w-4 text-brand-strong" /> Requisitos previstos
            </div>
            <ul className="mt-3 space-y-2 text-sm text-white/50">
              <li>macOS 10.15 (Catalina) o superior.</li>
              <li>Apple Silicon o Intel de 64 bits.</li>
              <li>~150 MB libres para instalar.</li>
            </ul>
            <p className="mt-4 text-xs leading-relaxed text-white/35">
              Estos requisitos pueden cambiar antes del lanzamiento.
            </p>
          </aside>
        </section>
      </main>
      <Footer />
    </>
  );
}
