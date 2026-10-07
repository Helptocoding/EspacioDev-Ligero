# EspacioDev Ligero
# Analizador local de carpetas regenerables de desarrollo para Windows.
# No envía datos a Internet y nunca elimina nada sin selección explícita.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:KnownFolders = @{
    'node_modules' = @{ Category = 'Dependencias Node.js'; Risk = 'Muy seguro'; Reason = 'Se puede reconstruir desde package.json y el archivo lock del proyecto.' }
    '.pnpm-store' = @{ Category = 'Caché pnpm'; Risk = 'Muy seguro'; Reason = 'Caché de paquetes; pnpm la vuelve a descargar cuando sea necesaria.' }
    '.yarn'        = @{ Category = 'Caché Yarn'; Risk = 'Revisar'; Reason = 'Puede contener caché o versiones locales; revisa antes de limpiar.' }
    '.next'        = @{ Category = 'Build Next.js'; Risk = 'Muy seguro'; Reason = 'Salida de compilación; se regenera al ejecutar el proyecto.' }
    'dist'         = @{ Category = 'Build'; Risk = 'Revisar'; Reason = 'Suele ser salida de compilación, pero confirma que no sea una entrega manual.' }
    'build'        = @{ Category = 'Build'; Risk = 'Revisar'; Reason = 'Suele ser salida de compilación, pero confirma que no sea una entrega manual.' }
    'coverage'     = @{ Category = 'Cobertura de pruebas'; Risk = 'Muy seguro'; Reason = 'Reportes generados por pruebas; se pueden crear de nuevo.' }
    '.cache'       = @{ Category = 'Caché de herramientas'; Risk = 'Muy seguro'; Reason = 'Caché regenerable de una herramienta de desarrollo.' }
    '.turbo'       = @{ Category = 'Caché Turborepo'; Risk = 'Muy seguro'; Reason = 'Caché regenerable de compilaciones.' }
    '.vite'        = @{ Category = 'Caché Vite'; Risk = 'Muy seguro'; Reason = 'Caché regenerable de Vite.' }
    '.venv'        = @{ Category = 'Entorno virtual Python'; Risk = 'Muy seguro'; Reason = 'Se puede recrear con requirements.txt o pyproject.toml.' }
    'venv'         = @{ Category = 'Entorno virtual Python'; Risk = 'Revisar'; Reason = 'Normalmente regenerable; confirma que sea un entorno virtual.' }
    '__pycache__'  = @{ Category = 'Caché Python'; Risk = 'Muy seguro'; Reason = 'Bytecode regenerable de Python.' }
    '.pytest_cache'= @{ Category = 'Caché pytest'; Risk = 'Muy seguro'; Reason = 'Caché regenerable de pruebas Python.' }
    '.gradle'      = @{ Category = 'Caché Gradle'; Risk = 'Revisar'; Reason = 'Puede regenerarse, aunque la siguiente compilación será más lenta.' }
    'target'       = @{ Category = 'Salida Java/Rust'; Risk = 'Revisar'; Reason = 'Suele ser salida de compilación; revisa que no contenga artefactos que quieras entregar.' }
}
$script:CancelScan = $false
$script:ProtectedRoots = @($env:WINDIR, ${env:ProgramFiles}, ${env:ProgramFiles(x86)}, ${env:ProgramData}) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

function Get-FolderSize {
    param([Parameter(Mandatory)][string]$Path)
    [Int64]$total = 0
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($Path)
    while ($pending.Count -gt 0) {
        if ($script:CancelScan) { return -1 }
        $current = $pending.Pop()
        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($current)) {
                try { $total += ([System.IO.FileInfo]$file).Length } catch { }
            }
            foreach ($dir in [System.IO.Directory]::EnumerateDirectories($current)) {
                try {
                    $attributes = [System.IO.File]::GetAttributes($dir)
                    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) { $pending.Push($dir) }
                } catch { }
            }
        } catch { }
    }
    return $total
}

