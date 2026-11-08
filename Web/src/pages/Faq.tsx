import { ChevronDown } from 'lucide-react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import { release } from '../data/releases';

const faqs = [
  {
    q: '¿Cómo instalo el APK en Android?',
    a: 'Descarga el archivo, ábrelo desde la notificación o tu gestor de archivos y acepta la instalación. Si Android bloquea la instalación, activa “Instalar apps desconocidas” para el navegador o gestor que estés usando.',
  },
  {
    q: '¿Qué arquitectura debo elegir?',
    a: 'La mayoría de teléfonos y tablets modernos usan arm64-v8a. Si tu equipo es antiguo o el APK no instala, prueba armeabi-v7a. x86_64 es para emuladores, Chromebooks y equipos con procesador Intel.',
  },
  {
    q: '¿Cuál es la diferencia de la versión tablet?',
    a: 'Es un APK universal optimizado para pantallas grandes. Incluye todas las arquitecturas, por eso pesa más, y ajusta la interfaz para tablets.',
  },
  {
    q: 'Windows dice que el archivo no es seguro. ¿Qué hago?',
    a: 'Es el aviso de SmartScreen porque el instalador no tiene un certificado comercial. Pulsa “Más información” y luego “Ejecutar de todos modos”. También puedes usar la versión portable en ZIP.',
  },
  {
    q: 'macOS no abre la app. ¿Qué hago?',
    a: 'La app no está firmada con un certificado de Apple, así que macOS la bloquea la primera vez. Ábrela con clic derecho → Abrir, o ve a Ajustes del Sistema → Privacidad y seguridad y pulsa “Abrir igualmente”. Si sigue bloqueada, ejecuta en Terminal: xattr -dr com.apple.quarantine /Applications/Yeflix.app',
  },
  {
    q: '¿Cómo instalo Yeflix en Linux?',
    a: 'Descarga el AppImage, dale permisos de ejecución (clic derecho → Propiedades → Permisos) y ábrelo. Si prefieres instalarlo en el menú, usa el .tar.gz y ejecuta ./install.sh. En Ubuntu 23.04 o superior el AppImage puede pedir libfuse2: sudo apt install libfuse2.',
  },
  {
    q: '¿La app se actualiza sola?',
    a: `Yeflix comprueba si hay versiones nuevas y te avisa. La versión actual es ${release.version} (build ${release.build}); puedes ver todas las versiones en GitHub Releases.`,
  },
  {
    q: '¿Cómo agrego las extensiones?',
    a: `Abre Ajustes → Extensiones → Repositorios, pulsa “+” y pega ${release.extensions}. Luego recarga y podrás instalar las extensiones disponibles.`,
  },
  {
    q: '¿Yeflix aloja películas o series?',
    a: 'No. Yeflix es un reproductor y gestor de catálogo; el contenido proviene de las extensiones y fuentes de terceros que tú decidas agregar.',
  },
];

export default function Faq() {
  return (
    <>
      <Navbar />
      <main className="mx-auto w-full max-w-3xl px-4 py-14 sm:px-6">
        <h1 className="text-3xl font-extrabold tracking-tight text-white sm:text-5xl">
          Preguntas frecuentes
        </h1>
        <p className="mt-4 text-base text-white/55">
          Todo lo necesario para instalar Yeflix en Android, Windows, macOS o Linux.
        </p>

        <div className="mt-10 space-y-3">
          {faqs.map((faq) => (
            <details
              key={faq.q}
              className="group rounded-2xl border border-white/[0.08] bg-[#0d0d13] px-5 py-4 open:border-white/15"
            >
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-sm font-semibold text-white">
                {faq.q}
                <ChevronDown className="h-4 w-4 shrink-0 text-white/40 transition-transform group-open:rotate-180" />
              </summary>
              <p className="mt-3 text-sm leading-relaxed text-white/55">{faq.a}</p>
            </details>
          ))}
        </div>
      </main>
      <Footer />
    </>
  );
}
