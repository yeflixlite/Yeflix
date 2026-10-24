# Yeflix

<div align="center">

<img width="180" src="./icons/logo.png" alt="Yeflix Logo"/>

# Yeflix

### Tu plataforma definitiva para ver anime, películas y series en español

Aplicación moderna, rápida y fluida para Android y escritorio, diseñada para disfrutar de tus contenidos favoritos sin publicidad intrusiva y con la máxima velocidad de carga.

<br>

[![Repository](https://img.shields.io/badge/Repository-Yeflix-red?style=for-the-badge&logo=github)](https://github.com/yeflixlite/Yeflix)
[![Release](https://img.shields.io/github/v/release/yeflixlite/Yeflix?style=for-the-badge&color=red)](https://github.com/yeflixlite/Yeflix/releases)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Linux-black?style=for-the-badge&logo=android)](https://github.com/yeflixlite/Yeflix/releases)
[![License](https://img.shields.io/badge/License-AGPL--3.0-blue?style=for-the-badge)](LICENSE)

</div>

---

## ✨ Características Principales

### 🎬 Reproductor Nativo de Alto Rendimiento (ExoPlayer / Media3)
* **Integración nativa en Android** con aceleración de hardware para transmisiones HLS (`.m3u8`), DASH y archivos directos MP4/MKV.
* **Cero pantallas negras y sin retrasos**: sincronización fluida entre video y controles táctiles interactivos en pantalla.
* **Gestos y controles avanzados**: ajuste de brillo, volumen, selector de pistas de audio, cambio dinámico de servidores y pantalla completa inmersiva.

### ⚡ Carga Ultrarrápida de Servidores
* Tiempos de inicio de video reducidos de más de 15 segundos a **1 - 3 segundos** con resolución directa de stream.
* Servidores compatibles optimizados: **StreamWish**, **VidHide**, **Voe**, **Filelions**, entre otros.
* Conmutación inteligente de servidores: si una fuente falla o expira, cambia automáticamente a la siguiente opción funcional sin interrupciones.

### 📥 Descargas Offline Inteligentes y Aceleradas
* **Ahorro masivo de almacenamiento (hasta 55% menos peso)**:
  * **Económica (480p)**: ~300 a 450 MB por película (ahorro máximo de espacio).
  * **Estándar (720p - Recomendada)**: ~500 a 700 MB por película con nitidez HD cristalina.
  * **Máxima (1080p)**: Máxima fidelidad de imagen para pantallas de alta resolución.
* **Descarga Acelerada en Paralelo**: Pool concurrente de 3 conexiones simultáneas para descargar segmentos a máxima velocidad.
* **Reanudación Automática**: Reanuda descargas interrumpidas o pausadas al instante sin perder los datos ya descargados.
* **100% Sin Conexión**: Disfruta tus películas y episodios descargados en cualquier lugar sin gastar datos ni requerir Wi-Fi.
* **Gestor de Espacio**: Elimina completamente los archivos descargados y libera memoria con un solo toque mediante un diálogo de confirmación claro.

### 🎨 Diseño Moderno y Personalizable
* Interfaz con tema oscuro premium (OLED Black / Rojo Yeflix).
* Historial de reproducción, lista de favoritos, seguimiento y notificaciones.
* Catálogo dinámico con filtros por género, año y popularidad.

---

## 📦 Repositorio Oficial de Extensiones

Para acceder al catálogo de películas, series y anime, agrega el repositorio oficial de extensiones de Yeflix:

1. Abre **Yeflix**.
2. Dirígete a **Ajustes** → **Extensiones** → **Repositorios**.
3. Presiona el botón **+** (Agregar).
4. Pega la URL del repositorio oficial:
   ```txt
   https://raw.githubusercontent.com/yeflixlite/Anime/main
   ```
5. Presiona **Recargar** o **Aceptar**.
6. ¡Listo! Ya puedes explorar e instalar extensiones como *Pelis Premium*, *LatAnime*, entre otras.

---

## 📲 Instalación

1. Dirígete a la sección de [Releases de Yeflix](https://github.com/yeflixlite/Yeflix/releases).
2. Descarga el archivo APK más reciente en tu dispositivo Android.
3. Abre el archivo descargado y autoriza la instalación si el sistema te lo solicita.
4. Abre la aplicación y configura el repositorio de extensiones para comenzar a ver contenido.

---

## 🛠️ Tecnologías y Librerías

* **Framework**: [Flutter](https://flutter.dev) (Dart)
* **Reproductor Android**: [AndroidX Media3 ExoPlayer](https://developer.android.com/media/media3/exoplayer)
* **Gestión de Estado**: [GetX](https://pub.dev/packages/get)
* **Almacenamiento Local**: [Hive](https://pub.dev/packages/hive) & [Isar Database](https://isar.dev)
* **Descargas y Red**: [Dio](https://pub.dev/packages/dio) con arquitectura de streaming en paralelo

---

## 🤝 Créditos y Agradecimientos

Este proyecto fue desarrollado tomando como base inicial el proyecto de código abierto **JiruHub** / **Miru App**, al cual se le han implementado profundas reestructuraciones de arquitectura, integración nativa de ExoPlayer en Android, nuevo gestor de descargas concurrentes con compresión inteligente, mejoras de servidores y diseño personalizado para la comunidad de **Yeflix**.

Agradecimientos especiales a todos los desarrolladores de la comunidad open source que hacen posible estas tecnologías.

---

## 📜 Licencia

Yeflix se distribuye bajo los términos de la licencia **GNU Affero General Public License v3.0 (AGPL-3.0)**. Consulta el archivo [LICENSE](LICENSE) para más información.

<div align="center">

**Yeflix — Tu entretenimiento en tus manos**

</div>
