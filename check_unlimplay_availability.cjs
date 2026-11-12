/**
 * UnLimPlay Batch Availability Checker & Diagnostics (v2.0)
 * 
 * Funciona con o SIN clave de API.
 * 
 * Uso:
 *   node check_unlimplay_availability.cjs [--ids=278,550,1396/1/1] [--key=ulp_TU_CLAVE] [--input=ids.json]
 */

const fs = require('fs');
const https = require('https');

const ULP_BASE = 'https://unlimplay.com';
const CACHE_FILE = 'unlimplay_cache.json';

const args = process.argv.slice(2).reduce((acc, curr) => {
  const [k, v] = curr.replace(/^--/, '').split('=');
  acc[k] = v === undefined ? true : v;
  return acc;
}, {});

const API_KEY = args.key || process.env.ULP_API_KEY || '';
const IDS_RAW = args.ids || '278,550,680,1399/1/1,1396/1/1';
const INPUT_FILE = args.input || null;
const OUT_JSON = args.out || 'unlimplay_availability.json';
const OUT_CSV = args.csv || 'unlimplay_availability.csv';
const CONCURRENCY = parseInt(args.concurrency || '2', 10);
const TIMEOUT_MS = parseInt(args.timeout || '8000', 10);

let cache = {};
if (fs.existsSync(CACHE_FILE)) {
  try { cache = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8')); } catch (_) { cache = {}; }
}

function saveCache() {
  try { fs.writeFileSync(CACHE_FILE, JSON.stringify(cache, null, 2), 'utf8'); } catch (_) {}
}

const EMBED_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Referer': 'https://cuevana.biz/',
  'Sec-Fetch-Dest': 'iframe',
  'Sec-Fetch-Mode': 'navigate',
  'Sec-Fetch-Site': 'cross-site',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
};

function fetchUrl(urlStr, headers = {}, redirects = 5) {
  return new Promise((resolve) => {
    if (redirects <= 0) return resolve({ status: 500, error: 'TOO_MANY_REDIRECTS', duration: 0 });
    const tStart = Date.now();
    const u = new URL(urlStr);
    const req = https.get(urlStr, { headers, timeout: TIMEOUT_MS }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        let nextUrl = res.headers.location;
        if (nextUrl.startsWith('/')) nextUrl = u.origin + nextUrl;
        return resolve(fetchUrl(nextUrl, headers, redirects - 1));
      }
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ status: res.statusCode, body: data, duration: Date.now() - tStart });
      });
    });
    req.on('timeout', () => {
      req.destroy();
      resolve({ status: 408, error: 'TIMEOUT', duration: TIMEOUT_MS });
    });
    req.on('error', (err) => {
      resolve({ status: 500, error: err.message, duration: Date.now() - tStart });
    });
  });
}

function parseItem(itemStr) {
  const clean = itemStr.trim();
  if (clean.includes('/')) {
    const parts = clean.split('/');
    if (parts.length === 3) {
      return { type: 'tv', path: `tv/${clean}`, embedPath: `f/embed/tv/${clean}`, id: parts[0], season: parts[1], ep: parts[2] };
    }
  }
  return { type: 'movie', path: `movie/${clean}`, embedPath: `f/embed/movie/${clean}`, id: clean };
}

