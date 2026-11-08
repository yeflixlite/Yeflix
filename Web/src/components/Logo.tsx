export default function Logo({ compact = false }: { compact?: boolean }) {
  return (
    <span className="inline-flex items-center gap-2.5">
      <svg
        viewBox="0 0 64 64"
        aria-hidden="true"
        className="h-9 w-9 rounded-xl bg-[#0f0f15] p-1 ring-1 ring-white/10"
      >
        <path d="M15 13h9.2l7.9 13.4L40 13h9L36.4 35.2V51h-8.8V35.2L15 13z" fill="#e50914" />
      </svg>
      <span className="text-[17px] font-bold tracking-[0.22em] text-white">
        {compact ? 'YFLX' : 'YEFLIX'}
      </span>
    </span>
  );
}
