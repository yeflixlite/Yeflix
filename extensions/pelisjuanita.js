// ==MiruExtension==
// @name         Pelis
// @version      v0.1.5
// @author       YeaniFlix
// @lang         es
// @license      MIT
// @package      pelisjuanita
// @type         bangumi
// @icon         https://pelisjuanita.com/favicon.ico
// @webSite      https://pelisjuanita.com
// @nsfw         false
// ==/MiruExtension==

// PelisJuanita (https://pelisjuanita.com) - peliculas y series en espanol.
//
// La web tiene una puerta "apodo": todo /movies/ y /series/ redirige a
// inicio.php hasta que existe una sesion (cookie PHPSESSID). El POST a
// inicio.php responde 302 + Set-Cookie; por eso se manda followRedirects:false
// (la app guarda la cookie en su cookie jar y la reenvia automaticamente).
//
// Endpoints (fragmentos HTML, sin layout):
//   peliculas : /movies/movies.php?ultimas-agregadas&page=N
//               /movies/movies.php?s=<q>
//               /movies/movieInfo.php?title=<slug>            (info + servidores)
//   series    : /series/apiSeries.php?ultimas-agregadas&page=N
//               /series/apiSeries.php?s=<q>
//               /series/serieInfo.php?nombreSerie=<slug>      (info + S1E1)
//               /series/serieInfo.php?nombreSerie=<slug>&temporada=S&snum=1&enum=1
//               /series/serieInfo.php?nombreSerie=<slug>&nroTemporada=S&nroEpisodio=E
//
// Los servidores vienen en <div class='row-download' data-tipo='stream'
// data-url='<embed>'>. Se resuelven sin proxy: byse/filemoon (AES-256-GCM),
// voe, mixdrop, streamwish (CDN hls2/hls3), vidhide (packer) y vimeus.

const SITE = "https://pelisjuanita.com";
const MOVIES = SITE + "/movies/movies.php";
const SERIES = SITE + "/series/apiSeries.php";
const MOVIE_INFO = SITE + "/movies/movieInfo.php";
const SERIES_INFO = SITE + "/series/serieInfo.php";

const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

const BYSE_RE = /(byse|filemoon|filemooon|moonplayer)/i;
const VOE_RE =
  /(voe\.sx|v-?o-?e\.|derricknationtop|johnfullwonder|charlestoughrace|timmaybealready|richardquestionbuilding|nicolehappyoutside|rebeccapracticeloss|reitshof)/i;
const VOE_MIRRORS = [
  "derricknationtop.com",
  "johnfullwonder.com",
  "charlestoughrace.com",
  "timmaybealready.com",
  "richardquestionbuilding.com",
  "nicolehappyoutside.com",
  "rebeccapracticeloss.com",
];
const SW_HOSTS = [
  "playnixes.com",
  "hglamioz.com",
  "medixiru.com",
  "hglink.to",
  "streamhg.com",
  "streamwish.to",
];

export default class extends Extension {
  // ------------------------------------------------------------------ listas
  async latest(page) {
    const p = Math.max(1, parseInt(page) || 1);
    const urls = [
      [MOVIES + "?ultimas-agregadas&page=" + p, SITE + "/movies/"],
      [SERIES + "?ultimas-agregadas&page=" + p, SITE + "/series/"],
    ];
    const html = await Promise.all(
      urls.map((u) => this.get(u[0], u[1]).catch(() => ""))
    );
    return this.dedupe(
      this.cards(html[0], "movie").concat(this.cards(html[1], "serie"))
    );
  }

  async search(kw, page) {
    const text = String(kw || "").trim();
    if (!text) return [];
    const p = Math.max(1, parseInt(page) || 1);
    let out = await this.searchPage(encodeURIComponent(text), p);
    // La busqueda del sitio falla con frases largas: reintenta por palabra.
    if (!out.length) {
      const stop = ["the", "los", "las", "del", "una", "uno", "por", "para", "con", "and", "que", "el", "la", "de"];
      const tokens = text
        .toLowerCase()
        .split(/\s+/)
        .map((t) => t.replace(/[^a-z0-9áéíóúñü-]/gi, ""))
        .filter((t) => t.length > 2 && stop.indexOf(t) === -1)
        .sort((a, b) => b.length - a.length);
      for (const t of tokens) {
        out = await this.searchPage(encodeURIComponent(t), p);
        if (out.length) break;
      }
    }
    return this.dedupe(out);
  }

  async searchPage(q, p) {
    const urls = [
      [MOVIES + "?s=" + q + "&page=" + p, SITE + "/movies/"],
      [SERIES + "?s=" + q + "&page=" + p, SITE + "/series/"],
    ];
    const html = await Promise.all(
      urls.map((u) => this.get(u[0], u[1]).catch(() => ""))
    );
    return this.cards(html[0], "movie").concat(this.cards(html[1], "serie"));
  }