function Format-Size {
    param([Int64]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Find-CleanupCandidates {
    param([Parameter(Mandatory)][string]$Root, [int]$MinimumMB = 50, [scriptblock]$Progress)
    $found = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($Root)
    $minimumBytes = [Int64]$MinimumMB * 1MB
    $scanned = 0

    while ($pending.Count -gt 0) {
        if ($script:CancelScan) { break }
        $current = $pending.Pop()
        try {
            foreach ($dir in [System.IO.Directory]::EnumerateDirectories($current)) {
                try {
                    if ($script:CancelScan) { break }
                    $attributes = [System.IO.File]::GetAttributes($dir)
                    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    if (Test-ProtectedPath -Path $dir) { continue }
                    $scanned++
                    if ($Progress -and ($scanned % 100 -eq 0)) { & $Progress $scanned $found.Count }
                    $name = [System.IO.Path]::GetFileName($dir)
                    if ($script:KnownFolders.ContainsKey($name)) {
                        $bytes = Get-FolderSize -Path $dir
                        if ($bytes -lt 0) { break }
                        if ($bytes -ge $minimumBytes) {
                            $rule = Get-CandidateRule -FolderName $name -FolderPath $dir
                            $lastWrite = (Get-Item -LiteralPath $dir -Force).LastWriteTime
                            $found.Add([pscustomobject]@{
                                Seleccionar = $rule.Risk -eq 'Muy seguro'
                                Categoria = $rule.Category
                                Tamano = Format-Size $bytes
                                Bytes = $bytes
                                UltimaModificacion = $lastWrite
                                Riesgo = $rule.Risk
                                Motivo = $rule.Reason
                                Ruta = $dir
                            })
                        }
                        continue # Evita contar candidatos dentro de otro candidato.
                    }
                    $pending.Push($dir)
                } catch { }
            }
        } catch { }
    }
    if ($Progress) { & $Progress $scanned $found.Count }
    return [pscustomobject]@{ Candidates = @($found | Sort-Object Bytes -Descending); Scanned = $scanned; Cancelled = $script:CancelScan }
}

function Test-SafeChildPath {
    param([string]$Path, [string]$Root)
    try {
        $slash = [char]92
        $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd($slash)
        $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd($slash)
        return $fullPath.StartsWith($fullRoot + $slash, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Test-ProtectedPath {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($protectedRoot in $script:ProtectedRoots) {
        try {
            $slash = [char]92
            $left = [System.IO.Path]::GetFullPath($Path).TrimEnd($slash)
            $right = [System.IO.Path]::GetFullPath($protectedRoot).TrimEnd($slash)
            if ($left.Equals($right, [System.StringComparison]::OrdinalIgnoreCase) -or (Test-SafeChildPath -Path $Path -Root $protectedRoot)) { return $true }
        } catch { }
    }
    return $false
}

function Get-CandidateRule {
    param([string]$FolderName, [string]$FolderPath)
    $baseRule = $script:KnownFolders[$FolderName]
    $risk = $baseRule.Risk
    $reason = $baseRule.Reason
    if ($FolderName -eq 'node_modules') {
        $projectRoot = [System.IO.Directory]::GetParent($FolderPath).FullName
        $hasPackage = Test-Path -LiteralPath (Join-Path $projectRoot 'package.json') -PathType Leaf
        $lockFiles = @('package-lock.json', 'pnpm-lock.yaml', 'yarn.lock')
        $hasLock = @($lockFiles | Where-Object { Test-Path -LiteralPath (Join-Path $projectRoot $_) -PathType Leaf }).Count -gt 0
        if ($hasPackage -and $hasLock) { $reason = 'Proyecto Node.js valido: package.json y lockfile detectados; node_modules se puede reinstalar.' }
        else { $risk = 'Revisar'; $reason = 'No se encontro package.json y lockfile juntos; confirma que esta carpeta sea regenerable antes de limpiarla.' }
    }
    return @{ Category = $baseRule.Category; Risk = $risk; Reason = $reason }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'EspacioDev Ligero'
$form.Size = New-Object System.Drawing.Size(1180, 720)
$form.MinimumSize = New-Object System.Drawing.Size(900, 550)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'EspacioDev Ligero'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(18, 14)
$title.AutoSize = $true
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Encuentra dependencias, builds y cachés regenerables. Todo el análisis es local.'
$subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$subtitle.Location = New-Object System.Drawing.Point(20, 50)
$subtitle.AutoSize = $true
$form.Controls.Add($subtitle)

$rootLabel = New-Object System.Windows.Forms.Label
$rootLabel.Text = 'Carpeta a analizar:'
$rootLabel.Location = New-Object System.Drawing.Point(20, 87)
$rootLabel.AutoSize = $true
$form.Controls.Add($rootLabel)

$rootBox = New-Object System.Windows.Forms.TextBox
$rootBox.Location = New-Object System.Drawing.Point(125, 83)
$rootBox.Size = New-Object System.Drawing.Size(720, 26)
$rootBox.Text = [Environment]::GetFolderPath('MyDocuments')
$form.Controls.Add($rootBox)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'Elegir carpeta'
$browse.Location = New-Object System.Drawing.Point(856, 80)
$browse.Size = New-Object System.Drawing.Size(115, 30)
$form.Controls.Add($browse)

$minimumLabel = New-Object System.Windows.Forms.Label
$minimumLabel.Text = 'Tamaño mínimo (MB):'
$minimumLabel.Location = New-Object System.Drawing.Point(20, 126)
$minimumLabel.AutoSize = $true
$form.Controls.Add($minimumLabel)

$minimum = New-Object System.Windows.Forms.NumericUpDown
$minimum.Location = New-Object System.Drawing.Point(155, 122)
$minimum.Minimum = 1
$minimum.Maximum = 10240
$minimum.Value = 50
$minimum.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($minimum)

$scan = New-Object System.Windows.Forms.Button
$scan.Text = 'Analizar espacio'
$scan.Location = New-Object System.Drawing.Point(270, 120)
$scan.Size = New-Object System.Drawing.Size(130, 30)
$scan.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$scan.ForeColor = [System.Drawing.Color]::White
$scan.FlatStyle = 'Flat'
$form.Controls.Add($scan)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancelar'
$cancel.Location = New-Object System.Drawing.Point(408, 120)
$cancel.Size = New-Object System.Drawing.Size(80, 30)
$cancel.Enabled = $false
$form.Controls.Add($cancel)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Elige una carpeta de proyectos o Descargas y pulsa Analizar espacio.'
$status.Location = New-Object System.Drawing.Point(500, 126)
$status.AutoSize = $true
$form.Controls.Add($status)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(20, 166)
$grid.Size = New-Object System.Drawing.Size(1125, 455)
$grid.Anchor = 'Top,Bottom,Left,Right'
$grid.AutoGenerateColumns = $false
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $true
$grid.RowHeadersVisible = $false
$grid.AutoSizeRowsMode = 'DisplayedCells'
$grid.DefaultCellStyle.WrapMode = 'False'

$columns = @(
    @{ Name = 'Seleccionar'; Header = 'Limpiar'; Width = 60; Type = 'CheckBox' },
    @{ Name = 'Categoria'; Header = 'Categoría'; Width = 150; Type = 'TextBox' },
    @{ Name = 'Tamano'; Header = 'Tamaño'; Width = 90; Type = 'TextBox' },
    @{ Name = 'UltimaModificacion'; Header = 'Último cambio'; Width = 135; Type = 'TextBox' },
    @{ Name = 'Riesgo'; Header = 'Confianza'; Width = 90; Type = 'TextBox' },
    @{ Name = 'Motivo'; Header = 'Por qué'; Width = 310; Type = 'TextBox' },
    @{ Name = 'Ruta'; Header = 'Ruta'; Width = 420; Type = 'TextBox' }
)
foreach ($column in $columns) {
    if ($column.Type -eq 'CheckBox') { $c = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn } else { $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn; $c.ReadOnly = $true }
    $c.DataPropertyName = $column.Name; $c.HeaderText = $column.Header; $c.Width = $column.Width
    [void]$grid.Columns.Add($c)
}
$form.Controls.Add($grid)

$summary = New-Object System.Windows.Forms.Label
$summary.Text = 'Espacio seleccionado: 0 KB'
$summary.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$summary.Location = New-Object System.Drawing.Point(20, 640)
$summary.AutoSize = $true
$summary.Anchor = 'Bottom,Left'
$form.Controls.Add($summary)

$openFolder = New-Object System.Windows.Forms.Button
$openFolder.Text = 'Abrir ubicación'
$openFolder.Location = New-Object System.Drawing.Point(810, 636)
$openFolder.Size = New-Object System.Drawing.Size(120, 32)
$openFolder.Anchor = 'Bottom,Right'
$form.Controls.Add($openFolder)

$clean = New-Object System.Windows.Forms.Button
$clean.Text = 'Enviar seleccionados a la Papelera'
$clean.Location = New-Object System.Drawing.Point(940, 636)
$clean.Size = New-Object System.Drawing.Size(205, 32)
$clean.Anchor = 'Bottom,Right'
$clean.BackColor = [System.Drawing.Color]::FromArgb(22, 163, 74)
$clean.ForeColor = [System.Drawing.Color]::White
$clean.FlatStyle = 'Flat'
$form.Controls.Add($clean)

$updateSummary = {
    [Int64]$selected = 0
    if ($grid.DataSource) { foreach ($item in $grid.DataSource) { if ($item.Seleccionar) { $selected += $item.Bytes } } }
    $summary.Text = 'Espacio seleccionado: ' + (Format-Size $selected)
}
$grid.add_CellValueChanged({ & $updateSummary })
$grid.add_CurrentCellDirtyStateChanged({ if ($grid.IsCurrentCellDirty) { $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) } })

$browse.add_Click({
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = 'Elige una carpeta. Empieza por tus proyectos, Descargas o Documentos.'
    $picker.SelectedPath = $rootBox.Text
    if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $rootBox.Text = $picker.SelectedPath }
})

$cancel.add_Click({
    $script:CancelScan = $true
    $cancel.Enabled = $false
    $status.Text = 'Cancelando analisis...'
})

$scan.add_Click({
    $chosenRoot = $rootBox.Text.Trim()
    if (-not (Test-Path -LiteralPath $chosenRoot -PathType Container)) { [System.Windows.Forms.MessageBox]::Show('Elige una carpeta existente.', 'EspacioDev Ligero'); return }
    if ($chosenRoot -match '^[A-Za-z]:\\?$') {
        $reply = [System.Windows.Forms.MessageBox]::Show('Analizar toda la unidad puede tardar bastante. ¿Deseas continuar?', 'Análisis amplio', 'YesNo', 'Warning')
        if ($reply -ne 'Yes') { return }
    }
    $script:CancelScan = $false
    $scan.Enabled = $false; $cancel.Enabled = $true; $status.Text = 'Analizando... puede tardar unos minutos en carpetas grandes.'; $grid.DataSource = $null
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $progressCallback = {
            param($scanned, $found)
            $status.Text = "Analizando: $scanned carpetas revisadas, $found candidatas."
            [System.Windows.Forms.Application]::DoEvents()
        }
        $scanResult = Find-CleanupCandidates -Root $chosenRoot -MinimumMB ([int]$minimum.Value) -Progress $progressCallback
        $data = New-Object System.ComponentModel.BindingList[object]
        foreach ($row in @($scanResult.Candidates)) { $data.Add($row) }
        $grid.DataSource = $data
        [Int64]$total = 0; foreach ($row in $data) { $total += $row.Bytes }
        if ($scanResult.Cancelled) { $status.Text = "Analisis cancelado: $($data.Count) candidatas encontradas en $($scanResult.Scanned) carpetas." }
        else { $status.Text = "Se encontraron $($data.Count) carpetas candidatas: $(Format-Size $total). Revisa las marcadas antes de limpiar." }
        & $updateSummary
    } catch {
        $status.Text = 'No se pudo completar el analisis: ' + $_.Exception.Message
    } finally {
        $scan.Enabled = $true; $cancel.Enabled = $false
    }
})

$openFolder.add_Click({
    if ($grid.SelectedRows.Count -eq 0) { return }
    $path = $grid.SelectedRows[0].DataBoundItem.Ruta
    if (Test-Path -LiteralPath $path) { Start-Process explorer.exe -ArgumentList ('/select,"' + $path + '"') }
})

$clean.add_Click({
    if (-not $grid.DataSource) { return }
    $items = @($grid.DataSource | Where-Object { $_.Seleccionar })
    if ($items.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Marca al menos una carpeta para enviarla a la Papelera.', 'EspacioDev Ligero'); return }
    [Int64]$bytes = 0; foreach ($item in $items) { $bytes += $item.Bytes }
    $cleanPrompt = "Enviar $($items.Count) carpetas ($(Format-Size $bytes)) a la Papelera de reciclaje?`n`nRevisa la lista: los elementos marcados como Revisar pueden contener resultados que quieras conservar."
    $answer = [System.Windows.Forms.MessageBox]::Show($cleanPrompt, 'Confirmar limpieza', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }
    $removed = 0
    $blocked = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $items) {
        if ((Test-Path -LiteralPath $item.Ruta -PathType Container) -and (Test-SafeChildPath -Path $item.Ruta -Root $rootBox.Text)) {
            try {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($item.Ruta, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                $removed++
            } catch { [System.Windows.Forms.MessageBox]::Show("No se pudo mover a la Papelera:`n$($item.Ruta)`n`n$($_.Exception.Message)", 'EspacioDev Ligero') }
        } else { $blocked.Add($item.Ruta) }
    }
    if ($removed -eq 0) {
        $status.Text = 'No se envio ninguna carpeta a la Papelera; conserva la lista para revisar las rutas.'
        if ($blocked.Count -gt 0) { [System.Windows.Forms.MessageBox]::Show("Se bloquearon $($blocked.Count) ruta(s) porque ya no estan dentro de la carpeta analizada o no existen. No se elimino nada.", 'EspacioDev Ligero') }
        return
    }
    $status.Text = "$removed carpeta(s) enviada(s) a la Papelera. Vuelve a analizar para actualizar la lista."
    $grid.DataSource = $null; & $updateSummary
})

[void]$form.ShowDialog()
