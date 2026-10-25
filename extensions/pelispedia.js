// ==MiruExtension==
// @name         Pelis Premium
// @version      v0.1.8
// @author       YeaniFlix
// @lang         es
// @license      MIT
// @package      pelispedia
// @type         bangumi
// @icon         https://pelispedia.mov/favicon.ico
// @webSite      https://pelispedia.mov
// @nsfw         false
// ==/MiruExtension==

// PelisPedia (https://pelispedia.mov) - peliculas y series en espanol.
//
// La ficha incrusta el reproductor Embed69 en /vidurl/<tmdb>/ (peliculas) o
// /vidurl/<tmdb>-<S>x<E>/ (episodios). Embed69 entrega los enlaces cifrados
// con AES-256-CBC y una prueba de trabajo SHA-256 (POW_CHALLENGE,
// POW_DIFFICULTY, POW_SALT); aqui se resuelve en el runtime sin proxy.
//
// Servidores soportados: StreamWish, Filemoon/BYSE, VidHide y Voe (Voe suele
// quedar detras de Cloudflare; se conserva como ultimo recurso).

const SITE = "https://pelispedia.mov";

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
  "hgcloud.to",
  "awish.pro",
  "streamhide.to",
];

export default class extends Extension {
  // ------------------------------------------------------------------ listas
  async latest(page) {
    const p = Math.max(1, parseInt(page) || 1);
    const urls = [
      SITE + "/peliculas?page=" + p,
      SITE + "/series?page=" + p,
    ];
    const html = await Promise.all(
      urls.map((u) => this.get(u, SITE + "/").catch(() => ""))
    );
    return this.dedupe(
      this.cards(html[0]).concat(this.cards(html[1]))
    );
  }

  async search(kw, page) {
    const text = String(kw || "").trim();
    if (!text) return [];
    const p = Math.max(1, parseInt(page) || 1);
    let out = await this.searchPage(text, p);
    if (!out.length && /[:|\-]/.test(text)) {
      const head = text.split(/[:|\-]/)[0].trim();
      if (head && head !== text) out = await this.searchPage(head, p);
    }
    if (!out.length) {
      const words = text.split(/\s+/).filter((w) => w.length > 2);
      if (words.length > 3) out = await this.searchPage(words.slice(0, 3).join(" "), p);
    }
    return this.dedupe(out);
  }

  async searchPage(q, p) {
    const url =
      SITE +
      "/search?s=" +
      encodeURIComponent(q).replace(/%20/g, "+") +
      "&page=" +
      p;
    return this.cards(await this.get(url, SITE + "/"));
  }