  // ------------------------------------------------------------------ detalle
  async detail(url, allowFallback) {
    const u = this.canonical(url);

    if (/movieInfo\.php/i.test(u)) {
      const html = await this.get(u, SITE + "/movies/", true);
      const info = this.info(html);
      const langs = this.langs(html);
      const hasServers = this.rows(html).some((s) => this.hostInfo(s.url));
      if (!hasServers && allowFallback !== false) {
        const slug0 = this.param(u, "title") || "";
        if (slug0) {
          const alt = await this.detail(
            SERIES_INFO + "?nombreSerie=" + encodeURIComponent(slug0),
            false
          );
          if (alt && alt.episodes && alt.episodes.length) {
            if (info.title) alt.title = info.title;
            return alt;
          }
        }
      }
      const groups = [];
      if (langs.length) {
        for (const lang of langs) {
          groups.push({
            title: this.langName(lang),
            urls: [
              {
                name: "Ver pelicula",
                url: u + (u.indexOf("?") === -1 ? "?" : "&") + "lang=" + encodeURIComponent(lang),
              },
            ],
          });
        }
      } else if (hasServers) {
        groups.push({
          title: "Pelicula",
          urls: [{ name: "Ver pelicula", url: u }],
        });
      }
      return {
        title: info.title || "Pelicula",
        cover: info.cover,
        desc: info.desc,
        episodes: groups,
      };
    }

    const slug = this.param(u, "nombreSerie") || this.param(u, "slug") || "";
    if (!slug) return { title: "", cover: "", desc: "", episodes: [] };

    const base = SERIES_INFO + "?nombreSerie=" + encodeURIComponent(slug);
    const html = await this.get(base, SITE + "/series/", true);
    const info = this.info(html);

    const seasons = [];
    const re = /cargarEpisodiosDeTemporada\(\s*['"]?(\d+)/g;
    let m;
    while ((m = re.exec(html))) {
      const n = parseInt(m[1], 10);
      if (!isNaN(n) && seasons.indexOf(n) === -1) seasons.push(n);
    }
    if (!seasons.length) seasons.push(1);
    seasons.sort((a, b) => a - b);

    const groups = [];
    for (const s of seasons) {
      const listUrl =
        SERIES_INFO +
        "?nombreSerie=" +
        encodeURIComponent(slug) +
        "&temporada=" +
        s +
        "&snum=1&enum=1";
      let list = "";
      try {
        list = await this.get(listUrl, SITE + "/series/", true);
      } catch (_) {
        list = "";
      }
      const eps = [];
      const seen = {};
      const re2 = /href=["']ver-serie\/[^"'\/]+\/(\d+)x(\d+)["']/g;
      let mm;
      while ((mm = re2.exec(list))) {
        const n = parseInt(mm[2], 10);
        if (isNaN(n) || seen[n]) continue;
        seen[n] = 1;
        eps.push({
          name: "Episodio " + n,
          url:
            SERIES_INFO +
            "?nombreSerie=" +
            encodeURIComponent(slug) +
            "&nroTemporada=" +
            s +
            "&nroEpisodio=" +
            n,
        });
      }
      if (eps.length) groups.push({ title: "Temporada " + s, urls: eps });
    }

    if (!groups.length && allowFallback !== false) {
      const slug0 = this.param(u, "nombreSerie") || "";
      if (slug0) {
        const alt = await this.detail(
          MOVIE_INFO + "?title=" + encodeURIComponent(slug0),
          false
        );
        if (alt && alt.episodes && alt.episodes.length) return alt;
      }
    }

    if (!groups.length) {
      const s = parseInt(this.param(u, "nroTemporada") || "1", 10) || 1;
      const e = parseInt(this.param(u, "nroEpisodio") || "1", 10) || 1;
      groups.push({
        title: "Temporada " + s,
        urls: [{ name: "Episodio " + e, url: u }],
      });
    }

    return {
      title: info.title || slug,
      cover: info.cover,
      desc: info.desc,
      episodes: groups,
    };
  }

  // ------------------------------------------------------------------ watch
  async watch(url) {
    const raw = this.fix(url);
    if (!raw) return this.err("URL vacia");

    // El reproductor pide cambiar de servidor: recibe directamente el embed.
    if (!/pelisjuanita\.com|movieInfo\.php|serieInfo\.php/i.test(raw)) {
      if (!this.hostInfo(raw)) return this.err("Servidor no soportado");
      const direct = await this.resolveEmbed(raw, SITE + "/");
      if (direct && direct.url) return direct;
      return this.err("Servidor no resoluble");
    }

    const u = this.canonical(raw);
    const isMovie = /movieInfo\.php/i.test(u);
    const referer = isMovie ? SITE + "/movies/" : SITE + "/series/";
    const html = await this.get(u, referer, true);
    if (!html) return this.err("No se pudo abrir el reproductor");

    const lang = (this.param(u, "lang") || "").toLowerCase();
    let list = [];
    for (const s of this.rows(html)) {
      const h = this.hostInfo(s.url);
      if (!h) continue;
      if (lang && (s.lang || "").toLowerCase() !== lang) continue;
      list.push({ name: h.name, url: s.url, lang: s.lang || "" });
    }
    if (!list.length) return this.err("Sin servidores disponibles");

    const map = {};
    for (const s of list) {
      let label = s.name;
      let n = 2;
      while (map[label]) label = s.name + " #" + n++;
      s.label = label;
      map[label] = s.url;
    }
    let langLabel = lang ? this.langName(lang) : "";
    if (!langLabel) {
      const ls = {};
      for (const s of list) if (s.lang) ls[(s.lang || "").toLowerCase()] = true;
      const keys = Object.keys(ls);
      if (keys.length === 1) langLabel = this.langName(keys[0]);
    }
    const extra = { "X-Servers": JSON.stringify(map) };
    if (langLabel) extra["X-Language"] = langLabel;

    const ordered = list.slice().sort((a, b) => this.rankHost(a.url) - this.rankHost(b.url));
    for (const s of ordered) {
      let r = null;
      try {
        r = await this.resolveEmbed(s.url, referer);
      } catch (_) {
        r = null;
      }
      if (r && r.url) {
        r.headers = Object.assign({}, r.headers, extra, {
          "X-Primary-Server": s.label,
        });
        return r;
      }
    }
    return Object.assign(this.err("Ningun servidor resoluble"), { headers: extra });
  }

  langs(html) {
    const out = [];
    for (const s of this.rows(html)) {
      if (!this.hostInfo(s.url)) continue;
      const l = (s.lang || "").toLowerCase();
      if (!l) continue;
      if (out.indexOf(l) === -1) out.push(l);
    }
    return out;
  }

  langName(lang) {
    const l = String(lang || "").toLowerCase();
    if (l.indexOf("latino") !== -1) return "Español Latino";
    if (l.indexOf("castellano") !== -1) return "Español Castellano";
    if (l.indexOf("sub") !== -1) return "Subtitulada";
    if (l.indexOf("ingl") !== -1 || l.indexOf("english") !== -1) return "Inglés";
    if (l.indexOf("port") !== -1) return "Portugués";
    return l.charAt(0).toUpperCase() + l.slice(1);
  }

  hostInfo(u) {
    const s = String(u || "");
    if (/bysesukior|byse\.|filemoon|filemooon|moonplayer/i.test(s)) {
      return { key: "filemoon", name: "Filemoon" };
    }
    if (VOE_RE.test(s)) return { key: "voe", name: "Voe" };
    if (/streamwish|hglink|streamhg|playnixes|hglamioz|medixiru|awish/i.test(s)) {
      return { key: "streamwish", name: "StreamWish" };
    }
    if (/vidhide|earnvids|morencius|callistanise|minochinos|vsharea|vhide|vid-hide/i.test(s)) {
      return { key: "vidhide", name: "VidHide" };
    }
    return null;
  }

  // ------------------------------------------------------------------ sesion
  async ensure() {
    if (this._auth) return this._auth;
    this._auth = (async () => {
      try {
        await this.request("", {
          method: "post",
          data: "apodo=" + encodeURIComponent("Yeflix" + (Date.now() % 100000)),
          followRedirects: false,
          headers: {
            "Miru-Url": SITE + "/inicio.php",
            "Content-Type": "application/x-www-form-urlencoded",
            "Referer": SITE + "/inicio.php",
            "Origin": SITE,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "es-MX,es;q=0.9,en;q=0.8",
            "User-Agent": UA,
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-User": "?1",
            "Upgrade-Insecure-Requests": "1",
          },
        });
      } catch (_) {}
      return true;
    })();
    return this._auth;
  }

  isGate(res) {
    if (typeof res !== "string" || !res) return false;
    return (
      res.indexOf("PelisJuanita - Acceso") !== -1 ||
      /name=["']apodo["']/i.test(res) ||
      /id=["']apodo["']/i.test(res)
    );
  }

  async get(url, referer, authed) {
    if (authed) await this.ensure();
    const headers = {
      "Miru-Url": url,
      "Referer": referer || SITE + "/",
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "es-MX,es;q=0.9,en;q=0.8",
      "User-Agent": UA,
      "Sec-Fetch-Dest": "document",
      "Sec-Fetch-Mode": "navigate",
      "Sec-Fetch-Site": "same-origin",
      "Upgrade-Insecure-Requests": "1",
    };

    let res = "";
    try {
      res = await this.request("", { headers });
    } catch (_) {
      res = "";
    }
    if (typeof res !== "string") return "";

    if (!authed && this.isGate(res)) {
      await this.ensure();
      try {
        res = await this.request("", { headers });
      } catch (_) {
        res = "";
      }
    }

    if (this.isGate(res)) {
      this._auth = null;
      await this.ensure();
      try {
        res = await this.request("", { headers });
      } catch (_) {
        res = "";
      }
      if (typeof res !== "string" || this.isGate(res)) return "";
    }
    return res;
  }

  // ------------------------------------------------------------------ parseo
  cards(html, kind) {
    const out = [];
    if (!html || typeof html !== "string") return out;
    const parts = html.split(/<div\s+class=['"]grid-item['"]>/i);
    for (let i = 1; i < parts.length; i++) {
      const p = parts[i];
      const a = p.match(/<a\s+[^>]*href=['"]([^'"]+)['"]/i);
      if (!a) continue;
      const href = this.fix(a[1]);

      const img =
        p.match(/<img[^>]*class=['"]img-cover['"][^>]*src=['"]([^'"]+)['"]/i) ||
        p.match(/<img[^>]*src=['"](https?:[^'"]+)['"][^>]*>/i);
      const h2 = p.match(/<h2[^>]*>([\s\S]*?)<\/h2>/i);
      const year = p.match(/<div\s+class=['"]right['"]>\s*([^<]+?)\s*<\/div>/i);

      const title = h2 ? this.clean(h2[1]) : "";
      if (!title) continue;

      let type = kind;
      if (/ver-serie\//i.test(href)) type = "serie";
      else if (/\/pelicula\//i.test(href)) type = "movie";

      let slug = "";
      if (type === "movie") {
        slug = (href.match(/\/pelicula\/([^\/?#]+)/i) || [])[1] || "";
      } else {
        slug = (href.match(/ver-serie\/([^\/?#]+)/i) || [])[1] || "";
      }
      if (!slug) slug = href.split("?")[0].split("/").filter(Boolean).pop() || "";
      if (!slug) continue;
      try {
        slug = decodeURIComponent(slug);
      } catch (_) {}

      out.push({
        title: title,
        url:
          type === "movie"
            ? MOVIE_INFO + "?title=" + encodeURIComponent(slug)
            : SERIES_INFO + "?nombreSerie=" + encodeURIComponent(slug),
        cover: img ? this.fix(img[1]) : "",
        update: year ? this.clean(year[1]) : "",
      });
    }
    return out;
  }

  normTitle(s) {
    return this.clean(s)
      .toLowerCase()
      .replace(/[áàäâã]/g, "a")
      .replace(/[éèëê]/g, "e")
      .replace(/[íìïî]/g, "i")
      .replace(/[óòöôõ]/g, "o")
      .replace(/[úùüû]/g, "u")
      .replace(/ñ/g, "n")
      .replace(/[^a-z0-9]+/g, "");
  }

  dedupe(list) {
    const out = [];
    const seen = {};
    for (const it of list) {
      const k = this.normTitle(it.title);
      if (!k) {
        out.push(it);
        continue;
      }
      if (seen[k]) continue;
      seen[k] = true;
      out.push(it);
    }
    return out;
  }

  info(html) {
    let title = "";
    let cover = "";
    let desc = "";

    const h1 = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    if (h1) title = this.clean(h1[1]);

    const img =
      html.match(/<div\s+class=["']columna imagen["']\s*>\s*<img[^>]*src=["']([^"']+)["']/i) ||
      html.match(/contenedorImgTexto[\s\S]{0,500}?<img[^>]*src=["']([^"']+)["']/i);
    if (img) cover = this.fix(img[1]);

    const p = html.match(/<p[^>]*class=["']sinopsis["'][^>]*>([\s\S]*?)<\/p>/i);
    if (p) desc = this.clean(p[1]);

    return { title: title, cover: cover, desc: desc };
  }

  rows(html) {
    const out = [];
    if (!html || typeof html !== "string") return out;
    const re = /<div\b[^>]*class=['"]row-download['"][^>]*>/gi;
    let m;
    while ((m = re.exec(html))) {
      const tag = m[0];
      if (!/data-tipo\s*=\s*['"]stream['"]/i.test(tag)) continue;
      const url = this.attr(tag, "data-url");
      if (!url || !/^https?:/i.test(url)) continue;
      if (out.some((x) => x.url === url)) continue;
      const after = html.substr(m.index + tag.length, 220);
      const span = after.match(/<span[^>]*>([^<]+)<\/span>/i);
      out.push({
        name: span ? this.clean(span[1]) : "Servidor",
        lang: this.clean(this.attr(tag, "data-idioma")),
        url: this.fix(url),
      });
    }
    return out;
  }

  attr(tag, name) {
    const m = String(tag || "").match(new RegExp(name + "\\s*=\\s*['\"]([^'\"]*)['\"]", "i"));
    return m ? m[1] : "";
  }

  param(url, name) {
    const m = String(url || "").match(new RegExp("[?&]" + name + "=([^&#]*)", "i"));
    if (!m) return "";
    try {
      return decodeURIComponent(m[1].replace(/\+/g, " "));
    } catch (_) {
      return m[1];
    }
  }

  clean(s) {
    return String(s || "")
      .replace(/<[^>]+>/g, " ")
      .replace(/&nbsp;/gi, " ")
      .replace(/&amp;/gi, "&")
      .replace(/&quot;/gi, '"')
      .replace(/&#0?39;/g, "'")
      .replace(/&aacute;/gi, "a")
      .replace(/&eacute;/gi, "e")
      .replace(/&iacute;/gi, "i")
      .replace(/&oacute;/gi, "o")
      .replace(/&uacute;/gi, "u")
      .replace(/&ntilde;/gi, "n")
      .replace(/&#x([0-9a-f]+);/gi, (m2, h) => String.fromCharCode(parseInt(h, 16)))
      .replace(/&#(\d+);/g, (m2, d) => String.fromCharCode(parseInt(d, 10)))
      .replace(/\s+/g, " ")
      .trim();
  }

  canonical(url) {
    let s = this.fix(url);
    if (/movieInfo\.php|serieInfo\.php/i.test(s)) return s;

    let m = s.match(/\/pelicula\/([^\/?#]+)/i);
    if (m) return MOVIE_INFO + "?title=" + m[1];

    m = s.match(/ver-serie\/([^\/?#]+)(?:\/(\d+)x(\d+))?/i);
    if (m) {
      if (m[2] && m[3]) {
        return (
          SERIES_INFO +
          "?nombreSerie=" +
          m[1] +
          "&nroTemporada=" +
          m[2] +
          "&nroEpisodio=" +
          m[3]
        );
      }
      return SERIES_INFO + "?nombreSerie=" + m[1];
    }
    if (!/^https?:/i.test(s)) return MOVIE_INFO + "?title=" + encodeURIComponent(s);
    return s;
  }

  // ------------------------------------------------------------------ servidores
  rankHost(u) {
    const h = (String(u || "").match(/^https?:\/\/([^\/]+)/i) || ["", ""])[1].toLowerCase();
    if (
      h.indexOf("streamwish") !== -1 ||
      h.indexOf("hglink") !== -1 ||
      h.indexOf("streamhg") !== -1 ||
      h.indexOf("playnixes") !== -1 ||
      h.indexOf("hglamioz") !== -1 ||
      h.indexOf("medixiru") !== -1
    )
      return 0;
    if (h.indexOf("byse") !== -1 || h.indexOf("filemoon") !== -1) return 1;
    if (
      h.indexOf("vidhide") !== -1 ||
      h.indexOf("earnvids") !== -1 ||
      h.indexOf("callistanise") !== -1 ||
      h.indexOf("minochinos") !== -1 ||
      h.indexOf("vsharea") !== -1
    )
      return 2;
    if (h.indexOf("voe") !== -1) return 3;
    return 9;
  }

  async resolveEmbed(embed, referer) {
    const src = this.fix(embed);
    if (!src) return null;
    if (/\.m3u8(\?|#|$)/i.test(src)) {
      return { type: "hls", url: src, headers: { Referer: referer, "User-Agent": UA } };
    }
    if (/\.mp4(\?|#|$)/i.test(src)) {
      return { type: "mp4", url: src, headers: { Referer: referer, "User-Agent": UA } };
    }

    if (BYSE_RE.test(src)) {
      const r = await this.byse(src);
      if (r) return r;
    }
    if (VOE_RE.test(src)) {
      const r = await this.voe(src);
      if (r) return r;
    }
    if (/streamwish|hglink|streamhg|playnixes|hglamioz|medixiru|awish|wish/i.test(src)) {
      const r = await this.streamwish(src);
      if (r) return r;
    }
    if (/vidhide|earnvids|morencius|callistanise|minochinos|vsharea|vhide|vid-hide/i.test(src)) {
      const r = await this.vidhide(src);
      if (r) return r;
    }
    if (/vimeus|vimeos/i.test(src)) {
      const r = await this.vimeus(src, referer);
      if (r) return r;
    }

    let html = "";
    try {
      html = await this.request("", {
        headers: { "Miru-Url": src, Referer: referer, "User-Agent": UA },
      });
    } catch (_) {
      html = "";
    }
    if (typeof html !== "string" || !html) return null;

    if (html.indexOf("/pass_md5/") !== -1) {
      const r = await this.dood(src, html);
      if (r) return r;
    }
    if (html.indexOf("MDCore") !== -1) {
      const r = this.mixdrop(html);
      if (r) return r;
    }
    if (html.indexOf("eval(function(p,a,c,k,e") !== -1) {
      let r = this.swHtml(html);
      if (!r) r = this.filemoon(html, src);
      if (r) return r;
    }
    return this.findStream(html, src);
  }

  // ---- StreamWish (packer links.hls2/hls3 + CDN real) --------------------
  async streamwish(embed) {
    const src = this.fix(embed);
    const clean = src.split("#")[0];
    let id = (clean.split("?")[0].split("/").filter(Boolean).pop() || "").replace(
      /\.html?$/i,
      ""
    );
    if (!id) return null;
    const search = (clean.match(/\?[^#]*/) || [""])[0];
    const own = (this.originOf(src) || "").replace(/^https?:\/\//i, "").toLowerCase();

    const hosts = SW_HOSTS.concat([own]);
    const seen = {};
    for (const h of hosts.slice(0, 4)) {
      if (!h || seen[h]) continue;
      seen[h] = true;
      for (const path of ["/e/", "/v/"]) {
        const page = "https://" + h + path + id + search;
        let html = "";
        try {
          html = await this.request("", {
            headers: {
              "Miru-Url": page,
              "Referer": "https://www.google.com/",
              "User-Agent": UA,
              "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
              "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
            },
          });
        } catch (_) {
          html = "";
        }
        if (typeof html !== "string" || html.length < 500) continue;
        // Cascara "Page is loading": reintento con la cookie ya guardada.
        if (html.indexOf("Page is loading") !== -1 || html.indexOf("Redirecting") !== -1) {
          try {
            html = await this.request("", {
              headers: { "Miru-Url": page, "Referer": page, "User-Agent": UA },
            });
          } catch (_) {}
        }
        if (typeof html !== "string" || !html) continue;
        if (html.indexOf("Just a moment") !== -1) continue;

        const r = await this.swHtml(html, "https://" + h);
        if (r) return r;
        const d = html.match(/["']((?:https?:)?\/\/[^"']+\.m3u8[^"']*)["']/i);
        if (d) {
          return {
            type: "hls",
            url: this.fix(d[1]),
            headers: { Referer: "https://" + h + "/", "User-Agent": UA },
          };
        }
      }
    }
    return null;
  }

  swHtml(html, base) {
    const un = this.unpack(this.locate(html, "links"));
    if (!un) return null;
    const block = un.match(/links\s*=\s*\{([\s\S]*?)\}/);
    if (!block) return null;
    const links = {};
    const re = /["']([a-zA-Z0-9_]+)["']\s*:\s*["']([^"']+)["']/g;
    let m;
    while ((m = re.exec(block[1]))) links[m[1]] = m[2];
    for (const k of ["hls2", "hls3", "hls4"]) {
      let u = this.fix(links[k] || "");
      if (!u) continue;
      if (u.indexOf("/") === 0) u = (base || "") + u;
      if (!/\.m3u8|master\.txt|playlist\.txt|\/hls\//i.test(u)) continue;
      const ref = k === "hls4" ? (base || "") + "/" : "https://streamwish.to/";
      return {
        type: "hls",
        url: u,
        headers: { Referer: ref, "User-Agent": UA },
      };
    }
    return null;
  }

  // ---- VidHide / Earnvids (packer con file: *.m3u8) ---------------------
  async vidhide(embed) {
    const src = this.fix(embed);
    const clean = src.split("#")[0];
    const idm = clean.match(/\/(?:v|e|embed)\/([A-Za-z0-9]+)/i);
    const id = idm
      ? idm[1]
      : (clean.split("?")[0].split("/").filter(Boolean).pop() || "");
    if (!id) return null;
    const search = (clean.match(/\?[^#]*/) || [""])[0];
    const own = (this.originOf(src) || "").replace(/^https?:\/\//i, "").toLowerCase();

    const hosts = [own].concat([
      "morencius.com",
      "minochinos.com",
      "callistanise.com",
      "vsharea.com",
      "vidhide.com",
    ]);
    const seen = {};
    for (const h of hosts.slice(0, 4)) {
      if (!h || seen[h]) continue;
      seen[h] = true;
      const page = "https://" + h + "/v/" + id + search;
      let html = "";
      try {
        html = await this.request("", {
          headers: {
            "Miru-Url": page,
            "Referer": "https://google.com/",
            "User-Agent": UA,
            "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
            "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
          },
        });
      } catch (_) {
        html = "";
      }
      if (typeof html !== "string" || !html) continue;
      if (
        html.length < 2000 &&
        (html.indexOf("Page is loading") !== -1 || html.indexOf("Redirecting") !== -1)
      ) {
        try {
          html = await this.request("", {
            headers: { "Miru-Url": page, "Referer": page, "User-Agent": UA },
          });
        } catch (_) {}
      }
      if (typeof html !== "string" || !html) continue;
      if (html.indexOf("Just a moment") !== -1) continue;

      const r = this.streamFromPage(html, "https://" + h);
      if (r) return r;
    }
    return null;
  }

  streamFromPage(html, origin) {
    const body = String(html || "");
    const abs = (u) => {
      let s = this.fix(u);
      if (s.indexOf("/") === 0) s = origin + s;
      return s;
    };
    const pick = (text) => {
      const m =
        text.match(
          /file\s*:\s*["']([^"']*(?:\.m3u8|master\.txt|playlist\.txt|\/hls\/)[^"']*)["']/i
        ) ||
        text.match(
          /["']((?:https?:)?\/\/[^"'<>\s]+(?:\.m3u8|master\.txt|playlist\.txt)[^"'<>\s]*)["']/i
        ) ||
        text.match(/["'](\/stream\/[^"']+\.m3u8[^"']*)["']/i);
      return m ? abs(m[1]) : "";
    };
    let u = "";
    if (body.indexOf("eval(function(p,a,c,k,e") !== -1) {
      const un = this.unpack(body);
      if (un) u = pick(un);
    }
    if (!u) u = pick(body);
    let type = "hls";
    if (!u) {
      const m = body.match(/file\s*:\s*["']([^"']+\.mp4[^"']*)["']/i);
      if (m) {
        u = abs(m[1]);
        type = "mp4";
      }
    }
    if (!u) return null;
    return {
      type: type,
      url: u,
      headers: { Referer: origin + "/", "User-Agent": UA },
    };
  }

  // ---- Vimeus -> Vimeos (packer) -----------------------------------------
  async vimeus(embed, referer) {
    try {
      const src = this.fix(embed);
      let html = await this.request("", {
        headers: { "Miru-Url": src, Referer: referer || SITE + "/", "User-Agent": UA },
      });
      if (typeof html !== "string" || !html) return null;

      let target = "";
      const m = html.match(/<script[^>]*id=["']data["'][^>]*>([\s\S]*?)<\/script>/i);
      if (m) {
        try {
          const j = JSON.parse(m[1]);
          const e = (j.embeds && j.embeds[0]) || {};
          target = e.url || "";
        } catch (_) {}
      }
      if (!target) {
        const d = html.match(/["'](https?:\/\/vimeos?\.net\/embed-[^"']+)["']/i);
        if (d) target = d[1];
      }
      if (!target) return this.findStream(html, src);

      const page = await this.request("", {
        headers: { "Miru-Url": target, Referer: src, "User-Agent": UA },
      });
      if (typeof page !== "string" || !page) return null;
      const un = this.unpack(this.locate(page, "eval(function"));
      const body = un || page;
      const f =
        body.match(/sources\s*:\s*\[\s*\{[^}]*file\s*:\s*["']([^"']+)["']/i) ||
        body.match(/file\s*:\s*["']([^"']+\.m3u8[^"']*)["']/i) ||
        body.match(/["'](https?:[^"']+\.m3u8[^"']*)["']/i);
      if (!f) return null;
      return {
        type: "hls",
        url: this.fix(f[1]),
        headers: { Referer: target, "User-Agent": UA },
      };
    } catch (_) {
      return null;
    }
  }

  // ---- Byse / Filemoon (API nueva con playback AES-256-GCM) --------------
  async byse(embed) {
    try {
      if (typeof CryptoJS === "undefined") return null;
      const src = this.fix(embed);
      const origin = this.originOf(src);
      const idm = src.match(/\/(?:e|v|embed)\/([A-Za-z0-9]+)/);
      if (!origin || !idm) return null;
      const id = idm[1];
      const parent = origin + "/e/" + id;

      const base = {
        "User-Agent": UA,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
        "X-Requested-With": "XMLHttpRequest",
        "Origin": origin,
        "Referer": parent,
      };

      const details = await this.jsonGet(origin + "/api/videos/" + id + "/embed/details", base);
      if (!details || !details.embed_frame_url) return null;

      const iframe = details.embed_frame_url;
      const io = this.originOf(iframe) || origin;
      const frame = Object.assign({}, base, {
        "Origin": io,
        "Referer": iframe,
        "x-embed-parent": parent,
      });

      await this.jsonGet(io + "/api/videos/" + id + "/embed/settings", frame);

      const viewer = this.rnd(16) + this.rnd(16);
      const device = this.rnd(16) + this.rnd(16);
      const auth = Object.assign({}, frame, {
        "Cookie": "byse_viewer_id=" + viewer + "; byse_device_id=" + device,
      });

      const captcha = await this.jsonPost(
        io + "/api/videos/" + id + "/embed/captcha",
        Object.assign({}, auth, { "Content-Type": "application/json" }),
        "{}"
      );
      if (!captcha || !captcha.pow_token) return null;

      const token = captcha.pow_token;
      const playback = await this.jsonPost(
        io + "/api/videos/" + id + "/embed/playback",
        Object.assign({}, auth, {
          "Content-Type": "application/json",
          "X-Captcha-Token": token,
        }),
        JSON.stringify({
          fingerprint: { token: token, viewer_id: viewer, device_id: device },
        })
      );
      if (!playback || !playback.playback) return null;

      const data = this.byseDecrypt(playback.playback);
      if (!data) return null;
      const list = data.sources || (data.source ? [data] : []);
      let pick = "";
      let mime = "";
      for (const s of list) {
        const u = s && (s.url || s.file);
        if (!u) continue;
        const mimeType = String((s && s.mime_type) || "");
        if (!pick || /mpegurl/i.test(mimeType)) {
          pick = u;
          mime = mimeType;
        }
        if (/mpegurl/i.test(mime)) break;
      }
      if (!pick) return null;
      const isHls = /\.m3u8/i.test(pick) || /mpegurl/i.test(mime);
      return {
        type: isHls ? "hls" : "mp4",
        url: this.fix(pick),
        headers: { Referer: origin + "/", "User-Agent": UA },
      };
    } catch (_) {
      return null;
    }
  }

  byseDecrypt(pl) {
    try {
      if (!pl || !pl.iv || !pl.payload || !pl.key_parts) return null;
      if (typeof CryptoJS === "undefined") return null;
      const parts = pl.key_parts;
      let sel = parts;
      const v = Number(pl.version);
      if (v >= 1 && v <= 20) {
        const a = v;
        const b = 31 - v;
        if (a <= parts.length && b <= parts.length) {
          sel = [parts[a - 1], parts[b - 1]];
        }
      }
      const keyHex = sel.map((p) => this.b64wa(p).toString(CryptoJS.enc.Hex)).join("");
      const payload = this.b64wa(pl.payload);
      const ctBytes = payload.sigBytes - 16;
      if (ctBytes <= 0) return null;
      const ct = CryptoJS.lib.WordArray.create(
        payload.words.slice(0, Math.ceil(ctBytes / 4)),
        ctBytes
      );
      const ivHex = this.b64wa(pl.iv).toString(CryptoJS.enc.Hex) + "00000002";
      const dec = CryptoJS.AES.decrypt(
        { ciphertext: ct },
        CryptoJS.enc.Hex.parse(keyHex),
        {
          iv: CryptoJS.enc.Hex.parse(ivHex),
          mode: CryptoJS.mode.CTR,
          padding: CryptoJS.pad.NoPadding,
        }
      );
      return JSON.parse(dec.toString(CryptoJS.enc.Utf8));
    } catch (_) {
      return null;
    }
  }

  b64wa(s) {
    let v = String(s || "").replace(/-/g, "+").replace(/_/g, "/");
    while (v.length % 4) v += "=";
    return CryptoJS.enc.Base64.parse(v);
  }

  // ---- VOE (config ofuscada en <script type="application/json">) ---------
  async voe(embed) {
    try {
      const src = this.fix(embed);
      const id = (src.split("?")[0].split("/").filter(Boolean).pop() || "").trim();
      if (!id) return null;
      const search = (src.match(/\?[^#]*/) || [""])[0];
      const host = (this.originOf(src) || "").replace(/^https?:\/\//i, "");
      if (!host) return null;

      const hosts = [host].concat(VOE_MIRRORS);
      const seen = {};
      let html = "";
      let origin = this.originOf(src);

      for (const h of hosts) {
        if (seen[h]) continue;
        seen[h] = true;
        const page = "https://" + h + "/e/" + id + search;
        let res = "";
        try {
          res = await this.request("", {
            headers: {
              "Miru-Url": page,
              "Referer": "https://google.com/",
              "User-Agent": UA,
              "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
              "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
            },
          });
        } catch (_) {
          continue;
        }
        if (typeof res !== "string" || !res) continue;

        const red = res.match(/window\.location\.href\s*=\s*['"](https?:\/\/[^'"]+)['"]/i);
        if (red && res.indexOf("application/json") === -1) {
          try {
            const r2 = await this.request("", {
              headers: { "Miru-Url": red[1], "Referer": page, "User-Agent": UA },
            });
            if (typeof r2 === "string" && r2) {
              res = r2;
              origin = this.originOf(red[1]) || origin;
            }
          } catch (_) {}
        }

        if (res.indexOf('<script type="application/json">["') !== -1 || /\.m3u8/i.test(res)) {
          html = res;
          break;
        }
      }
      if (!html) return null;

      let url = "";
      const m = html.match(/<script type="application\/json">\["([^"]+)"\]<\/script>/);
      if (m) {
        const cfg = this.voeDecode(m[1]);
        if (cfg) url = cfg.source || cfg.file || "";
      }

      if (!url) {
        const d = html.match(/decodeURI\(['"]([^'"]+)['"]\)/i);
        if (d) {
          try {
            const str = decodeURIComponent(d[1]);
            let off = "";
            for (let i = 0; i < str.length; i++) {
              off += String.fromCharCode(str.charCodeAt(i) - 3);
            }
            const rev = off.split("").reverse().join("");
            const b = rev.match(/[A-Za-z0-9+/=]{50,}/);
            if (b) {
              const cfg = JSON.parse(this.utf8(this.b64u(b[0])));
              url = cfg.file || cfg.source || cfg.url || "";
            }
          } catch (_) {}
        }
      }

      if (!url) {
        const d = html.match(/['"](https?:\/\/[^'"]+\.m3u8[^'"]*)['"]/i);
        if (d) url = d[1];
      }
      if (!url) return null;

      url = this.fix(url);
      if (search && url.indexOf("t=") === -1) {
        url += (url.indexOf("?") === -1 ? "?" : "&") + search.substring(1);
      }
      return {
        type: /\.m3u8/i.test(url) ? "hls" : "mp4",
        url: url,
        headers: { Referer: origin + "/", "User-Agent": UA },
      };
    } catch (_) {
      return null;
    }
  }

  voeDecode(encoded) {
    try {
      const rot = String(encoded || "").replace(/[a-zA-Z]/g, (c) => {
        const code = c.charCodeAt(0);
        return String.fromCharCode((c <= "Z" ? 90 : 122) >= code + 13 ? code + 13 : code - 13);
      });
      let str = rot;
      for (const tag of ["@$", "^^", "~@", "%?", "*~", "!!", "#&"]) {
        str = str.split(tag).join("");
      }
      const first = this.b64u(str);
      let off = "";
      for (let i = 0; i < first.length; i++) {
        off += String.fromCharCode(first.charCodeAt(i) - 3);
      }
      const rev = off.split("").reverse().join("");
      return JSON.parse(this.utf8(this.b64u(rev)));
    } catch (_) {
      return null;
    }
  }

  // ---- DoodStream / MixDrop / Filemoon -----------------------------------
  async dood(embed, html) {
    try {
      const host = (embed.match(/^https?:\/\/[^\/]+/) || [""])[0];
      const after = html.split("/pass_md5/")[1];
      if (!after) return null;
      const md5 = after.split(/['")\s]/)[0];
      if (!md5) return null;
      const token = md5.split("/").pop();

      const base = await this.request("", {
        headers: { "Miru-Url": host + "/pass_md5/" + md5, Referer: embed, "User-Agent": UA },
      });
      if (typeof base !== "string" || !base || base.indexOf("RELOAD") !== -1) return null;

      const url =
        base.replace(/\s+$/, "") + this.rnd(10) + "?token=" + token + "&expiry=" + Date.now();
      return { type: "mp4", url: url, headers: { Referer: host + "/", "User-Agent": UA } };
    } catch (_) {
      return null;
    }
  }

  mixdrop(html) {
    const region = this.locate(html, "MDCore");
    const un = this.unpack(region);
    if (!un) return null;
    let u = (un.match(/Core\.wurl\s*=\s*["']([^"']+)["']/) || [])[1];
    if (!u) u = (un.match(/wurl\s*=\s*["']([^"']+)["']/) || [])[1];
    if (!u) return null;
    return {
      type: "mp4",
      url: this.fix(u),
      headers: { Referer: "https://mixdrop.co/", "User-Agent": UA },
    };
  }

  filemoon(html, referer) {
    const region = this.locate(html, "m3u8");
    const un = this.unpack(region);
    if (!un) return null;
    const f = un.match(/file\s*:\s*["']([^"']+)["']/);
    if (!f) return null;
    return { type: "hls", url: this.fix(f[1]), headers: { Referer: referer, "User-Agent": UA } };
  }

  findStream(text, referer) {
    if (!text || typeof text !== "string") return null;
    const headers = { Referer: referer, "User-Agent": UA };

    let m =
      text.match(/src\s*:\s*["'](https?:[^"']+\.mp4[^"']*)["']/i) ||
      text.match(/["'](https?:\\?\/\\?\/[^"'<>\s]+?\.mp4[^"'<>\s]*)["']/i);
    if (m) return { type: "mp4", url: this.fix(m[1]), headers: headers };

    m =
      text.match(/["'](https?:\\?\/\\?\/[^"'<>\s]+?\.m3u8[^"'<>\s]*)["']/i) ||
      text.match(/(https?:\\?\/\\?\/[^"'<>\s]+?\.m3u8[^"'<>\s]*)/i);
    if (m) return { type: "hls", url: this.fix(m[1]), headers: headers };

    if (text.indexOf("eval(function(p,a,c,k,e") !== -1) {
      const un = this.unpack(text);
      if (un) {
        const f = un.match(/file\s*:\s*["']([^"']+)["']/);
        if (f) return { type: "hls", url: this.fix(f[1]), headers: headers };
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ utils
  async jsonGet(url, headers) {
    const res = await this.request("", {
      headers: Object.assign({ "Miru-Url": url }, headers),
    });
    if (typeof res === "string") {
      try {
        return JSON.parse(res);
      } catch (_) {
        return null;
      }
    }
    return res;
  }

  async jsonPost(url, headers, data) {
    const res = await this.request("", {
      method: "post",
      data: data,
      headers: Object.assign({ "Miru-Url": url }, headers),
    });
    if (typeof res === "string") {
      try {
        return JSON.parse(res);
      } catch (_) {
        return null;
      }
    }
    return res;
  }

  locate(html, marker) {
    const re = /<script\b[^>]*>([\s\S]*?)<\/script>/gi;
    let m;
    while ((m = re.exec(html))) {
      if (m[1].indexOf(marker) !== -1 && m[1].indexOf("eval(function(p,a,c,k,e") !== -1) {
        return m[1];
      }
    }
    return html;
  }

  unpack(src) {
    if (!src || typeof src !== "string") return "";
    const m = src.match(
      /}\s*\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'\.split\(/
    );
    if (!m) return "";
    let p = this.unesc(m[1]);
    const a = parseInt(m[2], 10);
    const c = parseInt(m[3], 10);
    const k = m[4].split("|");

    const enc = (idx) => {
      let s = "";
      if (idx >= a) s = enc(Math.floor(idx / a));
      const d = idx % a;
      return s + (d > 35 ? String.fromCharCode(d + 29) : d.toString(36));
    };

    for (let i = c - 1; i >= 0; i--) {
      if (k[i]) {
        p = p.replace(new RegExp("\\b" + enc(i) + "\\b", "g"), k[i]);
      }
    }
    return p;
  }

  unesc(s) {
    let o = "";
    for (let i = 0; i < s.length; i++) {
      const ch = s.charAt(i);
      if (ch === "\\" && i + 1 < s.length) {
        const n = s.charAt(i + 1);
        if (n === "n") o += "\n";
        else if (n === "r") o += "\r";
        else if (n === "t") o += "\t";
        else o += n;
        i++;
      } else {
        o += ch;
      }
    }
    return o;
  }

  b64(s) {
    const A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    s = String(s || "")
      .replace(/=+$/, "")
      .replace(/[^A-Za-z0-9+/]/g, "");
    let bits = "";
    for (let i = 0; i < s.length; i++) {
      const v = A.indexOf(s.charAt(i));
      if (v < 0) continue;
      bits += ("000000" + v.toString(2)).slice(-6);
    }
    let out = "";
    for (let i = 0; i + 8 <= bits.length; i += 8) {
      out += String.fromCharCode(parseInt(bits.substr(i, 8), 2));
    }
    return out;
  }

  b64u(s) {
    return this.b64(String(s || "").replace(/-/g, "+").replace(/_/g, "/"));
  }

  utf8(bin) {
    let out = "";
    let i = 0;
    while (i < bin.length) {
      const c = bin.charCodeAt(i++);
      if (c < 0x80) {
        out += String.fromCharCode(c);
      } else if (c < 0xe0) {
        out += String.fromCharCode(((c & 0x1f) << 6) | (bin.charCodeAt(i++) & 0x3f));
      } else if (c < 0xf0) {
        out += String.fromCharCode(
          ((c & 0x0f) << 12) |
            ((bin.charCodeAt(i++) & 0x3f) << 6) |
            (bin.charCodeAt(i++) & 0x3f)
        );
      } else {
        const cp =
          ((c & 0x07) << 18) |
          ((bin.charCodeAt(i++) & 0x3f) << 12) |
          ((bin.charCodeAt(i++) & 0x3f) << 6) |
          (bin.charCodeAt(i++) & 0x3f);
        out += String.fromCodePoint(cp);
      }
    }
    return out;
  }

  rnd(n) {
    const A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let s = "";
    for (let i = 0; i < n; i++) s += A.charAt(Math.floor(Math.random() * A.length));
    return s;
  }

  originOf(u) {
    const m = String(u || "").match(/^(https?:\/\/[^\/]+)/i);
    return m ? m[1] : "";
  }

  fix(u) {
    const s = String(u || "")
      .replace(/\\\//g, "/")
      .replace(/\\u0026/gi, "&")
      .replace(/&amp;/gi, "&")
      .replace(/&#0?38;/g, "&")
      .trim();
    if (s.indexOf("//") === 0) return "https:" + s;
    return s;
  }

  err(msg) {
    return { type: "hls", url: "error://" + msg };
  }
}
