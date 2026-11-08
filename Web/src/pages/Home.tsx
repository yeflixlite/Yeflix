import { Download, Puzzle, WifiOff, Zap } from 'lucide-react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import Hero from '../components/Hero';

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
      </main>
      <Footer />
    </>
  );
}
