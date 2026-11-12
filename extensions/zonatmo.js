// ==MiruExtension==
// @name         ZonaTMO
// @version      v0.1.3
// @author       YeaniFlix
// @lang         es
// @license      MIT
// @package      zonatmo
// @type         manga
// @icon         https://zonatmo.org/favicon/apple-touch-icon.png
// @webSite      https://zonatmo.org
// @nsfw         false
// ==/MiruExtension==

export default class extends Extension {
  constructor() {
    super();
    this.siteUrl = "https://zonatmo.org";
    // Exclusión obligatoria permanente en servidor:
    // +18, +19, Adulto, Maduro, Hentai, Ecchi, Doujinshi, Smut, Erotica, Gore,
    // BL (Boys Love), Yaoi, Shounen-ai, Omegaverse, Yuri, Girls Love, Sin Censura, Toxicidad
    this.excludedGenderIds = [
      19, // Ecchi
      27, // +18
      29, // Smut
      30, // Boys Love
      31, // Yaoi
      32, // Adulto
      33, // Maduro
      35, // Girls Love
      44, // Gore
      52, // Yuri
      68, // Traps
      80, // BL (Boys Love)
      81, // Adult Cast
      92, // Doujinshi
      94, // Shonen-ai
      95, // Shonen-ai (Yaoi Soft)
      96, // Yaoi (Soft)
      123, // Erotica
      129, // Shounen Ai
      132, // Omegaverse
      140, // Toxicidad
      141, // Mucho Gogogo
      142, // Manhwa +19
      143, // BL
      144, // +19
      149, // boys
      150, // boyslove
      153, // Bl Sin Censura
      155, // Nobl💌
      156  // Toxicidad Nivel Chernóbil
    ];
  }

  getExcludeParam() {
    return this.excludedGenderIds.map((id) => `exclude_genders[]=${id}`).join("&");
  }

