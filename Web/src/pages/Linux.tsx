import { useState } from 'react';
import { Check, Copy, Info, ShieldCheck, Terminal } from 'lucide-react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import DownloadCard from '../components/DownloadCard';
import { linuxAssets, release } from '../data/releases';

const INSTALL_COMMAND =
  'curl -fsSL https://raw.githubusercontent.com/yeflixlite/Yeflix/main/scripts/install-linux.sh | sh';

const appImageSteps = [
  'Descarga el archivo .AppImage.',
  'Clic derecho → Propiedades → Permisos y marca «Permitir ejecutar como programa» (o ejecuta chmod +x en la terminal).',
  'Haz doble clic en el archivo para abrir Yeflix.',
];

const tarballSteps = [
  'Extrae el .tar.gz en la carpeta que prefieras.',
  'Entra a la carpeta y haz doble clic en «yeflix» (o ejecuta ./yeflix en la terminal).',
  'Listo: no hay que instalar nada más, el reproductor ya viene incluido.',
];

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const area = document.createElement('textarea');
      area.value = text;
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      document.execCommand('copy');
      document.body.removeChild(area);
    }
    setCopied(true);
    window.setTimeout(() => setCopied(false), 2000);
  };

  return (
    <button
      type="button"
      onClick={copy}
      aria-label="Copiar comando"
      className="inline-flex shrink-0 items-center gap-2 rounded-lg border border-white/15 bg-white/[0.06] px-3 py-2 text-xs font-semibold text-white/80 transition-colors hover:border-white/30 hover:bg-white/10"
    >
      {copied ? <Check className="h-4 w-4 text-emerald-400" /> : <Copy className="h-4 w-4" />}
      {copied ? 'Copiado' : 'Copiar'}
    </button>
  );
}

export default function Linux() {
  return (
    <>
      <Navbar />
      <main className="mx-auto w-full max-w-6xl px-4 py-14 sm:px-6">
        <div className="max-w-2xl">
          <span className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.05] px-3 py-1 text-xs font-medium text-white/60">
            <Terminal className="h-3.5 w-3.5" /> Linux · v{release.version} build {release.build}
          </span>
          <h1 className="mt-5 text-3xl font-extrabold tracking-tight text-white sm:text-5xl">
            Descargar para Linux
          </h1>
          <p className="mt-4 text-base leading-relaxed text-white/55">
            Disponible para distribuciones modernas de 64 bits: Ubuntu, Debian, Linux Mint,
            Fedora, Arch, openSUSE, Pop!_OS y derivados. Instálalo con un solo comando o
            descarga el archivo que prefieras: en ambos casos el reproductor y sus librerías
            ya vienen incluidos.
          </p>
        </div>

        <section className="mt-10 rounded-2xl border border-white/[0.08] bg-[#0d0d13] p-5 sm:p-6">
          <div className="flex items-center gap-2 text-sm font-semibold text-white">
            <Terminal className="h-4 w-4 text-brand-strong" /> Instalación en un comando
          </div>
          <p className="mt-2 text-sm leading-relaxed text-white/50">
            Pega esto en tu terminal. Descarga Yeflix, lo instala en{' '}
            <code className="rounded bg-black/40 px-1.5 py-0.5 text-xs">~/.local/opt/yeflix</code>{' '}
            y lo agrega al menú de aplicaciones. No necesitas instalar librerías aparte.
          </p>
          <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center">
            <pre className="min-w-0 flex-1 overflow-x-auto rounded-xl border border-white/10 bg-black/50 px-4 py-3 text-xs text-white/80">
              <code>{INSTALL_COMMAND}</code>
            </pre>
            <CopyButton text={INSTALL_COMMAND} />
          </div>
          <p className="mt-3 text-xs leading-relaxed text-white/35">
            Después podrás abrir Yeflix desde el menú de aplicaciones o escribiendo{' '}
            <code className="rounded bg-black/40 px-1.5 py-0.5">yeflix</code> en la terminal.
          </p>
        </section>

        <section className="mt-10">
          <h2 className="text-lg font-semibold text-white">O descarga el archivo</h2>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            {linuxAssets.map((asset) => (
              <DownloadCard key={asset.id} asset={asset} />
            ))}
          </div>
        </section>

        <section className="mt-14 grid gap-8 md:grid-cols-[1.1fr_1fr]">
          <div>
            <h2 className="text-lg font-semibold text-white">Cómo usarlo</h2>

            <h3 className="mt-5 text-sm font-semibold text-white/80">AppImage</h3>
            <ol className="mt-3 space-y-3">
              {appImageSteps.map((step, index) => (
                <li key={step} className="flex gap-3 text-sm leading-relaxed text-white/55">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-white/[0.07] text-xs font-semibold text-white/80">
                    {index + 1}
                  </span>
                  {step}
                </li>
              ))}
            </ol>

            <h3 className="mt-7 text-sm font-semibold text-white/80">Portable (.tar.gz)</h3>
            <ol className="mt-3 space-y-3">
              {tarballSteps.map((step, index) => (
                <li key={step} className="flex gap-3 text-sm leading-relaxed text-white/55">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-white/[0.07] text-xs font-semibold text-white/80">
                    {index + 1}
                  </span>
                  {step}
                </li>
              ))}
            </ol>

            <div className="mt-6 flex items-start gap-3 rounded-2xl border border-sky-400/20 bg-sky-400/[0.06] p-4 text-sm text-white/60">
              <Info className="mt-0.5 h-5 w-5 shrink-0 text-sky-300" />
              <p>
                Si el AppImage no abre en Ubuntu 23.04 o superior, instala FUSE con
                <code className="mx-1 rounded bg-black/40 px-1.5 py-0.5 text-xs">sudo apt install libfuse2</code>
                o ejecútalo con
                <code className="mx-1 rounded bg-black/40 px-1.5 py-0.5 text-xs">--appimage-extract-and-run</code>.
              </p>
            </div>
          </div>

          <aside className="rounded-2xl border border-white/[0.08] bg-[#0d0d13] p-5">
            <div className="flex items-center gap-2 text-sm font-semibold text-white">
              <ShieldCheck className="h-4 w-4 text-brand-strong" /> Requisitos
            </div>
            <ul className="mt-3 space-y-2 text-sm text-white/50">
              <li>Linux de 64 bits (x86_64).</li>
              <li>glibc 2.35 o superior (Ubuntu 22.04+, Debian 12+, Fedora 36+…).</li>
              <li>Escritorio con GTK 3 (GNOME, KDE, XFCE, Cinnamon…).</li>
              <li>~350 MB libres para instalar.</li>
            </ul>
            <div className="mt-4 flex items-start gap-2 rounded-xl border border-emerald-400/20 bg-emerald-400/[0.06] p-3 text-xs leading-relaxed text-white/55">
              <Check className="mt-0.5 h-4 w-4 shrink-0 text-emerald-400" />
              <p>
                El reproductor (libmpv) y sus dependencias vienen incluidos en el AppImage,
                en el portable y en el instalador. No hay que instalar nada aparte.
              </p>
            </div>
            <p className="mt-4 text-xs leading-relaxed text-white/35">
              Por ahora no hay versión para ARM (Raspberry Pi, algunas laptops ARM).
              Si la necesitas, se puede compilar más adelante.
            </p>
          </aside>
        </section>
      </main>
      <Footer />
    </>
  );
}
