# Read my Script

Read my Script convierte el PDF de un guion en un audiolibro. Un narrador lee la acción y cada papel habla con su propia voz. Las voces vienen de **VoiceStudio**, que funciona en el mismo Mac.

## Tu guion se queda en este Mac

- El guion solo pasa a VoiceStudio en este ordenador (dirección 127.0.0.1), nunca a Internet.
- Read my Script solo se conecta a GitHub: para preguntar si hay una versión nueva de sí mismo y, solo si haces clic en **Instalar VoiceStudio**, para descargar VoiceStudio. Ninguna de las dos cosas contiene nada de tus guiones.
- El archivo de registro enumera lo que hizo la app, sin ningún texto de tus guiones.
- Read my Script avisa cuando las estadísticas de uso o la sincronización en la nube de VoiceStudio están activadas. Desactívalas en VoiceStudio antes de leer un guion.

## Antes de empezar

- Read my Script solo funciona junto con **VoiceStudio**. Mientras falte, la ventana muestra una breve configuración: **Instalar VoiceStudio** descarga la versión actual de la página oficial de VoiceStudio en GitHub y la pone en la carpeta Aplicaciones, solo si Apple confirma que está firmada por su desarrollador y sin cambios. Con **Página de descarga** puedes instalarla tú mismo.
- En su primer inicio, VoiceStudio descarga su modelo de voz (unos 2,4 GB) y muestra su licencia, que solo permite el uso no comercial. Léela y acéptala tú mismo: Read my Script no lo hace por ti.
- Después, Read my Script desactiva en VoiceStudio las estadísticas de uso, la sincronización en la nube y el uso compartido en red.
- El punto de arriba a la derecha se vuelve verde cuando VoiceStudio está listo; si no, haz clic en **Abrir VoiceStudio**.
- Crea algunas voces en VoiceStudio, o crea voces nuevas desde Read my Script (consulta «Una voz nueva»).

## Abrir un guion

Arrastra el PDF de un guion a la ventana o usa **Archivo → Abrir PDF…** (⌘O). Read my Script reconoce encabezados de escena, acción, nombres de personajes, acotaciones entre paréntesis, diálogos y transiciones, en guiones de Final Draft, Fade In, Word y otros programas, en alemán e inglés. Los números de página y de escena, los encabezados y las marcas de agua se omiten.

- Todo lo que hay antes del primer encabezado de escena (portada, notas) no se lee. El reparto indica cuántos párrafos son.
- Los PDF de páginas escaneadas no contienen texto y todavía no se pueden leer.

## Reparto

La columna izquierda muestra el **Narrador** y todos los papeles, primero los que tienen más réplicas. Elige una voz para cada uno en su menú; ▶ reproduce una réplica del papel con esa voz.

- **Una voz por papel:** Read my Script nunca asigna por sí mismo una voz a dos papeles. Si hay más papeles que voces, los restantes muestran **Elegir voz**. Si eliges una voz que ya usa otro papel, la app pregunta antes: los oyentes solo distinguen los papeles por la voz.
- **No leer** deja fuera un papel a propósito.
- Mientras un papel no tenga voz, no se puede crear el audiolibro; así no se pierde ninguna réplica sin que lo sepas.

## Una voz nueva

**Nueva voz…**, al final de cada menú de voces, crea una voz en VoiceStudio a partir de unos pocos rasgos: género, edad, tono y susurro. **Escuchar** reproduce la primera réplica del papel; **Otra variante** da otra voz con los mismos rasgos. **Guardar voz** la guarda en VoiceStudio y se la asigna al papel.

## Revisar el texto

La columna derecha muestra el guion tal como se leerá. Con un clic derecho en un párrafo puedes hacer que **lo lea el narrador**, que **no se lea** o volver a **como se detectó**.

## Crear el audiolibro

Elige abajo el **idioma de las voces** (Automático, alemán o inglés), haz clic en **Crear audiolibro…** y elige dónde guardarlo. El resultado es un audiolibro `.m4b` con un capítulo por escena.

- Tarda mucho: unas siete veces la duración en un Mac con Apple Silicon; un guion de 90 minutos necesita unas diez horas. Déjalo trabajar durante la noche.
- **Pausa** detiene VoiceStudio; las escenas terminadas se conservan y **Reanudar** sigue donde se quedó. **Cancelar** descarta el audiolibro a medio hacer.

## Ajustes

**Read my Script → Ajustes…** (⌘,):

- **General:** aspecto claro u oscuro, idioma (la app se reinicia).
- **Actualizaciones:** versión, buscar actualizaciones, versiones de prueba. Un aviso en la parte superior de la ventana ofrece las versiones nuevas; la instalación reinicia la app.
- **Soporte:** una autoprueba con guiones de prueba inventados (no se envía nada), el archivo de registro y un café si te gusta la app.
- **Acerca de:** versión, licencia y código fuente.
