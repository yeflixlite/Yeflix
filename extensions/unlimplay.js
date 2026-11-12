// ==MiruExtension==
// @name         UnLimPlay
// @version      v0.2.0
// @author       YeaniFlix
// @lang         es
// @license      MIT
// @package      unlimplay
// @type         bangumi
// @icon         https://unlimplay.com/favicon.ico
// @webSite      https://unlimplay.com
// @nsfw         false
// ==/MiruExtension==

// UnLimPlay (https://unlimplay.com) — Agregador de fuentes HLS para películas y series.
//
// MODO DUAL DE OPERACIÓN:
// 1. MODO DIRECTO (Predeterminado / Sin Clave):
//    Extrae el catálogo de servidores directamente de los embeds públicos de UnLimPlay:
//      Películas: https://unlimplay.com/f/embed/movie/{id}
//      Series:    https://unlimplay.com/f/embed/tv/{id}/{temporada}/{episodio}
//    Utiliza emulación de navegación iframe (Sec-Fetch) para desbloquear las fuentes
//    sin necesidad de cuenta ni clave API.
//
// 2. MODO API OFICIAL (Opcional):
//    Si configuras tu clave "ulp_XXXXXX" en los ajustes de la extensión,
//    utiliza la API JSON oficial en /api/v1/.
//
// Servidores soportados: Direct (HLS nativo), StreamWish/HLSWish, VidHide/EarnVids,
// Filemoon/Byse, VOE, Goodstream, Streamtape, MediaFire y más.

const ULP_SITE   = "https://unlimplay.com";
const TMDB_API   = "https://api.themoviedb.org/3";
const TMDB_IMG   = "https://image.tmdb.org/t/p/w500";
const TMDB_KEY   = "4ef0d7355d9ffb5151e987764708ce96"; // Public read-only key
const UA         = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

// Cabeceras que emulan una carga legítima de iframe cross-site (evita el bloqueo 403)
const EMBED_HEADERS = {
  "User-Agent": UA,
  "Referer": "https://cuevana.biz/",
  "Sec-Fetch-Dest": "iframe",
  "Sec-Fetch-Mode": "navigate",
  "Sec-Fetch-Site": "cross-site",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "es-ES,es;q=0.9,en;q=0.8"
};

const SW_RE  = /streamwish|embedwish|hglink|streamhg|playnixes|hglamioz|medixiru|awish|hgcloud|sfastwish|wishfast|streamhide|hlswish|vibuxer/i;
const VH_RE  = /vidhide|earnvids|morencius|callistanise|minochinos|vsharea|vhide|vid-hide|vidhideplus|vidhidefast/i;
const FM_RE  = /byse|filemoon|filemooon|moonplayer/i;
const VOE_RE = /voe\.sx|v-?o-?e\.|derricknationtop|johnfullwonder|charlestoughrace|timmaybealready|richardquestionbuilding|nicolehappyoutside|rebeccapracticeloss/i;
const ST_RE  = /streamtape/i;
const GS_RE  = /goodstream/i;

export default class extends Extension {

  async createFilter() { return []; }

  async _apiKey() {
    try {
      const k = await this.getSetting("api_key");
      return String(k || "").trim();
    } catch (_) {
      return "";
    }
  }

