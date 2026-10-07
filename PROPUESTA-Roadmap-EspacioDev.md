# EspacioDev-Ligero — Análisis PM + Tech Lead

## 1. Análisis del script actual (366 líneas) + `LEEME`

**Lo que está bien:** 100% local, `SendToRecycleBin`, `Test-ProtectedPath` + `Test-SafeChildPath`, `ReparsePoint` excluido, no entra en candidatos anidados, `node_modules` exige `package.json+lock`, cancelación.

**Gaps / riesgos / fricción UX detectados en código:**

1. **UI bloqueante:** `$scan.add_Click` corre `Find-CleanupCandidates` + `Get-FolderSize` en hilo UI. Solo `DoEvents()`. En `C:\Users\...` con 50k carpetas se congela.
2. **Doble coste:** `Find` enumera árbol y por cada candidato `Get-FolderSize` re-recorre todo. Filtro `MinimumMB` se aplica *después* de pesar. `__pycache__` de 2 MB cuesta lo mismo que `node_modules` de 2 GB.
3. **Bug cancelación:** `Get-FolderSize` retorna `-1`, `Find` hace `break` solo del `foreach`, no del `while($pending)`. Sigue escaneando.
4. **Cobertura Windows incompleta:** falta stack .NET (`bin,obj,.vs,TestResults,NuGet`), moderno JS (`.nuxt,.parcel-cache,.svelte-kit,.angular`), Python (`.tox,.mypy_cache,.ruff_cache`), Rust (`target` sin verificar `Cargo.toml`), Java (sin `pom.xml/gradle` check), `.git` se escanea inútilmente.
5. **`venv` débil:** `venv=Revisar` solo por nombre. No verifica `pyvenv.cfg`. Falso positivo si usuario tiene carpeta `build/dist/target` con entrega manual.
6. **Protección corta:** solo `$env:WINDIR, ProgramFiles(x2), ProgramData`. Falta `C:\Windows\System32`, `WindowsApps`, raíz `C:\`, perfil de OneDrive/`AppData\Roaming` crítico, `.git` como tal. `Test-SafeChildPath` valida contra `$rootBox.Text` *actual*, si usuario cambia el TextBox tras escanear todo se marca `blocked` y confunde.
7. **Sin reversibilidad trazable:** borra y hace `$grid.DataSource=$null`. Sin log CSV, sin botón `Restaurar`, sin `re-analizar` diff.
8. **Sin acciones masivas:** sin `Todos/Ninguno/Invertir/Solo Muy seguro`, sin buscador, sin filtro por riesgo, sin color. Checkbox de 60px con `FullRowSelect` es propenso a error.
9. **Fallo típico no manejado:** `DeleteDirectory->RecycleBin` falla con paths >260 chars y `node_modules` bloqueado por VSCode/Code Helper. Muestra `MessageBox` por cada fallo, sin reintento ni `Abrir ubicación`.
10. **Sin memoria:** no guarda última raíz, favoritos ni exclusiones. Cada vez re-escribir ruta.

## 2. Backlog 12 features ordenado por Impacto/Esfuerzo

| # | Problema | Propuesta | Cómo (técnico) | Esfuerzo | Riesgo |
|---|---|---|---|---|---|
| 1 | Selección lenta y errores: todo manual, sin ver qué es peligroso | **Semáforo + selección masiva + buscador** | Modificar `$grid`: `CellFormatting` colorea `Muy seguro=verde/Revisar=ámbar`; añadir `CheckBox Todos`, `Solo Muy seguro`, `Invertir`, `TextBox Filtrar`. Función `Update-GridFilter()` filtra `BindingList` sin re-escanear. `Seleccionar` solo editable. | **S** | Bajo. Mitigar: `CommitEdit` ya existe; probar con 2000 filas. |
| 2 | Falsos positivos `venv/build/dist/target/bin/obj` | **Reglas inteligentes por ecosistema** | Ampliar `$KnownFolders` con `bin,obj,.vs,TestResults,.nuxt,.parcel-cache,.angular,.svelte-kit,.tox,.ruff_cache,.mypy_cache,.expo,.dart_tool`; nueva `Get-CandidateRule` verifica: `venv→pyvenv.cfg`, `bin/obj→*.csproj/*.sln` padre, `target→Cargo.toml/pom.xml`, `dist→package.json scripts.build`. Si no hay prueba → forzar `Revisar+Seleccionar=$false`. | **S** | Bajo. Mitigar: nunca auto-elevar a `Muy seguro`, solo degradar. |
| 3 | Usuario puede meter raíz peligrosa o perder lista por cambiar TextBox | **Protecciones + exclusiones persistentes** | Ampliar `Test-ProtectedPath`: bloquear raíz drive `^[A-Z]:\\?$` salvo confirm doble, `WindowsApps`, `System Volume Information`, `$HOME\AppData`, `.git` como candidato. Guardar `exclusiones.txt` en `%LocalAppData%\EspacioDev\`. Añadir `ListBox Excluidas + Botón Excluir ruta`. `Find` hace `if($excluidos -contains $dir){continue}`. Congelar `$script:ScanRoot` en Click Analizar y usar ese en `clean`, no `$rootBox.Text`. | **S** | Bajo. Mitigar: lista editable, nunca silently excluir `node_modules` real. |
| 4 | No hay evidencia de qué se envió a Papelera | **Log + Re-analizar** | Nueva `Write-CleanupLog($items)`: CSV `fecha,ruta,bytes,categoria` en `%LocalAppData%\EspacioDev\limpiezas.csv`. Botón `Ver historial` abre CSV. Tras limpiar no vaciar grid: marcar filas `Eliminado` y ofrecer `Re-analizar`. | **S** | Bajo. Mitigar: solo escritura local, sin datos personales fuera de ruta. |
| 5 | Paths largos / archivos bloqueados rompen limpieza con N popups | **Manejo `LongPath` + reintento** | Antes de `DeleteDirectory`: `if($ruta.Length -gt 240){advertir}`; usar prefijo `\\?\` solo para `Get-FolderSize`. En `catch`: acumular en `$fallos` y mostrar 1 resumen con `Abrir ubicación / Reintentar / Omitir`. Detectar `IOException sharing violation` → mensaje `Cierra VSCode/npm/node y reintenta`. | **S** | Bajo. Mitigar: no borrar parcial con `Remove-Item`, seguir solo con `SendToRecycleBin`. |
| 6 | Escaneo pesa hasta carpetas diminutas | **Early-exit + skip `.git`** | Modificar `Get-FolderSize(Path, MinBytes)`: aborta si imposible superar mínimo. `Find`: `if($name -eq '.git' -or $name -eq '.svn'){continue}` sin pushear. Añadir `MinimumMB` también filtra `UltimaModificacion < X` opcional. | **S** | Bajo. Mitigar: mantener `ReparsePoint` check. |
| 7 | No sabe qué proyecto es ni cuánto pesa en total | **Agrupar por proyecto + Exportar** | Nueva `Get-ProjectRoot($dir)`: sube hasta `package.json/pyproject.toml/*.sln/Cargo.toml/pom.xml/.git`. Vista `Agrupado por proyecto` + `Exportar CSV/Copiar ruta` (`Clipboard::SetText`). Botón `Abrir ubicación` abre todas seleccionadas, no solo `[0]`. | **M** | Medio-bajo. Mitigar: agrupación solo visual, no cambia borrado. |
| 8 | Antigüedad no se usa para decidir | **Columna `Hace X meses` + orden** | Añadir prop `DiasSinUso=(Now-LastWrite).Days`; regla: si `<30 días` → degradar a `Revisar` aunque sea caché. `Sort` default por `Bytes desc`, segundo por `DiasSinUso`. Tooltip `Motivo` con comando regeneración (`npm ci`, `dotnet restore`). | **M** | Bajo. Mitigar: es heurística informativa, no auto-selección agresiva. |
| 9 | UI se congela minutos, sin ETA, Cancel tarda | **Escaneo async con `Runspace` + progreso real** | Crear `Start-ScanJob`: `PowerShell.Create().AddScript({Find-CleanupCandidates})` en `Runspace` + `Timer` 300ms que lee `ConcurrentQueue` progreso y actualiza `$status+ProgressBar`. `Cancel` pone `CancelScan=$true` + `Stop()`. `Get-FolderSize` chequea cancel cada 500 archivos. | **M** | Medio: cross-thread. Mitigar: nunca tocar `$grid` desde job, solo vía `Invoke`. Mantener modo síncrono como fallback si falla runspace. |
| 10 | Olvida última carpeta, repite trabajo | **Recientes + Favoritos** | `config.json` en `LocalAppData`: `{lastRoot, favorites[], minimumMB}`. `Load-Config/Save-Config`. `ComboBox` con recientes + botón `★`. | **S** | Muy bajo. Mitigar: validar `Test-Path` al cargar. |
| 11 | No distingue Docker/DB/backups, usuario los borra a mano con riesgo | **Inventario solo-lectura (sin borrar)** | Nuevo `Tab Inventario`: `Find-HeavyFolders` lista `*.vhdx, DockerDesktop, pgdata, dump*.sql, *.bak` con tamaño y `Abrir` + enlace `Cómo exportar`. Botón deshabilitado para Papelera con texto `Requiere exportación manual`. | **M** | Medio: riesgo de borrar DB única. Mitigar: `IsDeletable=$false` forzado, doble confirmación si se habilita futuro. |
| 12 | Sin programar ni comparar en el tiempo | **Snapshot + diff semanal** | `Save-Snapshot()` guarda `snapshot-fecha.csv`. `Compare-Snapshot` muestra `Nuevo/Crecido/Desaparecido`. Opcional `Task Scheduler` `EspacioDev semanal solo-escaneo`. | **L** | Medio. Mitigar: snapshots locales, sin auto-limpieza programada jamás. |

## 3. Roadmap

**Fase 1 — Quick wins (1 semana, solo `.ps1`, sin hilos):** #1, #2, #3, #4, #5
> Máximo valor seguridad/usabilidad con riesgo ~0. No toca concurrencia.

**Fase 2 — Velocidad + contexto (2 semanas):** #6, #8, #7, #10, #9
> Primero optimizaciones síncronas (#6), luego async (#9). Medir con `Measure-Command` en carpeta 20 GB antes/después.

**Fase 3 — Alcance controlado:** #11, #12
> Solo inventario y reportes. Nunca auto-borrar DB/Docker. Requiere UX de doble confirmación aparte.

## 4. Top 3 — Plan implementable paso a paso

### TOP 1 — #3 Protecciones + exclusiones + reglas inteligentes (Seguridad primero)

**Archivos:** `EspacioDev-Ligero.ps1` (único), crea `%LocalAppData%\EspacioDev\exclusiones.txt` y `config.json`.

**Pasos:**

1. Añadir al inicio:

```powershell
$script:ScanRoot = ""
$script:AppDir = Join-Path $env:LOCALAPPDATA "EspacioDev"
$script:Excludes = @()
function Load-Excludes { if(Test-Path "$script:AppDir\exclusiones.txt"){ $script:Excludes = Get-Content "$script:AppDir\exclusiones.txt" } }
function Test-ProtectedPath { # extender:
  # 1) roots actuales + WindowsApps, System Volume Information, $env:USERPROFILE\AppData
  # 2) if($Path -match '^[A-Z]:\\?$'){return $true}  # raíz drive nunca candidato
  # 3) if($Excludes -contains $Path){return $true}
}
```

2. Extender `$KnownFolders` con `bin,obj,.vs,TestResults,.nuxt,.tox` y reescribir `Get-CandidateRule`:

```powershell
function Get-CandidateRule {
 param($FolderName,$FolderPath)
 $r = $script:KnownFolders[$FolderName]; $risk=$r.Risk; $reason=$r.Reason
 $parent = [IO.Directory]::GetParent($FolderPath).FullName
 switch($FolderName){
  {$_ -in 'venv','.venv'}{ if(-not (Test-Path (Join-Path $FolderPath "pyvenv.cfg"))){$risk='Revisar'; $reason+=' Sin pyvenv.cfg.'} }
  {$_ -in 'bin','obj'}{ if(-not (Get-ChildItem $parent -Filter *.csproj -ErrorAction SilentlyContinue)){ $risk='Revisar' } }
  {$_ -eq 'target'}{ if(-not ((Test-Path "$parent\Cargo.toml") -or (Test-Path "$parent\pom.xml"))){$risk='Revisar'} }
 }
 return @{Category=$r.Category; Risk=$risk; Reason=$reason}
}
```

3. UI: añadir `ListBox lstExcl + Btn Excluir seleccionada / Quitar`. En `$scan.Click` fijar `$script:ScanRoot=$chosenRoot` y en `$clean.Click` validar `Test-SafeChildPath -Path $item.Ruta -Root $script:ScanRoot`.
4. En `Find-CleanupCandidates`: `if($name -eq '.git'){continue}` y `if(Test-ProtectedPath $dir){continue}` antes de `scanned++`.

**Pruebas manuales:**
- Raíz `C:\` → debe pedir doble confirm o bloquear; `C:\Windows\System32` nunca aparece.
- Crear `proj\venv\` sin `pyvenv.cfg` → aparece `Revisar` y desmarcado.
- Excluir una ruta, cerrar/reabrir, re-escanear → sigue excluida.
- Cambiar `rootBox.Text` tras escanear e intentar limpiar → bloquea con mensaje, no borra.

### TOP 2 — #9 + #6 Escaneo rápido y no bloqueante (Velocidad)

**Archivos:** mismo `.ps1`. Sin nuevos permisos.

**Pasos:**

1. Optimizar `Get-FolderSize`:

```powershell
function Get-FolderSize {
 param([string]$Path,[int64]$MinBytes=0)
 [int64]$total=0; $files=0
 $pending=[Collections.Generic.Stack[string]]::new(); $pending.Push($Path)
 while($pending.Count){
  if($script:CancelScan){return -1}
  $cur=$pending.Pop()
  try{
   foreach($f in [IO.Directory]::EnumerateFiles($cur)){ try{$total+=([IO.FileInfo]$f).Length; $files++; if($files%2000 -eq 0){[Windows.Forms.Application]::DoEvents()}}catch{} }
   foreach($d in [IO.Directory]::EnumerateDirectories($cur)){
    if(([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint)-ne 0){continue}
    $n=[IO.Path]::GetFileName($d); if($n -eq '.git'){continue}
    $pending.Push($d)
   }
  }catch{}
 }
 return $total
}
```

2. Async mínimo viable sin re-arquitectura: mover `Find-CleanupCandidates` a `Runspace`:

```powershell
# en $scan.Click:
$ps=[PowerShell]::Create().AddScript(${function:Find-CleanupCandidates}).AddArgument($script:ScanRoot)
$handle=$ps.BeginInvoke()
$timer=New-Object Windows.Forms.Timer; $timer.Interval=300
$timer.add_Tick({ $status.Text="... $elapsed s ..."; if($handle.IsCompleted){$timer.Stop(); $result=$ps.EndInvoke($handle); Update-Grid $result } })
$cancel.Click -> { $script:CancelScan=$true; $ps.Stop() }
```

Alternativa Fase 2a si runspaces dan fricción: mantener síncrono + `ProgressBar` + `DoEvents` cada 100 carpetas (ya existe, añadir `ProgressBar` control).
3. Añadir `ProgressBar pBar` bajo `status`, `Minimum/Maximum/Style=Marquee` cuando total desconocido.

**Pruebas manuales:**
- Carpeta proyectos 15 GB: UI responde, `Cancelar` tarda <2s, status muestra `X carpetas / Y candidatas`.
- `Measure-Command { Find-CleanupCandidates -Root ... }` antes/después: objetivo -30% por skip `.git` + no pesar `<MinimumMB` innecesario.
- Escaneo dos veces seguidas mismo resultado ordenado.

### TOP 3 — #1 + #4 Acciones masivas reversibles (Reversibilidad)

**Archivos:** mismo `.ps1` + `%LocalAppData%\EspacioDev\limpiezas.csv`.

**Pasos:**

1. UI grid: `CellFormatting`:

```powershell
$grid.add_CellFormatting({ param($s,$e)
 if($grid.Columns[$e.ColumnIndex].Name -eq 'Riesgo'){
  if($e.Value -eq 'Muy seguro'){$e.CellStyle.BackColor=[Drawing.Color]::FromArgb(220,252,231)}
  else{$e.CellStyle.BackColor=[Drawing.Color]::FromArgb(254,249,195)}
 }})
```

Botones: `Todos | Ninguno | Solo Muy seguro | Invertir` + `txtFiltro` con `TextChanged -> Update-GridFilter` (filtra `DataSource` en memoria por `Ruta/Categoria`).
2. Log:

```powershell
function Write-CleanupLog($items){ $dir="$env:LOCALAPPDATA\EspacioDev"; mkdir $dir -ea 0|Out-Null
 $items|Select @{n='Fecha';e={Get-Date}},Ruta,Bytes,Categoria|Export-Csv "$dir\limpiezas.csv" -Append -Encoding UTF8 }
# en $clean.Click: acumular $fallos en vez de MessageBox por item; al final 1 resumen + Write-CleanupLog $exitosos
```

3. Tras limpiar: no `DataSource=$null`, sino `Re-analizar` automático opcional + `status="X a Papelera. Deshacer: abre Papelera (shell:RecycleBinFolder)"` + botón `Abrir Papelera`.

**Pruebas manuales:**
- 50 filas: `Solo Muy seguro` marca solo verdes, `summary` recalcula.
- Filtro `node` muestra solo `node_modules`, limpiar respeta filtro (solo marcados).
- Limpiar 3 carpetas → `limpiezas.csv` tiene 3 líneas, Papelera las contiene, `Restaurar` de Windows las devuelve.
- Simular bloqueo (abrir archivo dentro de `node_modules` en VSCode) → 1 único diálogo resumen, no N popups.

> Ninguna feature requiere internet, admin ni otro lenguaje. Todo con `System.Windows.Forms`, `Microsoft.VisualBasic.FileIO`, `IO.Directory` ya usados.
