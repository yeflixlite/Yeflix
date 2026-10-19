// ==MiruExtension==
// @name         Latanime
// @version      v0.1.1
// @author       YeaniFlix
// @lang         es
// @license      MIT
// @package      latanime
// @type         bangumi
// @icon         https://latanime.org/favicon.ico
// @webSite      https://latanime.org
// @nsfw         false
// ==/MiruExtension==

// Latanime (https://latanime.org) - Laravel + Cloudflare (proxied, SIN challenge).
//
//   Populares / catalogo : /emision?p=<page>   -> tarjetas "div.row > div"
//   Busqueda             : /buscar?q=<q>&p=<page>
//   Detalle serie        : /anime/<slug>       -> titulo, portada, sinopsis, episodios
//   Episodio             : /ver/<slug>         -> lista de servidores
//
// El reproductor de /ver no trae el video: trae botones
//   <a class="play-video" data-player="<base64 del embed>">
// El embed (playmogo=Dood, mixdrop, mp4upload, filemoon, voe, ...) se resuelve
// aparte. La app solo acepta hls/mp4/torrent (no iframes), asi que hay que
// sacar la URL directa del stream.

const SITE = "https://latanime.org";
const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

export default class extends Extension {
  // ------------------------------------------------------------------ listas
  async latest(page) {
    try {
      const p = Math.max(1, parseInt(page) || 1);
      const res = await this.request("/emision?p=" + p, { headers: this.reqHeaders(SITE) });
      return await this.parseCards(res);
    } catch (_) {
      return [];
    }
  }

  async search(kw, page) {
    try {
      const q = encodeURIComponent(((kw || "") + "").trim());
      const p = Math.max(1, parseInt(page) || 1);
      const res = await this.request("/buscar?q=" + q + "&p=" + p, { headers: this.reqHeaders(SITE) });
      return await this.parseCards(res);
    } catch (_) {
      return [];
    }
  }

  async createFilter() {
    return [];
  }

  async parseCards(res) {
    if (!res || typeof res !== "string") return [];
    const out = [];
    let items = [];
    try {
      items = await this.querySelectorAll(res, "div.row > div");
    } catch (_) {
      items = [];
    }
    for (const el of items) {
      const html = el.content;
      const url = await this.getAttributeText(html, "a", "href");
      if (!url || url.indexOf("/anime/") === -1) continue;

      let title = "";
      try {
        title = ((await this.querySelector(html, "div.seriedetails > h3").text) || "").trim();
      } catch (_) {}
      if (!title) {
        try {
          title = ((await this.querySelector(html, "h3").text) || "").trim();
        } catch (_) {}
      }

      let cover = await this.getAttributeText(html, "img", "data-src");
      if (!cover) cover = await this.getAttributeText(html, "img", "src");

      if (title) out.push({ title: title, url: url, cover: cover || "" });
    }
    return out;
  }