  isNsfw(text) {
    if (!text) return false;
    const nsfwPattern = /(hentai|doujinshi|ecchi|erotica|erótico|smut|\+18|\+19|adulto|adultos|mature|maduro|gore|sin\s*censura|uncensored|r18|xxx|\bbl\b|yaoi|boys?\s*love|boy['’]?s\s*love|shounen[\s\-_]*ai|shonen[\s\-_]*ai|omegaverse|danmei|bara|yuri|girls?\s*love|anastasia|jinx|orco\s*y\s*el\s*elfo|bj\s*alex|pintor\s*nocturno|marea\s*baja|define\s*la\s*relaci[oó]n|el\s*chico\s*de\s*la\s*perla|seducci[oó]n\s*de\s*la\s*serpiente|vecinos\s*intimos|smyrna|d[ií]as\s*soleados|omega\s*complex|querida\s*puerta|convenience\s*store|desire\s*me)/i;
    return nsfwPattern.test(text);
  }

  async req(targetUrl) {
    return await this.request("", {
      headers: {
        "Miru-Url": targetUrl,
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://zonatmo.org/",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "es-ES,es;q=0.9"
      }
    });
  }

  parseCards(html) {
    const cards = [];
    const cardRegex = /<div[^>]*class="[^"]*element[^"]*"[\s\S]*?<a[^>]+href="([^"]+)"[\s\S]*?<\/a>\s*<\/div>/gi;
    let match;

    while ((match = cardRegex.exec(html)) !== null) {
      const cardHtml = match[0];
      const url = match[1];

      // 1. Exclusión directa por badge de contenido maduro / +18 / +19 en la tarjeta
      if (
        cardHtml.includes("book-meta-mature") ||
        cardHtml.includes("Contenido para mayores de 18") ||
        cardHtml.includes(">+18<") ||
        cardHtml.includes(">+19<")
      ) {
        continue;
      }

      // 2. Comprobación general en el HTML íntegro de la tarjeta
      if (this.isNsfw(cardHtml)) {
        continue;
      }

      // Título
      const titleMatch = cardHtml.match(/<h4[^>]*title="([^"]+)"/i) || cardHtml.match(/<h4[^>]*>([\s\S]*?)<\/h4>/i);
      const rawTitle = titleMatch ? (titleMatch[1] || titleMatch[2]).replace(/<[^>]+>/g, "").trim() : "";
      if (!rawTitle || this.isNsfw(rawTitle)) {
        continue;
      }

      // Tipo de obra
      const typeMatch = cardHtml.match(/<span[^>]*class="[^"]*book-type[^"]*"[^>]*>([\s\S]*?)<\/span>/i);
      const rawType = typeMatch ? typeMatch[1].replace(/<[^>]+>/g, "").trim().toUpperCase() : "MANGA";
      if (this.isNsfw(rawType)) {
        continue;
      }

      // Demografía
      const demoMatch = cardHtml.match(/<span[^>]*class="[^"]*demography[^"]*"[^>]*>([\s\S]*?)<\/span>/i);
      const demography = demoMatch ? demoMatch[1].replace(/<[^>]+>/g, "").trim() : "";
      if (this.isNsfw(demography)) {
        continue;
      }

      // Portada
      const coverMatch = cardHtml.match(/data-bg="([^"]+)"/i) || cardHtml.match(/src="([^"]+)"/i);
      const cover = coverMatch ? coverMatch[1] : "";

      // Estado
      const statusMatch = cardHtml.match(/<span[^>]*class="[^"]*book-meta-status[^"]*"[^>]*>([\s\S]*?)<\/span>/i);
      const status = statusMatch ? statusMatch[1].replace(/<[^>]+>/g, "").trim() : "";

      // Identificación de categoría original
      let typeLabel = "Manga";
      if (rawType.includes("NOVEL")) {
        typeLabel = "Novela";
      } else if (rawType.includes("MANHWA")) {
        typeLabel = "Manhwa";
      } else if (rawType.includes("MANHUA")) {
        typeLabel = "Manhua";
      } else if (rawType.includes("ONE_SHOT")) {
        typeLabel = "One Shot";
      }

      // Etiqueta visible en el título
      let displayTitle = "";
      if (typeLabel === "Novela") {
        displayTitle = `[Novela] ${rawTitle}`;
      } else if (typeLabel === "Manhwa") {
        displayTitle = `[Manhwa] ${rawTitle}`;
      } else {
        displayTitle = `[${typeLabel}] ${rawTitle}`;
      }

      cards.push({
        title: displayTitle,
        url: url,
        cover: cover,
        update: status ? `${typeLabel} • ${status}` : typeLabel
      });
    }

