import { Apple, Cpu, Download, FileArchive, HardDrive, Package, Smartphone, Tablet } from 'lucide-react';
import type { Asset } from '../data/releases';
import { assetUrl } from '../data/releases';

const icons = {
  phone: Smartphone,
  tablet: Tablet,
  cpu: Cpu,
  installer: Package,
  portable: HardDrive,
  mac: Apple,
  archive: FileArchive,
};

export default function DownloadCard({ asset }: { asset: Asset }) {
  const Icon = icons[asset.icon];

  return (
    <article className="group relative flex flex-col rounded-2xl border border-white/[0.08] bg-[#0e0e14] p-5 transition-colors hover:border-white/20">
      {asset.badge ? (
        <span className="absolute right-4 top-4 rounded-full bg-brand/15 px-2.5 py-1 text-[11px] font-semibold text-brand-strong ring-1 ring-brand/30">
          {asset.badge}
        </span>
      ) : null}

      <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-white/[0.06] ring-1 ring-white/10">
        <Icon className="h-5 w-5 text-white/80" />
      </div>

      <h3 className="mt-4 text-base font-semibold text-white">{asset.name}</h3>
      <p className="mt-1.5 flex-1 text-sm leading-relaxed text-white/50">{asset.description}</p>

      <div className="mt-5 flex items-center justify-between gap-3">
        <span className="text-xs font-medium text-white/40">{asset.size}</span>
        <a
          href={assetUrl(asset)}
          className="inline-flex items-center gap-2 rounded-full bg-brand px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-brand-strong"
        >
          <Download className="h-4 w-4" />
          Descargar
        </a>
      </div>
    </article>
  );
}
