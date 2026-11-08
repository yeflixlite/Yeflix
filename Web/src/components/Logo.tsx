const base = import.meta.env.BASE_URL;

export default function Logo() {
  return (
    <span className="inline-flex items-center gap-2.5">
      <img
        src={`${base}yeflix-icon.png`}
        alt=""
        aria-hidden="true"
        className="h-9 w-9 rounded-xl ring-1 ring-white/10"
      />
      <img src={`${base}yeflix-logo.png`} alt="Yeflix" className="h-6 w-auto" />
    </span>
  );
}