  // ------------------------------------------------------------------ detalle
  async detail(url) {
    const full = this.norm(url);
    let res = "";
    try {
      res = await this.request("", { headers: this.reqHeaders(full) });
    } catch (_) {
      res = "";
    }
    if (!res || typeof res !== "string") {
      return { title: "Latanime", cover: "", desc: "No se pudo cargar el detalle.", episodes: [] };
    }

    let title = "";
    try {
      title = ((await this.querySelector(res, "div.row > div > h2").text) || "").trim();
    } catch (_) {}
    if (!title) title = this.meta(res, "og:title");

    let cover = this.meta(res, "og:image");
    if (!cover) cover = await this.getAttributeText(res, "img", "src");

    let desc = "";
    try {
      desc = ((await this.querySelector(res, "p.my-2").text) || "").replace(/\s+/g, " ").trim();
    } catch (_) {}

    // Episodios: enlaces /ver/<slug>-episodio-N
    const eps = [];
    const seen = {};
    const re = /<a\b[^>]*href=["']([^"']*\/ver\/[^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
    let m;
    while ((m = re.exec(res))) {
      const href = this.fix(m[1]);
      if (!href || seen[href]) continue;
      seen[href] = 1;
      const name = m[2].replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
      eps.push({ name: name || ("Episodio " + (eps.length + 1)), url: href });
    }
    eps.reverse();

    const groups = [];
    if (eps.length > 0) {
      groups.push({ title: "Episodios", urls: eps });
    } else {
      groups.push({ title: "Ver", urls: [{ name: "Reproducir", url: full }] });
    }

    return { title: (title || "Latanime").trim(), cover: cover || "", desc: desc, episodes: groups };
  }

  // ------------------------------------------------------------------ watch
  async watch(url) {
    const full = this.norm(url);

    // La app llama watch(embedUrl) al cambiar/failover de servidor.
    if (this.isEmbed(full)) {
      if (/\/reproductor/i.test(full)) {
        const m = full.match(/[?&]url=([^&]+)/i);
        if (m) return (await this.resolveEmbed(decodeURIComponent(m[1]), full)) || this.err("Servidor no resoluble");
      }
      return (await this.resolveEmbed(full, full)) || this.err("Servidor no resoluble");
    }

    let res = "";
    try {
      res = await this.request("", { headers: this.reqHeaders(full) });
    } catch (_) {
      res = "";
    }
    if (!res || typeof res !== "string") return this.err("No se pudo cargar el episodio");

    const servers = this.servers(res);
    if (!servers.length) {
      const inline = this.findStream(res, full);
      return inline || this.err("No se encontraron servidores");
    }

    // Mapa para el selector de servidores y el failover automatico de la app.
    // Se ordena por fiabilidad para que el failover pruebe mixdrop antes.
    const ranked = servers
      .slice()
      .sort((a, b) => this.rankHost(a.url) - this.rankHost(b.url));
    const map = {};
    const refs = {};
    for (const s of ranked) {
      map[s.name] = s.url;
      refs[s.name] = full;
    }
    const extra = {
      "X-Servers": JSON.stringify(map),
      "X-Server-Referers": JSON.stringify(refs),
    };

    // Primario: probar primero los hosts mas fiables (mp4upload, mixdrop, ...).
    const ordered = servers.slice().sort((a, b) => this.rankHost(a.url) - this.rankHost(b.url));
    for (const s of ordered) {
      const r = await this.resolveEmbed(s.url, full);
      if (r && r.url) {
        r.headers = Object.assign({}, r.headers, extra, { "X-Primary-Server": s.name });
        return r;
      }
    }

    return { type: "hls", url: "error://Ningun servidor resoluble", headers: extra };
  }

  err(msg) {
    return { type: "hls", url: "error://" + msg };
  }

  // Una URL "embed" (de terceros) frente a una pagina /ver del sitio.
  isEmbed(u) {
    const m = u.match(/^https?:\/\/([^\/]+)/i);
    const host = m ? m[1].toLowerCase() : "";
    if (host.indexOf("latanime.org") !== -1) return /\/reproductor/i.test(u);
    return true;
  }

  // Prioridad de servidores: los que sabemos resolver/reproducir primero.
  // mixdrop va primero: mp4upload usa el puerto 183 y suele dar timeout/403.
  rankHost(u) {
    const h = (u.match(/^https?:\/\/([^\/]+)/i) || ["", ""])[1].toLowerCase();
    if (h.indexOf("mixdrop") !== -1 || h.indexOf("mxdrop") !== -1) return 0;
    if (h.indexOf("mp4upload") !== -1) return 1;
    if (h.indexOf("dood") !== -1 || h.indexOf("playmogo") !== -1 || h.indexOf("ds2") !== -1) return 2;
    return 3;
  }

  // Lista de servidores desde los botones data-player (base64).
  servers(html) {
    const out = [];
    let re = /<a\b[^>]*\bdata-player=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
    let m;
    while ((m = re.exec(html))) {
      const u = this.fix(this.b64(m[1]));
      if (!u) continue;
      const name = m[2].replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
      out.push({ name: name || ("Servidor " + (out.length + 1)), url: u });
    }
    if (!out.length) {
      re = /<a\b[^>]*\bdata-video=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
      while ((m = re.exec(html))) {
        const u = this.fix(this.b64(m[1]));
        if (u) out.push({ name: "Servidor", url: u });
      }
    }
    return out;
  }

  // Resuelve un embed de terceros a una URL directa de stream.
  async resolveEmbed(embed, referer) {
    const src = this.fix(embed);
    if (!src) return null;
    if (/\.m3u8(\?|#|$)/i.test(src)) {
      return { type: "hls", url: src, headers: { Referer: referer, "User-Agent": UA } };
    }
    if (/\.mp4(\?|#|$)/i.test(src)) {
      return { type: "mp4", url: src, headers: { Referer: referer, "User-Agent": UA } };
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

    // DoodStream (playmogo, ds2play, ...): data.pass_md5
    if (html.indexOf("/pass_md5/") !== -1) {
      const r = await this.dood(src, html);
      if (r) return r;
    }
    // MixDrop: MDCore + JS empaquetado
    if (html.indexOf("MDCore") !== -1) {
      const r = this.mixdrop(html);
      if (r) return r;
    }
    // Filemoon y clones: eval(...) con m3u8
    if (html.indexOf("eval(function(p,a,c,k,e") !== -1) {
      const r = this.filemoon(html, src);
      if (r) return r;
    }
    // mp4upload (videojs con video/mp4) y generico
    const r = this.findStream(html, src);
    if (r) return r;

    return null;
  }

  // ---- DoodStream --------------------------------------------------------
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

      const url = base.replace(/\s+$/, "") + this.rnd(10) + "?token=" + token + "&expiry=" + Date.now();
      return { type: "mp4", url: url, headers: { Referer: host + "/", "User-Agent": UA } };
    } catch (_) {
      return null;
    }
  }

  // ---- MixDrop -----------------------------------------------------------
  mixdrop(html) {
    const region = this.locate(html, "MDCore");
    const un = this.unpack(region);
    if (!un) return null;
    let u = (un.match(/Core\.wurl\s*=\s*["']([^"']+)["']/) || [])[1];
    if (!u) u = (un.match(/wurl\s*=\s*["']([^"']+)["']/) || [])[1];
    if (!u) return null;
    u = this.fix(u);
    return { type: "mp4", url: u, headers: { Referer: "https://mixdrop.co/", "User-Agent": UA } };
  }

  // ---- Filemoon y clones -------------------------------------------------
  filemoon(html, referer) {
    const region = this.locate(html, "m3u8");
    const un = this.unpack(region);
    if (!un) return null;
    const f = un.match(/file\s*:\s*["']([^"']+)["']/);
    if (!f) return null;
    return { type: "hls", url: this.fix(f[1]), headers: { Referer: referer, "User-Agent": UA } };
  }

  // ---- generico: m3u8 / mp4 en el HTML o tras desempacar ---------------
  findStream(text, referer) {
    if (!text || typeof text !== "string") return null;
    const headers = { Referer: referer, "User-Agent": UA };

    let m = text.match(/src\s*:\s*["'](https?:[^"']+\.mp4[^"']*)["']/i) ||
      text.match(/["'](https?:\\?\/\\?\/[^"'<>\s]+?\.mp4[^"'<>\s]*)["']/i);
    if (m) return { type: "mp4", url: this.fix(m[1]), headers: headers };

    m = text.match(/["'](https?:\\?\/\\?\/[^"'<>\s]+?\.m3u8[^"'<>\s]*)["']/i) ||
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
  // Extrae el <script> que contiene un marcador (para no desempacar todo).
  locate(html, marker) {
    const re = /<script\b[^>]*>([\s\S]*?)<\/script>/gi;
    let m;
    while ((m = re.exec(html))) {
      if (m[1].indexOf(marker) !== -1 && m[1].indexOf("eval(function(p,a,c,k,e") !== -1) return m[1];
    }
    return html;
  }

  // Desempaqueta el "packer" clasico (Dean Edwards): eval(function(p,a,c,k,e,d){...})
  unpack(src) {
    if (!src || typeof src !== "string") return "";
    const m = src.match(/}\s*\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'\.split\(/);
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
    s = String(s || "").replace(/=+$/, "").replace(/[^A-Za-z0-9+/]/g, "");
    let bits = "";
    for (let i = 0; i < s.length; i++) {
      const v = A.indexOf(s.charAt(i));
      if (v < 0) continue;
      bits += ("000000" + v.toString(2)).slice(-6);
    }
    let out = "";
    for (let i = 0; i + 8 <= bits.length; i += 8) out += String.fromCharCode(parseInt(bits.substr(i, 8), 2));
    return out;
  }

  rnd(n) {
    const A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let s = "";
    for (let i = 0; i < n; i++) s += A.charAt(Math.floor(Math.random() * A.length));
    return s;
  }

  reqHeaders(ref) {
    return {
      "Miru-Url": ref,
      Referer: ref,
      Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
      "User-Agent": UA,
    };
  }

  norm(url) {
    if (!url) return SITE + "/";
    if (/^https?:/i.test(url)) return url;
    if (url.indexOf("//") === 0) return "https:" + url;
    return SITE + (url.charAt(0) === "/" ? "" : "/") + url;
  }

  fix(u) {
    const s = (u || "")
      .replace(/\\\//g, "/")
      .replace(/\\u0026/gi, "&")
      .replace(/&amp;/gi, "&")
      .replace(/&#0?38;/g, "&")
      .trim();
    if (s.indexOf("//") === 0) return "https:" + s;
    return s;
  }

  meta(html, key) {
    const tags = html.match(/<meta\b[^>]*>/gi) || [];
    for (const t of tags) {
      if (t.indexOf(key) !== -1) {
        const c = t.match(/content=["']([^"']*)["']/i);
        if (c) return c[1];
      }
    }
    return "";
  }
}
