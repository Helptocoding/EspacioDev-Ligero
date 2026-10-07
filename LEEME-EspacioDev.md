# EspacioDev Ligero

Aplicación local para revisar carpetas regenerables de desarrollo que ocupan espacio. No necesita instalación, no usa internet y no borra nada sin confirmación.

## Uso

1. Abre `Abrir-EspacioDev.cmd`.
2. Elige una carpeta: primero prueba con tu carpeta de proyectos, `Documentos` o `Descargas`.
3. Pulsa **Analizar espacio**.
4. Revisa las carpetas encontradas y las marcadas para limpiar.
5. Pulsa **Enviar seleccionados a la Papelera**.

Las carpetas se mueven a la Papelera de reciclaje de Windows; puedes restaurarlas desde allí mientras no la vacíes.

## Protecciones incluidas

- El escaneo excluye enlaces del sistema y rutas de Windows, Program Files y ProgramData.
- Puedes cancelar el análisis; conserva lo que ya haya encontrado.
- Una carpeta `node_modules` solo se marca como **Muy seguro** cuando su proyecto tiene `package.json` y un lockfile (`package-lock.json`, `pnpm-lock.yaml` o `yarn.lock`).
- Si no se pudo enviar ninguna carpeta a la Papelera, la lista se mantiene visible y el programa explica el bloqueo. No simula una limpieza exitosa.

## Qué detecta

`node_modules`, `.venv`, `venv`, `__pycache__`, `.next`, `dist`, `build`, `coverage`, `.cache`, `.turbo`, `.vite`, `.pytest_cache`, `.gradle`, `target`, cachés de pnpm y algunos directorios de Yarn.

Las sugerencias **Muy seguro** corresponden a cachés, dependencias o salidas que normalmente se regeneran. Las sugerencias **Revisar** no se marcan automáticamente: pueden contener una entrega o un entorno que quieras conservar.

## Límites deliberados de esta versión

- No analiza ni elimina bases PostgreSQL, volúmenes de Docker ni backups automáticamente: esos datos pueden ser únicos. Un siguiente módulo puede inventariarlos y ofrecer exportación antes de limpiar.
- No borra archivos de código, documentos, `.env` ni bases de datos.
- El análisis puede tardar en una unidad completa; conviene elegir carpetas concretas.
