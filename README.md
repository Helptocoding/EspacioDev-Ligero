# EspacioDev Ligero

Analizador local de carpetas regenerables de desarrollo para Windows (PowerShell + WinForms).
100% local, sin internet, nunca borra sin selección explícita. Todo va a la Papelera (reversible).

## Uso

1. Doble-clic `Abrir-EspacioDev.cmd` (o `powershell -ExecutionPolicy Bypass -File EspacioDev-Ligero.ps1`).
2. Elige carpeta raíz (proyectos, `Documentos`, `Descargas`). Evita analizar `C:\` entero.
3. Pulsa **Analizar espacio**.
4. Revisa columna Confianza (`Muy seguro` = auto-marcado, `Revisar` = manual).
5. **Enviar seleccionados a la Papelera**.

Restaura desde Papelera de Windows mientras no la vacíes.

## Protecciones

- Excluye reparse points / symlinks, `C:\Windows`, `Program Files`, `ProgramData`.
- `node_modules` solo es `Muy seguro` con `package.json` + lockfile (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`).
- Valida que la ruta siga dentro de la raíz escaneada antes de mover a Papelera.
- Cancelable, sin borrado silencioso.

## Qué detecta

`node_modules`, `.pnpm-store`, `.yarn`, `.next`, `dist`, `build`, `coverage`, `.cache`, `.turbo`, `.vite`, `.venv`, `venv`, `__pycache__`, `.pytest_cache`, `.gradle`, `target`.

Ver `PROPUESTA-Roadmap-EspacioDev.md` para backlog Fase 1/2/3 y Top-3 implementable.

## Requisitos

- Windows 10/11 + PowerShell 5.1 (incluido).
- Sin dependencias, sin admin.

## Estructura

```text
EspacioDev-Ligero.ps1      # app WinForms
Abrir-EspacioDev.cmd       # launcher Bypass local
LEEME-EspacioDev.md        # doc original en español
PROPUESTA-Roadmap-EspacioDev.md  # análisis PM + roadmap
```

## Límites v1

- No toca PostgreSQL, volúmenes Docker ni backups (solo futuro inventario lectura).
- No borra `.env`, código ni documentos.
- Unidad completa puede tardar; usa carpetas concretas.