  cards(html) {
    const out = [];
    const src = String(html || "");
    if (!src) return out;
    const parts = src.split(/<div[^>]*class=["'][^"']*\bmovie-card\b[^"']*["'][^>]*>/i);
    for (let i = 1; i < parts.length; i++) {
      const p = parts[i];
      const a = p.match(/<a\s+[^>]*href=["']([^"']+)["']/i);
      if (!a) continue;
      const url = this.siteUrl(a[1]);
      if (!/\/(pelicula|serie)\//i.test(url)) continue;
      if (/\/temporada\//i.test(url)) continue;
      const img = p.match(/<img[^>]*\ssrc=["']([^"']+)["']/i);
      const h = p.match(/<h[1-4][^>]*>([\s\S]*?)<\/h[1-4]>/i);
      let title = h ? this.clean(h[1]) : "";
      if (!title) {
        const al = p.match(/alt=["']Ver\s+([^"']+?)\s+online/i);
        title = al ? this.clean(al[1]) : "";
      }
      if (!title) continue;
      title = title.replace(/\s*\(\d{4}\)\s*$/, "");
      const year = (p.match(/\((19|20)\d{2}\)/) || [])[0] || "";
      out.push({
        title: title + (year ? " " + year : ""),
        url: url,
        cover: img && /^https?:\/\//i.test(this.siteUrl(img[1])) ? this.siteUrl(img[1]) : "",
        update: "",
      });
    }
    return out;
  }

  // ------------------------------------------------------------------ ficha
  async detail(u) {
    const url = this.siteUrl(u).split("#")[0];
    if (!url) throw new Error("URL vacia");
    const html = await this.get(url, SITE + "/");
    if (!html) throw new Error("No se pudo abrir la ficha");

    const info = this.info(html);
    const vid = this.vidUrl(html, url);

    if (/\/serie\//i.test(url) && !/\/capitulo\//i.test(url)) {
      const eps = this.episodes(html, url);
      return {
        title: info.title,
        cover: info.cover,
        desc: info.description,
        episodes: [{ title: "Episodios", urls: eps }],
      };
    }

    if (vid) {
      const vh = await this.get(vid, url);
      const langs = this.e69Langs(vh);
      if (langs.length) {
        const groups = langs.map((l) => ({
          title: this.e69LangName(l),
          urls: [
            {
              name: "Ver pelicula",
              url: vid + (vid.indexOf("?") === -1 ? "?" : "&") + "lang=" + l,
            },
          ],
        }));
        return {
          title: info.title,
          cover: info.cover,
          desc: info.description,
          episodes: groups,
        };
      }
    }

    return {
      title: info.title,
      cover: info.cover,
      desc: info.description,
      episodes: [
        {
          title: "Ver",
          urls: [{ name: "Ver online", url: vid || url }],
        },
      ],
    };
  }

  info(html) {
    const title =
      (html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i) || [])[1] ||
      (html.match(/property=["']og:title["'][^>]*content=["']([^"']+)/i) || [])[1] ||
      "";
    const cover =
      (html.match(/property=["']og:image["'][^>]*content=["']([^"']+)/i) || [])[1] ||
      "";
    const description =
      (html.match(/name=["']description["'][^>]*content=["']([^"']*)/i) || [])[1] ||
      "";
    return {
      title: this.clean(title),
      cover: this.siteUrl(cover),
      description: this.clean(description),
    };
  }

  vidUrl(html, base) {
    const m = String(html || "").match(
      /<iframe[^>]*\ssrc=["']([^"']*\/vidurl\/[^"']*)["']/i
    );
    if (!m) return "";
    return this.siteUrl(m[1]);
  }

  episodes(html, base) {
    const out = [];
    const seen = {};
    const re = /href=["']([^"']*\/serie\/[^"'\/]+\/temporada\/(\d+)\/capitulo\/(\d+)[^"']*)["']/gi;
    let m;
    while ((m = re.exec(String(html || ""))) !== null) {
      const s = parseInt(m[2], 10);
      const e = parseInt(m[3], 10);
      const key = s + "x" + e;
      if (seen[key]) continue;
      seen[key] = true;
      out.push({
        name: "T" + s + "E" + e,
        url: this.siteUrl(m[1]),
      });
    }
    out.sort((a, b) => {
      const pa = a.name.substring(1).split("E").map(Number);
      const pb = b.name.substring(1).split("E").map(Number);
      return pa[0] - pb[0] || pa[1] - pb[1];
    });
    return out;
  }

  // ------------------------------------------------------------------ Embed69
  e69Data(html) {
    const m = String(html || "").match(/let\s+dataLink\s*=\s*(\[[\s\S]*?\]);/);
    if (!m) return null;
    try {
      return JSON.parse(m[1]);
    } catch (_) {
      return null;
    }
  }

  e69Langs(html) {
    const data = this.e69Data(html);
    if (!data) return [];
    const out = [];
    for (const g of data) {
      const l = String(g.video_language || "").toUpperCase();
      if (!l || out.indexOf(l) !== -1) continue;
      const has = (g.sortedEmbeds || []).some((s) => {
        return (
          (s.type || "video") === "video" &&
          !!s.link &&
          !!this.e69Host(s.servername)
        );
      });
      if (has) out.push(l);
    }
    return out;
  }

  e69LangName(code) {
    const l = String(code || "").toUpperCase();
    if (l === "LAT") return "Español Latino";
    if (l === "ESP") return "Español Castellano";
    if (l === "SUB" || l === "VOSE") return "Subtitulada";
    return l;
  }

  e69Host(name) {
    const n = String(name || "").toLowerCase();
    if (n === "streamwish" || n === "sw") return { key: "streamwish", name: "StreamWish" };
    if (n === "vidhide" || n === "vh") return { key: "vidhide", name: "VidHide" };
    if (n === "voe") return { key: "voe", name: "Voe" };
    if (n === "filemoon" || n === "byse") return { key: "filemoon", name: "Filemoon" };
    return null;
  }

  e69Nonce(challenge, diff) {
    if (typeof CryptoJS === "undefined") return -1;
    const prefix = new Array(Math.max(0, diff) + 1).join("0");
    for (let n = 0; n < 2000000; n++) {
      if (CryptoJS.SHA256(challenge + n).toString().indexOf(prefix) === 0) return n;
    }
    return -1;
  }

  e69Decrypt(b64, key) {
    const raw = CryptoJS.enc.Base64.parse(String(b64 || ""));
    if (!raw || raw.sigBytes <= 16) return "";
    const iv = CryptoJS.lib.WordArray.create(raw.words.slice(0, 4), 16);
    const ct = CryptoJS.lib.WordArray.create(
      raw.words.slice(4),
      raw.sigBytes - 16
    );
    const plain = CryptoJS.AES.decrypt({ ciphertext: ct }, key, {
      iv: iv,
      mode: CryptoJS.mode.CBC,
      padding: CryptoJS.pad.Pkcs7,
    });
    return plain.toString(CryptoJS.enc.Utf8).replace(/\0+$/, "").trim();
  }

  e69Servers(html) {
    const data = this.e69Data(html);
    if (!data) return [];
    const challenge = (String(html).match(/POW_CHALLENGE\s*=\s*'([^']+)'/) || [])[1];
    const salt = (String(html).match(/POW_SALT\s*=\s*'([^']+)'/) || [])[1];
    const diff = parseInt(
      (String(html).match(/POW_DIFFICULTY\s*=\s*(\d+)/) || [])[1] || "0",
      10
    );
    if (!challenge || !salt || typeof CryptoJS === "undefined") return [];
    const nonce = this.e69Nonce(challenge, diff);
    if (nonce < 0) return [];
    const key = CryptoJS.SHA256(challenge + nonce + salt);

    const groups = [];
    for (const g of data) {
      const lang = String(g.video_language || "").toUpperCase();
      const servers = [];
      for (const s of g.sortedEmbeds || []) {
        if ((s.type || "video") !== "video") continue;
        const host = this.e69Host(s.servername);
        if (!host) continue;
        let link = "";
        try {
          link = this.e69Decrypt(s.link, key);
        } catch (_) {
          link = "";
        }
        if (!/^https?:\/\//i.test(link)) continue;
        servers.push({ key: host.key, name: host.name, url: link });
      }
      if (servers.length) groups.push({ lang: lang, servers: servers });
    }
    return groups;
  }

  // ------------------------------------------------------------------ watch
  async watch(u) {
    const raw = this.siteUrl(u);
    if (!raw) return this.err("URL vacia");
    this._lastResolveError = "";

    if (this.hostInfo(raw) && !/pelispedia\./i.test(raw)) {
      const direct = await this.resolveEmbed(raw, SITE + "/");
      if (direct && direct.url && !String(direct.url).startsWith("error://")) {
        return direct;
      }
      return this.err(this._lastResolveError || "Servidor no resoluble");
    }

    let vid = raw;
    let referer = SITE + "/";
    if (!/\/vidurl\//i.test(raw)) {
      const page = await this.get(raw, SITE + "/");
      if (!page) return this.err("No se pudo abrir la ficha");
      vid = this.vidUrl(page, raw);
      if (!vid) return this.err("Sin servidores disponibles");
      referer = raw;
    }

    const html = await this.get(vid, referer);
    if (!html) return this.err("No se pudo abrir Embed69");
    const groups = this.e69Servers(html);
    if (!groups.length) return this.err("No se pudieron descifrar los enlaces");

    const want = (this.param(raw, "lang") || "").toUpperCase();
    let g =
      (want && groups.find((x) => x.lang === want)) ||
      groups.find((x) => x.lang === "LAT") ||
      groups.find((x) => x.lang === "ESP") ||
      groups.find((x) => x.lang === "SUB") ||
      groups[0];

    const seen = {};
    let n = 2;
    const list = g.servers
      .slice()
      .sort((a, b) => this.rankHost(a.url) - this.rankHost(b.url))
      .map((s) => {
        let label = s.name;
        while (seen[label]) label = s.name + " #" + n++;
        seen[label] = s.url;
        return { key: s.key, label: label, url: s.url };
      });

    const headers = {};
    for (const s of list) headers[s.label] = s.url;

    const failures = [];
    for (const s of list) {
      let r = null;
      try {
        r = await this.limit(this.resolveEmbed(s.url, referer), 4500, null);
      } catch (_) {
        r = null;
      }
      if (!r || !r.url || String(r.url).startsWith("error://")) {
        if (this._lastResolveError) {
          failures.push(s.label + ": " + this._lastResolveError);
        }
        continue;
      }
      r.headers = Object.assign({}, r.headers || {}, {
        "X-Servers": JSON.stringify(headers),
        "X-Primary-Server": s.label,
        "X-Language": this.e69LangName(g.lang),
      });
      return r;
    }

    const detail = failures.slice(0, 2).join(" | ");
    return {
      type: "hls",
      url: "error://" + (detail ? "Ningun servidor responde. " + detail : "Ningun servidor responde"),
      headers: {
        "X-Servers": JSON.stringify(headers),
        "X-Language": this.e69LangName(g.lang),
      },
    };
  }

  hostInfo(u) {
    const s = String(u || "");
    if (/bysesukior|byse\.|filemoon|filemooon|moonplayer/i.test(s)) {
      return { key: "filemoon", name: "Filemoon" };
    }
    if (VOE_RE.test(s)) return { key: "voe", name: "Voe" };
    if (/streamwish|hglink|streamhg|playnixes|hglamioz|medixiru|awish|hgcloud|sfastwish|wishfast|streamhide|desiupload/i.test(s)) {
      return { key: "streamwish", name: "StreamWish" };
    }
    if (/vidhide|earnvids|morencius|callistanise|minochinos|vsharea|vhide|vid-hide|vidhideplus/i.test(s)) {
      return { key: "vidhide", name: "VidHide" };
    }
    return null;
  }

  async get(url, referer) {
    if (!url) return "";
    const headers = {
      "Miru-Url": url,
      "Referer": referer || SITE + "/",
      "Accept":
        "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "es-MX,es;q=0.9,en;q=0.8",
      "User-Agent": UA,
    };
    let res = "";
    try {
      res = await this.request("", { headers });
    } catch (_) {
      return "";
    }
    return typeof res === "string" ? res : "";
  }

  siteUrl(u) {
    const s = this.fix(u);
    if (!s) return "";
    if (s.charAt(0) === "/") return SITE + s;
    return s;
  }

  dedupe(list) {
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

  rankHost(u) {
    const h = (String(u || "").match(/^https?:\/\/([^\/]+)/i) || ["", ""])[1].toLowerCase();
    // 0 = VidHide (PREDETERMINADO / PRIMERA OPCIÓN)
    if (
      h.indexOf("vidhide") !== -1 ||
      h.indexOf("earnvids") !== -1 ||
      h.indexOf("callistanise") !== -1 ||
      h.indexOf("morencius") !== -1 ||
      h.indexOf("minochinos") !== -1 ||
      h.indexOf("vsharea") !== -1 ||
      h.indexOf("vidhideplus") !== -1 ||
      h.indexOf("vidhidefast") !== -1 ||
      h.indexOf("vidhidepro") !== -1 ||
      h.indexOf("vidhidepre") !== -1
    )
      return 0;
    // 1 = StreamWish (RESPALDO AUTOMÁTICO)
    if (
      h.indexOf("streamwish") !== -1 ||
      h.indexOf("hglink") !== -1 ||
      h.indexOf("streamhg") !== -1 ||
      h.indexOf("playnixes") !== -1 ||
      h.indexOf("hglamioz") !== -1 ||
      h.indexOf("medixiru") !== -1 ||
      h.indexOf("hgcloud") !== -1 ||
      h.indexOf("awish") !== -1 ||
      h.indexOf("streamhide") !== -1
    )
      return 1;
    // 2 = Filemoon / Byse
    if (h.indexOf("byse") !== -1 || h.indexOf("filemoon") !== -1) return 2;
    // 3 = VOE
    if (h.indexOf("voe") !== -1 || VOE_RE.test(h)) return 3;
    return 9;
  }

  async resolveEmbed(embed, referer) {
    this._lastResolveError = "";
    const src = this.fix(embed);
    if (!src) return null;
    if (/\.m3u8(\?|#|$)/i.test(src)) {
      return { type: "hls", url: src, headers: { Referer: referer, "User-Agent": UA } };
    }
    if (/\.mp4(\?|#|$)/i.test(src)) {
      return { type: "mp4", url: src, headers: { Referer: referer, "User-Agent": UA } };
    }

    // 1. VidHide prioritario
    if (/vidhide|earnvids|morencius|callistanise|minochinos|vsharea|vhide|vid-hide|vidhideplus|vidhidefast/i.test(src)) {
      const r = await this.vidhide(src);
      if (r) return r;
    }
    // 2. StreamWish como respaldo
    if (/streamwish|hglink|streamhg|playnixes|hglamioz|medixiru|awish|wish/i.test(src)) {
      const r = await this.streamwish(src);
      if (r) return r;
    }
    // 3. Filemoon / Byse
    if (BYSE_RE.test(src)) {
      const r = await this.byse(src);
      if (r) return r;
    }
    // 4. VOE
    if (VOE_RE.test(src)) {
      const r = await this.voe(src);
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

  // ---- StreamWish: mirrors en paralelo + m3u8 mas rapido + cache ----
  async streamwish(embed) {
    const src = this.fix(embed);
    const clean = src.split("#")[0];
    const id = (clean.split("?")[0].split("/").filter(Boolean).pop() || "").replace(
      /\.html?$/i,
      ""
    );
    if (!id) return null;
    const search = (clean.match(/\?[^#]*/) || [""])[0];
    const own = (this.originOf(src) || "")
      .replace(/^https?:\/\//i, "")
      .replace(/^www\./i, "")
      .replace(/\/.*$/, "")
      .toLowerCase();

    this._sw = this._sw || {};
    const now = Date.now();
    const hit = this._sw[id];
    if (hit && hit.exp > now) {
      return { type: "hls", url: hit.url, headers: Object.assign({}, hit.headers) };
    }

    const norm = (h) =>
      String(h || "")
        .replace(/^https?:\/\//i, "")
        .replace(/^www\./i, "")
        .replace(/\/.*$/, "")
        .toLowerCase();

    // Ola 1: mirrors que sirven el HTML directo (hglink/streamwish usan JS).
    const wave1 = [];
    const add1 = (h) => {
      h = norm(h);
      if (h && wave1.indexOf(h) === -1) wave1.push(h);
    };
    if (!/^(hglink\.to|streamwish\.to|streamhg\.com)$/i.test(own)) add1(own);
    add1("playnixes.com");
    add1("hglamioz.com");
    add1("medixiru.com");

    let got = await this.swFirst(wave1.map((h) => this.swHost(h, id, search)));
    if (!got && !this._lastResolveError) {
      const wave2 = SW_HOSTS.map(norm).filter((h) => wave1.indexOf(h) === -1).slice(0, 3);
      got = await this.swFirst(wave2.map((h) => this.swHost(h, id, search)));
    }
    if (!got) {
      if (!this._lastResolveError) {
        this._lastResolveError = "StreamWish no devolvió la lista de reproducción.";
      }
      return null;
    }

    const picked = await this.swPick(got.cands);
    if (!picked) {
      this._lastResolveError = "StreamWish devolvió un HLS que no responde.";
      return null;
    }

    this._sw[id] = {
      url: picked.url,
      headers: Object.assign({}, picked.headers || {}),
      exp: now + 600000,
    };
    return {
      type: "hls",
      url: picked.url,
      headers: picked.headers,
      verified: true,
    };
  }

  async swHost(host, id, search) {
    try {
      let html = await this.swGet(
        "https://" + host + "/e/" + id + search,
        "https://www.google.com/"
      );
      let cands = this.swHtml(html, "https://" + host);
      if (!cands.length && !this._lastResolveError) {
        html = await this.swGet(
          "https://" + host + "/v/" + id + search,
          "https://" + host + "/"
        );
        cands = this.swHtml(html, "https://" + host);
      }
      return cands.length ? { host: host, cands: cands } : null;
    } catch (_) {
      return null;
    }
  }

  async swGet(url, referer) {
    const req = this.request("", {
      headers: {
        "Miru-Url": url,
        "Referer": referer || "https://www.google.com/",
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
        "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
      },
    }).catch(() => "");
    let html = "";
    try {
      html =
        typeof setTimeout === "function"
          ? await Promise.race([
              req,
              new Promise((res) => setTimeout(() => res(""), 3000)),
            ])
          : await req;
    } catch (_) {
      return "";
    }
    if (typeof html !== "string" || html.length < 800) return "";
    if (/no longer available|expired or has been deleted|file (?:was )?not found/i.test(html)) {
      this._lastResolveError = "El enlace de StreamWish expiró o fue eliminado.";
      return "";
    }
    if (/Page is loading|Redirecting|Just a moment/i.test(html)) {
      this._lastResolveError =
        "StreamWish está bloqueando la petición (Cloudflare o redirección).";
      return "";
    }
    return html;
  }

  swHtml(html, base) {
    const out = [];
    let un = this.unpack(this.locate(html, "links"));
    if (!un) un = this.unpack(this.locate(html, "sources"));
    if (!un) return out;
    const block =
      un.match(/links\s*=\s*\{([\s\S]*?)\}/) ||
      un.match(/sources\s*[:=]\s*\[([\s\S]*?)\]/);
    if (!block) return out;
    const links = {};
    const re = /["']([a-zA-Z0-9_]+)["']\s*:\s*["']([^"']+)["']/g;
    let m;
    while ((m = re.exec(block[1]))) links[m[1]] = m[2];

    // PRIORIDAD: hls2 es el .m3u8 real con video MPEG-TS.
    // hls3 suele ser .txt y hls4 suele ser anuncio/tiktokcdn.
    const keys = ["hls2", "hls3", "hls4"].concat(Object.keys(links));
    const seen = {};
    for (const k of keys) {
      if (seen[k]) continue;
      seen[k] = true;
      let u = this.fix(links[k] || "");
      if (!u) continue;
      let rooted = false;
      if (u.indexOf("/") === 0) {
        u = base + u;
        rooted = true;
      }
      if (!/\.m3u8|master\.txt|playlist\.txt|\/hls\//i.test(u)) continue;
      const ref = k === "hls4" || rooted ? base + "/" : "https://streamwish.to/";
      out.push({
        type: "hls",
        url: u,
        headers: { Referer: ref, "User-Agent": UA },
      });
    }

    // Sin packer: cualquier m3u8 suelto en el HTML.
    if (!out.length) {
      const rx = /["']((?:https?:)?\/\/[^"'\s]+\.m3u8[^"'\s]*|\/[^"'\s]+\.m3u8[^"'\s]*)["']/gi;
      while ((m = rx.exec(String(html || ""))) !== null) {
        let u = this.fix(m[1]);
        if (u.indexOf("/") === 0) u = base + u;
        if (!out.some((x) => x.url === u)) {
          out.push({
            type: "hls",
            url: u,
            headers: { Referer: base + "/", "User-Agent": UA },
          });
        }
      }
    }
    return out;
  }

  swPick(cands) {
    if (!cands || !cands.length) return Promise.resolve(null);
    // Priorizar hls2 (.m3u8 estándar con segmentos .ts de video)
    const hls2 = cands.filter(
      (c) => /premilkyway|\.m3u8/i.test(c.url) && !/\/stream\//i.test(c.url)
    );
    const hls3 = cands.filter(
      (c) => !/premilkyway/i.test(c.url) && !/\/stream\//i.test(c.url)
    );
    const rest = cands.filter((c) => /\/stream\//i.test(c.url));
    const sorted = hls2.concat(hls3).concat(rest);
    if (!sorted.length) return Promise.resolve(null);

    const primary = sorted[0];
    const alts = sorted.slice(1).map((x) => x.url);
    const headers = Object.assign({}, primary.headers || {});
    if (alts.length > 0) {
      headers["X-Netu-Alts"] = JSON.stringify(alts);
    }
    return Promise.resolve({
      type: "hls",
      url: primary.url,
      headers: headers,
      verified: true,
    });
  }

  swReq(url, headers, ms) {
    const req = this.request("", {
      headers: Object.assign({ "Miru-Url": url }, headers || {}),
    }).catch(() => "");
    if (typeof setTimeout !== "function") return req;
    return Promise.race([
      req,
      new Promise((res) => setTimeout(() => res(""), ms || 5000)),
    ]);
  }

  absUrl(u, base) {
    u = this.fix(u);
    if (!u) return "";
    if (/^https?:\/\//i.test(u)) return u;
    const o = this.originOf(base) || "";
    if (u.charAt(0) === "/") return o + u;
    const b = String(base || "").split("#")[0].split("?")[0];
    return o + b.slice(o.length, b.lastIndexOf("/") + 1) + u;
  }

  hlsParse(txt, base) {
    const lines = String(txt || "").split(/\r?\n/);
    const variants = [];
    const segs = [];
    if (String(txt || "").indexOf("#EXT-X-STREAM-INF") !== -1) {
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].trim().indexOf("#EXT-X-STREAM-INF") !== 0) continue;
        for (let j = i + 1; j < lines.length; j++) {
          const s = lines[j].trim();
          if (!s) continue;
          if (s.charAt(0) !== "#") {
            const u = this.absUrl(s, base);
            if (u && variants.indexOf(u) === -1) variants.push(u);
            break;
          }
        }
      }
    } else {
      for (let i = 0; i < lines.length; i++) {
        const s = lines[i].trim();
        if (!s || s.charAt(0) === "#") continue;
        const u = this.absUrl(s, base);
        if (u) segs.push(u);
      }
    }
    return { variants: variants, segs: segs };
  }

  async swProbe(c, ms) {
    if (!c || !c.url) return null;
    const hdr = Object.assign({ "Accept": "*/*" }, c.headers || {});
    const master = await this.swReq(c.url, hdr, ms || 5000);
    if (typeof master !== "string" || master.indexOf("#EXTM3U") === -1) return null;

    let vurl = c.url;
    let body = master;
    let parsed = this.hlsParse(master, c.url);
    if (parsed.variants.length) {
      vurl = parsed.variants[0];
      body = await this.swReq(vurl, hdr, ms || 5000);
      if (typeof body !== "string" || body.indexOf("#EXTM3U") === -1) return null;
      parsed = this.hlsParse(body, vurl);
    }
    const segs = parsed.segs;
    if (!segs.length) return null;

    let img = 0;
    let media = 0;
    for (const u of segs) {
      if (/tiktokcdn|\.png(\?|$)|\.jpe?g(\?|$)|\.webp(\?|$)|[?&]x-expires=|image\//i.test(u)) {
        img++;
      } else if (/\.ts(\?|$)|\.m4s(\?|$)|\.aac(\?|$)|\.mp4(\?|$)|\.txt(\?|$)/i.test(u) || !/\.(png|jpe?g|webp|gif|bmp|svg)/i.test(u)) {
        media++;
      }
    }
    if (!media || img * 2 >= segs.length) return null;

    return Object.assign({}, c, { verified: true });
  }

  limit(p, ms, fallback) {
    const done = Promise.resolve(p).catch(() => fallback);
    if (typeof setTimeout !== "function") return done;
    return Promise.race([
      done,
      new Promise((res) => setTimeout(() => res(fallback), ms)),
    ]);
  }

  swFirst(tasks) {
    return new Promise((resolve) => {
      let pending = tasks.length;
      let done = false;
      if (!pending) return resolve(null);
      for (const t of tasks) {
        Promise.resolve(t)
          .then(
            (r) => {
              if (!done && r) {
                done = true;
                resolve(r);
              }
            },
            () => {}
          )
          .then(() => {
            pending--;
            if (!pending && !done) resolve(null);
          });
      }
    });
  }

  // ---- VidHide: priorizado como #1, paralelo ultra-rápido, /embed/ directo + cache ----
  async vidhide(embed) {
    const src = this.fix(embed);
    const clean = src.split("#")[0];
    const idm = clean.match(/\/(?:v|e|embed)\/([A-Za-z0-9]+)/i);
    const id = idm
      ? idm[1]
      : (clean.split("?")[0].split("/").filter(Boolean).pop() || "");
    if (!id) return null;
    const search = (clean.match(/\?[^#]*/) || [""])[0];
    const own = (this.originOf(src) || "")
      .replace(/^https?:\/\//i, "")
      .replace(/^www\./i, "")
      .replace(/\/.*$/, "")
      .toLowerCase();

    this._vh = this._vh || {};
    const now = Date.now();
    const hit = this._vh[id];
    if (hit && hit.exp > now) {
      return { type: "hls", url: hit.url, headers: Object.assign({}, hit.headers) };
    }

    const norm = (h) =>
      String(h || "")
        .replace(/^https?:\/\//i, "")
        .replace(/^www\./i, "")
        .replace(/\/.*$/, "")
        .toLowerCase();

    // Espejos ordenados: el propio origen del enlace (morencius/callistanise) y espejos activos directos
    const hosts = [];
    const addHost = (h) => {
      h = norm(h);
      if (h && hosts.indexOf(h) === -1) hosts.push(h);
    };
    if (own) addHost(own);
    addHost("callistanise.com");
    addHost("morencius.com");
    addHost("vidhidefast.com");

    const found = await this.swFirst(
      hosts.map((h) => this.vidhideHost(h, id, search))
    );
    if (!found) {
      if (!this._lastResolveError) {
        this._lastResolveError = "VidHide no devolvió un stream reproducible.";
      }
      return null;
    }

    this._vh[id] = {
      url: found.url,
      headers: Object.assign({}, found.headers || {}),
      exp: now + 600000, // 10 minutos de caché
    };
    return found;
  }

  async vidhideHost(h, id, search) {
    // Probar /embed/ primero (más rápido, directo), luego /v/ si hiciera falta
    try {
      let page = "https://" + h + "/embed/" + id + search;
      let html = await this.vidhideGet(page, "https://google.com/");
      let stream = html ? this.streamFromPage(html, "https://" + h) : null;
      if (!stream && !this._lastResolveError) {
        page = "https://" + h + "/v/" + id + search;
        html = await this.vidhideGet(page, "https://" + h + "/");
        if (html) stream = this.streamFromPage(html, "https://" + h);
      }
      return stream;
    } catch (_) {
      return null;
    }
  }

  async vidhideGet(url, referer) {
    const req = this.request("", {
      headers: {
        "Miru-Url": url,
        "Referer": referer || "https://google.com/",
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
        "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
      },
    }).catch(() => "");
    let html = "";
    try {
      html =
        typeof setTimeout === "function"
          ? await Promise.race([
              req,
              new Promise((res) => setTimeout(() => res(""), 3500)),
            ])
          : await req;
    } catch (_) {
      return "";
    }
    if (typeof html !== "string" || !html || html.length < 500) return "";
    if (
      html.length < 2000 &&
      (html.indexOf("Page is loading") !== -1 || html.indexOf("Redirecting") !== -1)
    ) {
      try {
        const req2 = this.request("", {
          headers: { "Miru-Url": url, "Referer": url, "User-Agent": UA },
        }).catch(() => "");
        html =
          typeof setTimeout === "function"
            ? await Promise.race([
                req2,
                new Promise((res) => setTimeout(() => res(""), 3500)),
              ])
            : await req2;
      } catch (_) {}
    }
    if (typeof html !== "string" || !html) return "";
    if (/no longer available|expired or has been deleted|file (?:was )?not found/i.test(html)) {
      this._lastResolveError = "El enlace de VidHide expiró o fue eliminado.";
      return "";
    }
    if (html.indexOf("Just a moment") !== -1) {
      this._lastResolveError = "VidHide está bloqueando la petición (Cloudflare).";
      return "";
    }
    return html;
  }

  streamFromPage(html, origin) {
    const body = String(html || "");
    const abs = (u) => {
      let s = this.fix(u);
      if (s.indexOf("//") === 0) return "https:" + s;
      if (s.indexOf("/") === 0) return origin + s;
      return s;
    };

    let un = "";
    if (body.indexOf("eval(function(p,a,c,k,e") !== -1) {
      un = this.unpack(body) || "";
    }
    const text = un || body;

    // 1. VidHide estructurado con var links = { "hls2": "...", ... }
    const linksBlock =
      text.match(/links\s*=\s*(\{[\s\S]*?\});?/) ||
      text.match(/sources\s*[:=]\s*\[([\s\S]*?)\]/);
    if (linksBlock) {
      try {
        const re = /["']([a-zA-Z0-9_]+)["']\s*:\s*["']([^"']+)["']/g;
        const links = {};
        let lm;
        while ((lm = re.exec(linksBlock[1]))) {
          links[lm[1]] = lm[2];
        }
        // Priorizar hls2 (.m3u8 estándar con TS), luego hls3, luego hls4
        const ordered = ["hls2", "hls3", "hls4"].concat(Object.keys(links));
        const cands = [];
        for (const k of ordered) {
          const rawU = links[k];
          if (rawU && !cands.some((c) => c === rawU)) {
            let u = abs(rawU);
            if (/\.m3u8|master\.txt|playlist\.txt|\/hls\//i.test(u)) {
              cands.push(u);
            }
          }
        }
        if (cands.length > 0) {
          const primary = cands[0];
          const alts = cands.slice(1);
          const headers = { Referer: origin + "/", "User-Agent": UA };
          if (alts.length > 0) {
            headers["X-Netu-Alts"] = JSON.stringify(alts);
          }
          return {
            type: "hls",
            url: primary,
            headers: headers,
            verified: true,
          };
        }
      } catch (_) {}
    }

    // 2. Extracción directa de URL .m3u8 (descartando imágenes, thumbnails, pistas)
    const m3u8Match = text.match(
      /["']((?:https?:)?\/\/[^"'<>\s]+\.(?:m3u8|txt)(?:\?[^"'<>\s]*)?|\/[^"'<>\s]+\.m3u8(?:\?[^"'<>\s]*)?)["']/i
    );
    if (m3u8Match) {
      const u = abs(m3u8Match[1]);
      if (!/dl\?op=|\.jpg|\.png|\.webp|thumbnails/i.test(u)) {
        return {
          type: "hls",
          url: u,
          headers: { Referer: origin + "/", "User-Agent": UA },
          verified: true,
        };
      }
    }

    // 3. MP4 directo
    const mp4Match = text.match(/file\s*:\s*["']([^"']+\.mp4(?:\?[^"']*)?)["']/i);
    if (mp4Match) {
      return {
        type: "mp4",
        url: abs(mp4Match[1]),
        headers: { Referer: origin + "/", "User-Agent": UA },
        verified: true,
      };
    }

    return null;
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
        if (/Confirm you(?:'|&#39;|’)?re human|altcha|verify you are human|cf-turnstile|hcaptcha/i.test(res)) {
          this._lastResolveError =
            "VOE requiere verificación humana (Altcha); use VidHide o StreamWish.";
          return null;
        }

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

        if (/Confirm you(?:'|&#39;|’)?re human|altcha|verify you are human|cf-turnstile|hcaptcha/i.test(res)) {
          this._lastResolveError =
            "VOE requiere verificación humana (Altcha); use VidHide o StreamWish.";
          return null;
        }

        if (res.indexOf('<script type="application/json">["') !== -1 || /\.m3u8/i.test(res)) {
          html = res;
          break;
        }
      }
      if (!html) {
        if (!this._lastResolveError) {
          this._lastResolveError = "VOE no devolvió la configuración del video.";
        }
        return null;
      }

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
      if (!url) {
        this._lastResolveError = "VOE no expuso una URL de video válida.";
        return null;
      }

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