    return cards;
  }

  async createFilter() {
    return {
      type: {
        title: "Tipo de contenido",
        max: 1,
        min: 0,
        default: "",
        options: {
          "": "Todos (Aptos)",
          "manga": "Manga",
          "manhwa": "Manhwa",
          "novel": "Novela",
          "manhua": "Manhua"
        }
      },
      order: {
        title: "Ordenar por",
        max: 1,
        min: 0,
        default: "recently_updated",
        options: {
          "recently_updated": "Actualizados",
          "likes_count": "Populares",
          "creation": "Nuevos",
          "alphabetically": "Alfabético"
        }
      },
      demography: {
        title: "Demografía",
        max: 1,
        min: 0,
        default: "",
        options: {
          "": "Todas",
          "shounen": "Shounen",
          "seinen": "Seinen",
          "shoujo": "Shoujo",
          "josei": "Josei",
          "kodomo": "Kodomo"
        }
      },
      status: {
        title: "Estado",
        max: 1,
        min: 0,
        default: "",
        options: {
          "": "Todos",
          "ongoing": "En emisión",
          "completed": "Completado",
          "ended": "Finalizado",
          "hiatus": "En pausa"
        }
      }
    };
  }

  async latest(page = 1, filter = null) {
    return this.search("", page, filter);
  }

  async search(kw, page = 1, filter = null) {
    if (kw && this.isNsfw(kw)) {
      return [];
    }
    const pageNum = page || 1;
    const type = filter?.type?.[0] || "";
    const order = filter?.order?.[0] || "recently_updated";
    const demography = filter?.demography?.[0] || "";
    const status = filter?.status?.[0] || "";

    let url = `${this.siteUrl}/biblioteca?order_item=${order}&order_dir=desc&${this.getExcludeParam()}&page=${pageNum}`;
    if (kw && kw.trim()) {
      url += `&title=${encodeURIComponent(kw.trim())}`;
    }
    if (type) url += `&type=${encodeURIComponent(type)}`;
    if (demography) url += `&demography=${encodeURIComponent(demography)}`;
    if (status) url += `&status=${encodeURIComponent(status)}`;

    const res = await this.req(url);
    return this.parseCards(res);
  }

  async detail(url) {
    const res = await this.req(url);

    // 1. Tags oficiales de la obra
    const tags = [...res.matchAll(/href="https:\/\/zonatmo\.org\/tag\/[a-zA-Z0-9_\-]+"[^>]*>([\s\S]*?)<\/a>/gi)].map((m) =>
      m[1].replace(/<[^>]+>/g, "").trim()
    );
    for (const tag of tags) {
      if (this.isNsfw(tag)) {
        throw new Error("Contenido no apto para todo público (bloqueado por política de seguridad).");
      }
    }

    // 2. Encabezado principal de la obra (excluyendo navbar y carruseles recomendados del footer)
    const headerMatch = res.match(/<div[^>]*class="[^"]*element-header-content-text[^"]*"[\s\S]*?<\/div>/i) ||
                        res.match(/<section[^>]*class="[^"]*element-header[^"]*"[\s\S]*?<\/section>/i);
    const headerHtml = headerMatch ? headerMatch[0] : "";

    if (
      headerHtml.includes("book-meta-mature") ||
      headerHtml.includes("Contenido para mayores de 18") ||
      headerHtml.includes(">+18<") ||
      headerHtml.includes(">+19<")
    ) {
      throw new Error("Contenido no apto para todo público (bloqueado por política de seguridad).");
    }

    // 3. Título de la obra
    const titleMatch = (headerHtml || res).match(/<h1[^>]*class="[^"]*element-title[^"]*"[^>]*>([\s\S]*?)<\/h1>/i) ||
                       (headerHtml || res).match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    let title = titleMatch ? titleMatch[1].replace(/<small[\s\S]*?<\/small>/gi, "").replace(/<[^>]+>/g, "").trim() : "";

    if (!title || this.isNsfw(title)) {
      throw new Error("Obra bloqueada por política de seguridad.");
    }

    // 4. Identificación de tipo de contenido
    let typeLabel = "Manga";
    if (url.includes("/novel/")) {
      typeLabel = "Novela";
    } else if (url.includes("/manhwa/")) {
      typeLabel = "Manhwa";
    } else if (url.includes("/manhua/")) {
      typeLabel = "Manhua";
    } else {
      const typeBadge = (headerHtml || res).match(/<h1[^>]*class="[^"]*book-type[^"]*"[^>]*>([\s\S]*?)<\/h1>/i) ||
                        (headerHtml || res).match(/<span[^>]*class="[^"]*book-type[^"]*"[^>]*>([\s\S]*?)<\/span>/i);
      if (typeBadge) {
        const rawT = typeBadge[1].replace(/<[^>]+>/g, "").trim().toUpperCase();
        if (rawT.includes("NOVEL")) typeLabel = "Novela";
        else if (rawT.includes("MANHWA")) typeLabel = "Manhwa";
        else if (rawT.includes("MANHUA")) typeLabel = "Manhua";
        else if (this.isNsfw(rawT)) {
          throw new Error("Contenido no apto para todo público.");
        }
      }
    }

    if (typeLabel === "Novela" && !title.startsWith("[Novela]")) {
      title = `[Novela] ${title}`;
    } else if (typeLabel === "Manhwa" && !title.startsWith("[Manhwa]")) {
      title = `[Manhwa] ${title}`;
    } else if (!title.startsWith(`[${typeLabel}]`)) {
      title = `[${typeLabel}] ${title}`;
    }

    // 5. Portada
    const coverMatch = (headerHtml || res).match(/<img[^>]+src=["'](https:\/\/zonatmo\.org\/storage\/[^"']+)["']/i) ||
                       (headerHtml || res).match(/<img[^>]+src=["'](https:\/\/storage\d*\.zonatmo\.org\/[^"']+)["']/i) ||
                       (headerHtml || res).match(/data-bg=["']([^"']+)["']/i);
    const cover = coverMatch ? coverMatch[1] : "";

    // 6. Sinopsis
    const descMatch = res.match(/<p[^>]*class="[^"]*element-description[^"]*"[^>]*>([\s\S]*?)<\/p>/i) ||
                      res.match(/<div[^>]*class="[^"]*synopsis[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    const rawDesc = descMatch ? descMatch[1].replace(/<[^>]+>/g, "").trim() : "";

    let infoHeader = `Tipo: ${typeLabel}`;
    if (typeLabel === "Manhwa") {
      infoHeader += "\n\n💡 Modo Webtoon: Para leer las tiras en ancho completo y sin bordes estrechos, toca la pantalla, abre Ajustes (⚙️) y selecciona 'Webtoon'.";
    }
    if (tags.length > 0) {
      infoHeader += `\nGéneros: ${tags.join(", ")}`;
    }

    // 7. Lista de capítulos
    const chapterItems = [...res.matchAll(/<li[^>]*class="[^"]*upload-link[^"]*"[^>]*>([\s\S]*?)<\/li>/gi)];
    const episodes = [];

    for (const ci of chapterItems) {
      const content = ci[1];
      const numMatch = content.match(/<span[^>]*class="[^"]*chapter-number[^"]*"[^>]*>([\s\S]*?)<\/span>/i);
      const name = numMatch ? numMatch[1].replace(/<[^>]+>/g, "").trim() : "";

      const linkMatch = content.match(/href="(https:\/\/zonatmo\.org\/view_uploads\/\d+)"/i);
      if (linkMatch) {
        episodes.push({
          name: name || `Capítulo ${episodes.length + 1}`,
          url: linkMatch[1]
        });
      }
    }

    return {
      title,
      cover,
      desc: `${infoHeader}\n\n${rawDesc}`,
      episodes: [
        {
          title: "Capítulos",
          urls: episodes
        }
      ]
    };
  }

  async watch(url) {
    const res = await this.req(url);

    const images = [];
    // Extracción de imágenes del capítulo (almacenamiento CDN ZonaTMO)
    const regex = /<img[^>]+(?:src|data-src)=["']([^"']*(?:storage\d*\.zonatmo\.org\/chapters\/[^"']+))["']/gi;
    let match;
    while ((match = regex.exec(res)) !== null) {
      const imgUrl = match[1];
      if (!images.includes(imgUrl)) {
        images.push(imgUrl);
      }
    }

    // Fallback: lectores con clase reader-image
    if (images.length === 0) {
      const fallbackRegex = /<img[^>]+class="[^"]*reader-image[^"]*"[^>]+(?:src|data-src)=["']([^"']+)["']/gi;
      while ((match = fallbackRegex.exec(res)) !== null) {
        const imgUrl = match[1];
        if (!images.includes(imgUrl)) {
          images.push(imgUrl);
        }
      }
    }

    return {
      urls: images,
      headers: {
        "Referer": "https://zonatmo.org/",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      }
    };
  }
}