async function run() {
  console.log('======================================================');
  console.log('   YEFLIX — UNLIMPLAY DIAGNÓSTICO Y DISPONIBILIDAD     ');
  console.log('======================================================');
  
  if (API_KEY) {
    console.log(`[*] Modo: API Oficial (Clave: ulp_***${API_KEY.slice(-4)})`);
  } else {
    console.log('[*] Modo: EXTRACCIÓN DIRECTA PÚBLICA (Sin clave API)');
    console.log('    Desbloqueando fuentes mediante emulación de iframe legítimo.\n');
  }

  let itemsToTest = [];
  if (INPUT_FILE && fs.existsSync(INPUT_FILE)) {
    itemsToTest = JSON.parse(fs.readFileSync(INPUT_FILE, 'utf8'));
  } else {
    itemsToTest = IDS_RAW.split(',').map(s => s.trim()).filter(Boolean);
  }

  console.log(`[*] Títulos a consultar: ${itemsToTest.length}`);
  console.log(`[*] Concurrencia máxima: ${CONCURRENCY}\n`);

  const results = [];
  const stats = {
    totalChecked: 0,
    withSources: 0,
    withoutSources: 0,
    totalSources: 0,
    totalHls: 0,
    totalNonHls: 0,
    globalServers: {},
    globalLangs: {},
    errors: 0,
    durations: []
  };

  for (let i = 0; i < itemsToTest.length; i += CONCURRENCY) {
    const batch = itemsToTest.slice(i, i + CONCURRENCY);
    const promises = batch.map(async (rawItem) => {
      const parsed = parseItem(rawItem);
      
      if (cache[parsed.path] && cache[parsed.path].timestamp > Date.now() - 3600000) {
        console.log(`[CACHE] ${parsed.path} (de caché local)`);
        return cache[parsed.path].result;
      }

      let res;
      let sources = [];
      let itemResult = {
        item: rawItem,
        path: parsed.path,
        type: parsed.type,
        status: 0,
        durationMs: 0,
        hasSources: false,
        sourcesCount: 0,
        hlsCount: 0,
        nonHlsCount: 0,
        servers: {},
        languages: {},
        error: null
      };

      if (API_KEY) {
        // Modo API oficial
        res = await fetchUrl(`${ULP_BASE}/api/v1/${parsed.path}`, {
          'User-Agent': EMBED_HEADERS['User-Agent'],
          'Accept': 'application/json',
          'X-API-Key': API_KEY
        });
        itemResult.status = res.status;
        itemResult.durationMs = res.duration;
        stats.durations.push(res.duration);

        if (res.status === 200) {
          try {
            const json = JSON.parse(res.body);
            sources = json.sources || [];
          } catch (_) {}
        } else {
          itemResult.error = `HTTP_${res.status}`;
        }
      } else {
        // Modo directo público (Embed scraping)
        res = await fetchUrl(`${ULP_BASE}/${parsed.embedPath}`, EMBED_HEADERS);
        itemResult.status = res.status;
        itemResult.durationMs = res.duration;
        stats.durations.push(res.duration);

        if (res.status === 200) {
          const m = res.body.match(/const\s+EMBEDS\s*=\s*(\{[\s\S]*?\});/);
          if (m) {
            try {
              const data = JSON.parse(m[1]);
              for (const lang of Object.keys(data)) {
                for (const sName of Object.keys(data[lang])) {
                  const u = data[lang][sName];
                  const isHls = /\.m3u8/i.test(u) || /direct|hlswish/i.test(sName);
                  sources.push({ server: sName, lang, type: isHls ? 'hls' : 'mp4', url: u });
                }
              }
            } catch (_) {}
          }
        } else {
          itemResult.error = `HTTP_${res.status}`;
        }
      }

      // Analizar fuentes obtenidas
      for (const s of sources) {
        const isHls = s.type === 'hls' || /\.m3u8/i.test(s.url || '');
        if (isHls) itemResult.hlsCount++; else itemResult.nonHlsCount++;
        itemResult.servers[s.server] = (itemResult.servers[s.server] || 0) + 1;
        itemResult.languages[s.lang] = (itemResult.languages[s.lang] || 0) + 1;
      }

      itemResult.sourcesCount = sources.length;
      itemResult.hasSources = sources.length > 0;

      if (itemResult.hasSources) {
        console.log(`[OK 200] ${parsed.path} -> Fuentes: ${sources.length} (HLS: ${itemResult.hlsCount}) en ${res.duration}ms`);
      } else {
        console.log(`[VACÍO / ERR] ${parsed.path} -> ${itemResult.error || '0 fuentes'}`);
      }

      cache[parsed.path] = { timestamp: Date.now(), result: itemResult };
      return itemResult;
    });

    const batchResults = await Promise.all(promises);
    results.push(...batchResults);
    await new Promise(r => setTimeout(r, 200));
  }

  saveCache();

  for (const r of results) {
    stats.totalChecked++;
    if (r.hasSources) {
      stats.withSources++;
      stats.totalSources += r.sourcesCount;
      stats.totalHls += r.hlsCount;
      stats.totalNonHls += r.nonHlsCount;
      for (const [srv, c] of Object.entries(r.servers)) stats.globalServers[srv] = (stats.globalServers[srv] || 0) + c;
      for (const [lng, c] of Object.entries(r.languages)) stats.globalLangs[lng] = (stats.globalLangs[lng] || 0) + c;
    } else {
      stats.withoutSources++;
    }
    if (r.error) stats.errors++;
  }

  const avgDuration = stats.durations.length 
    ? Math.round(stats.durations.reduce((a, b) => a + b, 0) / stats.durations.length) 
    : 0;

  const finalReport = {
    timestamp: new Date().toISOString(),
    mode: API_KEY ? 'API_KEY' : 'PUBLIC_DIRECT',
    summary: {
      totalTitles: stats.totalChecked,
      titlesWithSources: stats.withSources,
      titlesWithoutSources: stats.withoutSources,
      totalSourcesFound: stats.totalSources,
      hlsSourcesFound: stats.totalHls,
      nonHlsSourcesFound: stats.totalNonHls,
      avgResponseTimeMs: avgDuration,
      totalErrors: stats.errors,
      serversFound: stats.globalServers,
      languagesFound: stats.globalLangs
    },
    details: results
  };

  fs.writeFileSync(OUT_JSON, JSON.stringify(finalReport, null, 2), 'utf8');

  let csvContent = 'Item,Tipo,Status,DuracionMs,TieneFuentes,TotalFuentes,FuentesHLS,FuentesNoHLS,Servidores,Idiomas,Error\n';
  for (const r of results) {
    const srvStr = Object.entries(r.servers).map(([k,v]) => `${k}:${v}`).join('|');
    const lngStr = Object.entries(r.languages).map(([k,v]) => `${k}:${v}`).join('|');
    csvContent += `"${r.item}","${r.type}",${r.status},${r.durationMs},${r.hasSources},${r.sourcesCount},${r.hlsCount},${r.nonHlsCount},"${srvStr}","${lngStr}","${r.error || ''}"\n`;
  }
  fs.writeFileSync(OUT_CSV, csvContent, 'utf8');

  console.log('\n======================================================');
  console.log('                 RESUMEN DEL DIAGNÓSTICO               ');
  console.log('======================================================');
  console.log(`- Modo de consulta:         ${API_KEY ? 'API Oficial' : 'DIRECTO PÚBLICO (Sin clave)'}`);
  console.log(`- Títulos analizados:       ${stats.totalChecked}`);
  console.log(`- Con fuentes disponibles:  ${stats.withSources}`);
  console.log(`- Sin fuentes:              ${stats.withoutSources}`);
  console.log(`- Total de fuentes:         ${stats.totalSources}`);
  console.log(`- Fuentes HLS:              ${stats.totalHls}`);
  console.log(`- Fuentes no HLS:           ${stats.totalNonHls}`);
  console.log(`- Tiempo promedio respuesta:${avgDuration} ms`);
  console.log(`- Servidores detectados:    ${Object.keys(stats.globalServers).join(', ')}`);
  console.log(`- Idiomas detectados:       ${Object.keys(stats.globalLangs).join(', ')}`);
  console.log(`- Archivos generados:       ${OUT_JSON}, ${OUT_CSV}`);
  console.log('======================================================\n');
}

run();