  async _registerSettings() {
    try {
      await this.registerSetting([
        {
          key: "api_key",
          title: "Clave de API UnLimPlay (Opcional)",
          desc: "Opcional: Si tienes una clave ulp_XXXXXX privada. Si la dejas vacía, la extensión funciona gratis extrayendo directamente.",
          type: "input",
          defaultValue: "",
        },
      ]);
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LATEST — Trending de la semana vía TMDb
  // ──────────────────────────────────────────────────────────────────────────
  async latest(page) {
    await this._registerSettings();
    const p = Math.max(1, parseInt(page) || 1);
    const [movies, tv] = await Promise.all([
      this._tmdb("/trending/movie/week?language=es-MX&page=" + p).catch(() => null),
      this._tmdb("/trending/tv/week?language=es-MX&page=" + p).catch(() => null),
    ]);
    const out = [];
    for (const r of (movies && movies.results) || []) out.push(this._tmdbCard(r, "movie"));
    for (const r of (tv && tv.results) || []) out.push(this._tmdbCard(r, "tv"));
    return this._dedupe(out);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SEARCH — Búsqueda por título vía TMDb
  // ──────────────────────────────────────────────────────────────────────────
  async search(kw, page) {
    await this._registerSettings();
    const q = String(kw || "").trim();
    if (!q) return [];
    const p = Math.max(1, parseInt(page) || 1);
    const [movies, tv] = await Promise.all([
      this._tmdb("/search/movie?language=es-MX&query=" + encodeURIComponent(q) + "&page=" + p).catch(() => null),
      this._tmdb("/search/tv?language=es-MX&query=" + encodeURIComponent(q) + "&page=" + p).catch(() => null),
    ]);
    const out = [];
    for (const r of (movies && movies.results) || []) out.push(this._tmdbCard(r, "movie"));
    for (const r of (tv && tv.results) || []) out.push(this._tmdbCard(r, "tv"));
    return this._dedupe(out);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DETAIL — Información y lista de episodios
  // ──────────────────────────────────────────────────────────────────────────
  async detail(url) {
    const { kind, id } = this._parseUrl(url);
    if (!id) throw new Error("URL de UnLimPlay inválida: " + url);

    if (kind === "movie") {
      const data = await this._tmdb("/movie/" + id + "?language=es-MX").catch(() => null);
      const title = (data && (data.title || data.name)) || ("Película " + id);
      const cover = data && data.poster_path ? TMDB_IMG + data.poster_path : "";
      const desc   = (data && data.overview) || "";
      return {
        title: title,
        cover: cover,
        desc: desc,
        episodes: [
          {
            title: "Ver Película",
            urls: [{ name: "Ver online", url: url }],
          },
        ],
      };
    }

    // Serie / Anime
    const data = await this._tmdb("/tv/" + id + "?language=es-MX").catch(() => null);
    const title = (data && (data.name || data.title)) || ("Serie " + id);
    const cover = data && data.poster_path ? TMDB_IMG + data.poster_path : "";
    const desc   = (data && data.overview) || "";
    const seasons = (data && data.seasons) || [];

    const episodeGroups = [];
    for (const season of seasons) {
      const sNum = season.season_number;
      if (sNum === 0) continue;
      const epCount = season.episode_count || 0;
      if (epCount === 0) continue;
      const eps = [];
      for (let e = 1; e <= epCount; e++) {
        eps.push({
          name: "T" + sNum + "E" + e,
          url: "ulp://tv/" + id + "/" + sNum + "/" + e,
        });
      }
      episodeGroups.push({
        title: "Temporada " + sNum,
        urls: eps,
      });
    }

    if (!episodeGroups.length) {
      episodeGroups.push({
        title: "Temporada 1",
        urls: [{ name: "T1E1", url: "ulp://tv/" + id + "/1/1" }],
      });
    }

    return {
      title: title,
      cover: cover,
      desc: desc,
      episodes: episodeGroups,
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // WATCH — Resolución de fuentes (Directo o API)
  // ──────────────────────────────────────────────────────────────────────────
  async watch(url) {
    // Si la URL es un embed directo ya resuelto (procedente del selector X-Servers)
    if (!/^ulp:\/\//i.test(url) && (this._isKnownHost(url) || /\.m3u8/i.test(url))) {
      return await this._resolveEmbed(url, ULP_SITE + "/");
    }

    const { kind, id, season, episode } = this._parseUrl(url);
    if (!id) return this._err("URL inválida: " + url);

    const apiKey = await this._apiKey();
    let sources = [];

    // Modo 1: API Oficial (si el usuario ingresó clave)
    if (apiKey && apiKey.startsWith("ulp_")) {
      try {
        const apiUrl = kind === "movie" 
          ? ULP_SITE + "/api/v1/movie/" + id 
          : ULP_SITE + "/api/v1/tv/" + id + "/" + season + "/" + episode;
        const resp = await this._apiGet(apiUrl, apiKey);
        if (resp && Array.isArray(resp.sources)) {
          sources = resp.sources;
        }
      } catch (_) {}
    }

    // Modo 2: Extracción directa de Embed (Predeterminado y Gratuito)
    if (!sources.length) {
      try {
        const embedUrl = kind === "movie"
          ? ULP_SITE + "/f/embed/movie/" + id
          : ULP_SITE + "/f/embed/tv/" + id + "/" + season + "/" + episode;
        
        sources = await this._extractFromEmbed(embedUrl);
      } catch (e) {
        return this._err("Error conectando con UnLimPlay: " + String(e));
      }
    }

    if (!sources.length) {
      return this._err("UnLimPlay: No hay servidores disponibles para este título.");
    }

    // Priorizar fuentes HLS y ordenar por servidor
    const sorted = this._sortSources(sources);
    const serverMap = {};
    for (const s of sorted) {
      const label = this._serverLabel(s);
      if (s.url) serverMap[label] = s.url;
    }

    // Agrupar por idioma
    const langGroups = this._groupByLang(sorted);
    const primaryLang = langGroups[0] || { lang: "", sources: sorted };
    const langLabel = this._langLabel(primaryLang.lang);

    // Resolver el servidor principal
    let resolved = null;
    let chosenServerLabel = "";

    for (const s of primaryLang.sources) {
      if (!s.url) continue;
      chosenServerLabel = this._serverLabel(s);
      
      // Si ya es un m3u8 directo (servidor Direct / HlsWish de UnLimPlay)
      if (/\.m3u8/i.test(s.url)) {
        resolved = {
          type: "hls",
          url: s.url,
          headers: { Referer: ULP_SITE + "/", "User-Agent": UA },
        };
        break;
      }

      // Si es un embed remoto, resolverlo
      try {
        const r = await this._resolveEmbed(s.url, ULP_SITE + "/");
        if (r && r.url && !String(r.url).startsWith("error://")) {
          resolved = r;
          break;
        }
      } catch (_) {}
    }

    if (!resolved || !resolved.url || String(resolved.url).startsWith("error://")) {
      return {
        type: "hls",
        url: "error://Ningún servidor respondió correctamente. Prueba a cambiar de servidor.",
        headers: {
          "X-Servers": JSON.stringify(serverMap),
          "X-Language": langLabel,
        },
      };
    }

    resolved.headers = Object.assign({}, resolved.headers || {}, {
      "X-Servers": JSON.stringify(serverMap),
      "X-Primary-Server": chosenServerLabel,
      "X-Language": langLabel,
    });
    return resolved;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // EXTRACCIÓN DEL OBJETO EMBEDS DESDE EL IFRAME DE UNLIMPLAY
  // ──────────────────────────────────────────────────────────────────────────
  async _extractFromEmbed(embedUrl) {
    let html = "";
    try {
      html = await this.request("", {
        headers: Object.assign({}, EMBED_HEADERS, { "Miru-Url": embedUrl }),
      });
      if (typeof html !== "string") html = "";
    } catch (_) {
      return [];
    }

    if (!html) return [];

    // Buscar const EMBEDS = { ... };
    const m = html.match(/const\s+EMBEDS\s*=\s*(\{[\s\S]*?\});/);
    if (!m) return [];

    let data;
    try {
      data = JSON.parse(m[1]);
    } catch (_) {
      return [];
    }

    const sources = [];
    // Formato de data: { "latino": { "direct": "url", "streamwish": "url" }, ... }
    for (const lang of Object.keys(data)) {
      const serverDict = data[lang];
      if (!serverDict || typeof serverDict !== "object") continue;

      for (const sName of Object.keys(serverDict)) {
        const sUrl = String(serverDict[sName] || "").trim();
        if (!sUrl || sUrl.startsWith("javascript:")) continue;

        // Omitir enlaces a páginas de descarga si no son de streaming
        if (/mf\.php|\.zip|download/i.test(sUrl) && !/m3u8/i.test(sUrl)) continue;

        const isHls = /\.m3u8/i.test(sUrl) || /direct|hlswish|cps\.php/i.test(sName);
        sources.push({
          server: sName.charAt(0).toUpperCase() + sName.slice(1),
          lang: lang,
          type: isHls ? "hls" : "mp4",
          url: sUrl,
        });
      }
    }

    return sources;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LLAMADA A LA API JSON DE UNLIMPLAY
  // ──────────────────────────────────────────────────────────────────────────
  async _apiGet(url, apiKey) {
    let resp = "";
    try {
      resp = await this.request("", {
        headers: {
          "Miru-Url": url,
          "X-API-Key": apiKey,
          "Accept": "application/json",
          "User-Agent": UA,
          "Referer": ULP_SITE + "/",
        },
      });
    } catch (e) {
      throw e;
    }
    if (typeof resp === "string") {
      try { return JSON.parse(resp); } catch (_) { return resp; }
    }
    return resp;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LLAMADA A TMDB
  // ──────────────────────────────────────────────────────────────────────────
  async _tmdb(path) {
    const url = TMDB_API + path + (path.indexOf("?") === -1 ? "?" : "&") + "api_key=" + TMDB_KEY;
    let resp = "";
    try {
      resp = await this.request("", {
        headers: {
          "Miru-Url": url,
          "Accept": "application/json",
          "User-Agent": UA,
        },
      });
    } catch (_) {
      return null;
    }
    if (typeof resp === "string") {
      try { return JSON.parse(resp); } catch (_) { return null; }
    }
    return resp || null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // RESOLUCIÓN DE SERVIDORES DE STREAMING
  // ──────────────────────────────────────────────────────────────────────────
  async _resolveEmbed(embedUrl, referer) {
    const src = String(embedUrl || "").trim();
    if (!src) return null;

    if (/\.m3u8(\?|#|$)/i.test(src)) {
      return { type: "hls", url: src, headers: { Referer: referer, "User-Agent": UA } };
    }
    if (/\.mp4(\?|#|$)/i.test(src)) {
      return { type: "mp4", url: src, headers: { Referer: referer, "User-Agent": UA } };
    }

    // VidHide / Earnvids / Morencius
    if (VH_RE.test(src)) {
      const r = await this._vidhide(src);
      if (r) return r;
    }
    // StreamWish / HlsWish / Mirrors
    if (SW_RE.test(src)) {
      const r = await this._streamwish(src, referer);
      if (r) return r;
    }
    // Filemoon / Byse
    if (FM_RE.test(src)) {
      const r = await this._filemoon(src, referer);
      if (r) return r;
    }
    // VOE
    if (VOE_RE.test(src)) {
      const r = await this._voe(src);
      if (r) return r;
    }
    // Streamtape
    if (ST_RE.test(src)) {
      const r = await this._streamtape(src);
      if (r) return r;
    }

    // Scraping genérico de .m3u8 en el HTML
    let html = "";
    try {
      html = await this.request("", {
        headers: { "Miru-Url": src, "Referer": referer, "User-Agent": UA },
      });
      if (typeof html !== "string") html = "";
    } catch (_) { html = ""; }

    if (html) {
      if (/eval\(function\(p,a,c,k,e/.test(html)) {
        const unpacked = this._unpack(html);
        if (unpacked) {
          const m3u8 = unpacked.match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)/i);
          if (m3u8) return { type: "hls", url: m3u8[1], headers: { Referer: src, "User-Agent": UA } };
        }
      }
      const m = html.match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)/i);
      if (m) return { type: "hls", url: m[1], headers: { Referer: src, "User-Agent": UA } };
      const mp4 = html.match(/["'](https?:\/\/[^"']+\.mp4[^"']*)/i);
      if (mp4) return { type: "mp4", url: mp4[1], headers: { Referer: src, "User-Agent": UA } };
    }

    return null;
  }

  async _vidhide(url) {
    try {
      const id = (url.split("/").pop() || "").replace(/\.html?$/i, "").split("?")[0];
      if (!id) return null;
      let html = "";
      try {
        html = await this.request("", { headers: { "Miru-Url": url, "Referer": "https://vidhide.com/", "User-Agent": UA } });
        if (typeof html !== "string") html = "";
      } catch (_) {}
      if (html) {
        const m = html.match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)/i);
        if (m) return { type: "hls", url: m[1], headers: { Referer: url, "User-Agent": UA } };
      }
      return null;
    } catch (_) { return null; }
  }

  async _streamwish(url, referer) {
    const SW_MIRRORS = ["playnixes.com", "hglamioz.com", "medixiru.com", "embedwish.com", "streamwish.to", "hglink.to"];
    try {
      const id = (url.split("/").filter(Boolean).pop() || "").replace(/\.html?$/i, "").split("?")[0];
      if (!id) return null;
      for (const host of SW_MIRRORS) {
        const embedUrl = "https://" + host + "/e/" + id;
        let html = "";
        try {
          html = await this.request("", {
            headers: { "Miru-Url": embedUrl, "Referer": referer || "https://www.google.com/", "User-Agent": UA },
          });
          if (typeof html !== "string" || html.length < 500) html = "";
        } catch (_) { html = ""; }
        if (!html) continue;
        const unpacked = this._unpack(html) || html;
        const block = unpacked.match(/sources\s*[:=]\s*\[([^\]]*)\]/) || unpacked.match(/links\s*=\s*\{([^}]*)\}/);
        if (block) {
          const m3u8 = block[1].match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)/i);
          if (m3u8) return { type: "hls", url: m3u8[1], headers: { Referer: "https://streamwish.to/", "User-Agent": UA } };
        }
        const m3u8 = unpacked.match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)/i);
        if (m3u8) return { type: "hls", url: m3u8[1], headers: { Referer: "https://streamwish.to/", "User-Agent": UA } };
      }
      return null;
    } catch (_) { return null; }
  }

  async _filemoon(url, referer) {
    try {
      let html = "";
      try {
        html = await this.request("", { headers: { "Miru-Url": url, "Referer": referer || ULP_SITE + "/", "User-Agent": UA } });
        if (typeof html !== "string") html = "";
      } catch (_) {}
      if (!html) return null;
      const unpacked = this._unpack(html) || html;
      const m = unpacked.match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)/i);
      if (m) return { type: "hls", url: m[1], headers: { Referer: url, "User-Agent": UA } };
      return null;
    } catch (_) { return null; }
  }

  async _voe(url) {
    const VOE_MIRRORS = ["voe.sx", "v-o-e.to", "derricknationtop.com", "johnfullwonder.com"];
    try {
      const id = (url.split("/").pop() || "").replace(/\.html?$/i, "").split("?")[0];
      if (!id) return null;
      for (const mirror of VOE_MIRRORS) {
        const embedUrl = "https://" + mirror + "/e/" + id;
        let html = "";
        try {
          html = await this.request("", { headers: { "Miru-Url": embedUrl, "Referer": embedUrl, "User-Agent": UA } });
          if (typeof html !== "string") html = "";
        } catch (_) {}
        if (!html) continue;
        const m = html.match(/['"]hls['"]\s*:\s*['"]([^'"]+\.m3u8[^'"]*)['"]/i) ||
                  html.match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)/i);
        if (m) return { type: "hls", url: m[1], headers: { Referer: embedUrl, "User-Agent": UA } };
      }
      return null;
    } catch (_) { return null; }
  }

  async _streamtape(url) {
    try {
      let html = "";
      try {
        html = await this.request("", { headers: { "Miru-Url": url, "Referer": "https://streamtape.com/", "User-Agent": UA } });
        if (typeof html !== "string") html = "";
      } catch (_) {}
      if (!html) return null;
      const m = html.match(/id=["']videolink["'][^\>]*\>([^\<]+)/i) ||
                html.match(/robotlink['"]\s*\)\s*\.innerHTML\s*=\s*["']([^'"]+)/i);
      if (m) {
        let videoUrl = m[1].trim();
        if (videoUrl.startsWith("//")) videoUrl = "https:" + videoUrl;
        if (/\.mp4/i.test(videoUrl)) return { type: "mp4", url: videoUrl, headers: { Referer: "https://streamtape.com/", "User-Agent": UA } };
      }
      return null;
    } catch (_) { return null; }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UTILIDADES
  // ──────────────────────────────────────────────────────────────────────────
  _langLabel(lang) {
    const l = String(lang || "").toLowerCase().trim();
    if (!l) return "Desconocido";
    if (/lat(ino)?/.test(l)) return "Español Latino";
    if (/esp|cast(ellano)?/.test(l)) return "Español Castellano";
    if (/sub(tit)?|vose/.test(l)) return "Subtitulado";
    if (/eng|ingl/.test(l)) return "Inglés";
    return l.charAt(0).toUpperCase() + l.slice(1);
  }

  _serverLabel(source) {
    const s = String((source && source.server) || "").trim();
    const lang = this._langLabel(source && source.lang);
    if (!s) return lang;
    return s + " (" + lang + ")";
  }

  _serverRank(source) {
    const u = String((source && source.url) || "").toLowerCase();
    const n = String((source && source.server) || "").toLowerCase();
    if (n.includes("direct") || u.includes("vimeos.net")) return 0; // HLS nativo súper rápido
    if (VH_RE.test(u) || n.includes("vidhide") || n.includes("earnvids")) return 1;
    if (SW_RE.test(u) || n.includes("streamwish") || n.includes("hlswish")) return 2;
    if (FM_RE.test(u) || n.includes("filemoon")) return 3;
    if (VOE_RE.test(u) || n.includes("voe")) return 4;
    return 9;
  }

  _sortSources(sources) {
    return sources.slice().sort((a, b) => this._serverRank(a) - this._serverRank(b));
  }

  _groupByLang(sources) {
    const map = {};
    const order = [];
    for (const s of sources) {
      const lang = String(s.lang || "").toLowerCase().trim() || "unknown";
      if (!map[lang]) { map[lang] = []; order.push(lang); }
      map[lang].push(s);
    }
    const langPriority = (l) => {
      if (/lat/.test(l)) return 0;
      if (/esp|cast/.test(l)) return 1;
      if (/sub|vose/.test(l)) return 2;
      return 9;
    };
    return order
      .sort((a, b) => langPriority(a) - langPriority(b))
      .map(lang => ({ lang, sources: map[lang] }));
  }

  _isKnownHost(url) {
    return VH_RE.test(url) || SW_RE.test(url) || FM_RE.test(url) ||
           VOE_RE.test(url) || ST_RE.test(url) || GS_RE.test(url);
  }

  _parseUrl(url) {
    const s = String(url || "");
    const m = s.match(/^ulp:\/\/(movie|tv)\/([^/]+)(?:\/(\d+)\/(\d+))?/i);
    if (!m) return { kind: "movie", id: s, season: null, episode: null };
    return {
      kind: m[1].toLowerCase(),
      id: m[2],
      season: m[3] ? parseInt(m[3], 10) : null,
      episode: m[4] ? parseInt(m[4], 10) : null,
    };
  }

  _tmdbCard(result, kind) {
    const id   = result.id;
    const title = result.title || result.name || "";
    const cover = result.poster_path ? TMDB_IMG + result.poster_path : "";
    const year  = (result.release_date || result.first_air_date || "").substring(0, 4);
    return {
      title: title + (year ? " (" + year + ")" : ""),
      url: "ulp://" + kind + "/" + id,
      cover: cover,
      update: year,
    };
  }

  _unpack(html) {
    const src = String(html || "");
    const re = /eval\(function\(p,a,c,k,e[^)]*\)\{[\s\S]+?\}\((['"].+?['"])\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(['"].+?['"]\.split\(['"]\|['"]\))/;
    const m = src.match(re);
    if (!m) return null;
    try {
      let p, a, c, k;
      try { p = eval(m[1]); } catch(_) { return null; }
      a = parseInt(m[2], 10);
      c = parseInt(m[3], 10);
      try { k = eval(m[4]); } catch(_) { return null; }
      if (!Array.isArray(k)) return null;
      let result = p;
      const radix = (n, r) => {
        const chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
        let s = "";
        while (n > 0) { s = chars[n % r] + s; n = Math.floor(n / r); }
        return s || "0";
      };
      while (c--) {
        if (k[c]) {
          const regex = new RegExp("\\b" + radix(c, a) + "\\b", "g");
          result = result.replace(regex, k[c]);
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  _err(msg) {
    return { type: "hls", url: "error://" + String(msg || "Error desconocido") };
  }

  _dedupe(list) {
    const out = [];
    const seen = {};
    for (const it of list || []) {
      const k = String((it && it.url) || "");
      if (k && seen[k]) continue;
      if (k) seen[k] = true;
      out.push(it);
    }
    return out;
  }
}
