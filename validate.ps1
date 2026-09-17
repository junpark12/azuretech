$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot 'docs'
$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$portal = Get-Content (Join-Path $PSScriptRoot 'portal-screenshots.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions
$jsonParser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
if ($manifest.topicCount -ne 13) { throw 'The public edition must contain exactly 13 topics.' }
if (@($manifest.topics | Where-Object { $_.slug -eq 'aks-confidential-vm' -and $_.category -eq 'AKS' }).Count -ne 1) { throw 'The AKS CVM topic is missing or duplicated.' }
if (@($manifest.topics | Where-Object { $_.slug -eq 'content-safety-streaming' -and $_.category -eq 'AI' }).Count -ne 1) { throw 'The Content Safety streaming topic is missing or duplicated.' }
if (@($manifest.topics | Where-Object { $_.slug -eq 'self-hosted-aca' -and $_.category -eq 'GitHub' }).Count -ne 1) { throw 'The GitHub ACA runner topic is missing or duplicated.' }
if (@($manifest.topics | Where-Object { $_.category -eq 'App Modernization' }).Count) { throw 'Excluded subject present.' }
$files = @(Get-ChildItem $root -File -Recurse -Force)
$problems = New-Object 'System.Collections.Generic.List[string]'
$htmlFiles = @($files | Where-Object { $_.Extension -eq '.html' })
if ($htmlFiles.Count -ne 14) { $problems.Add("Expected 14 HTML files, found $($htmlFiles.Count).") }
$guidPattern = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
$publicRoleIds = @('5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') # Cognitive Services OpenAI User.
$checks = @{
    'Non-English Korean text' = '[\uAC00-\uD7AF]'
    'Private source repository reference' = '(?i)vKB-|AppModernization'
    'Private key material' = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    'Credential-like token' = '(?i)\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{24,})\b'
    'Populated SAS signature' = '(?i)[?&](?:amp;)?sig=[A-Za-z0-9%+/]{20,}'
}
foreach ($file in $files) {
    if ($file.Extension -eq '.png') {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\','/')
        $entry = @($portal.images | Where-Object { $_.path -ceq $relative })
        if ($entry.Count -ne 1) { $problems.Add("Unreviewed PNG: $relative"); continue }
        if ((Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne $entry[0].sha256) { $problems.Add("PNG differs from reviewed pixels: $relative") }
        $image = [System.Drawing.Image]::FromFile($file.FullName)
        try {
            if ($image.Width -ne $entry[0].width -or $image.Height -ne $entry[0].height) { $problems.Add("PNG dimensions differ: $relative") }
        }
        finally { $image.Dispose() }
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $offset = 8
        $endFound = $false
        while ($offset + 12 -le $bytes.Length) {
            $length = [uint32]$bytes[$offset] * 16777216 + [uint32]$bytes[$offset+1] * 65536 + [uint32]$bytes[$offset+2] * 256 + [uint32]$bytes[$offset+3]
            $chunk = [System.Text.Encoding]::ASCII.GetString($bytes,$offset+4,4)
            if ($chunk -notin @('IHDR','IDAT','IEND','sRGB','gAMA','pHYs','cHRM')) { $problems.Add("Unreviewed PNG metadata chunk $chunk in $relative") }
            $offset += 12 + $length
            if ($chunk -eq 'IEND') { $endFound = $true; break }
        }
        if (-not $endFound -or $offset -ne $bytes.Length) { $problems.Add("Invalid PNG boundary or trailing data: $relative") }
        continue
    }
    if ($file.Name -notin @('Dockerfile','.gitignore','.dockerignore') -and $file.Extension -notin @('.html','.css','.js','.json','.xml','.yaml','.yml','.py','.http','.sh','.ps1','.bicep','.txt','.toml','.kql','.promql')) {
        if ($file.Name -ne '.nojekyll') { $problems.Add("Unreviewed file type: $($file.Name)") }
        continue
    }
    $text = Get-Content $file.FullName -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($text, $guidPattern)) {
        if ($match.Value -notin $publicRoleIds) {
            $problems.Add("$($file.Name): non-allowlisted GUID requires review and parameterization")
        }
    }
    foreach ($check in $checks.GetEnumerator()) {
        if ($text -match $check.Value) { $problems.Add("$($file.Name): $($check.Key)") }
    }
    if ($file.Extension -eq '.json') {
        # npm lockfiles use an empty-string package key, unsupported by PowerShell 5's object conversion.
        try { $null = $jsonParser.DeserializeObject($text) } catch { $problems.Add("$($file.Name): invalid JSON: $($_.Exception.Message)") }
    }
    if ($file.Extension -eq '.xml') {
        try { $null = [xml]$text } catch { $problems.Add("$($file.Name): invalid XML: $($_.Exception.Message)") }
    }
}
foreach ($file in $htmlFiles) {
    $html = Get-Content $file.FullName -Raw -Encoding UTF8
    if ($html -notmatch '<html lang="en">' -or $html -notmatch '<meta charset="utf-8">') { $problems.Add("$($file.Name): missing language/encoding.") }
    $ids = @([regex]::Matches($html, '<[a-zA-Z][^<>]*\sid="([^"]+)"[^<>]*>') | ForEach-Object { $_.Groups[1].Value })
    if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { $problems.Add("$($file.Name): duplicate IDs.") }
    $expectedImages = @($portal.images | Where-Object { $_.topic -eq $file.BaseName })
    $renderedImages = [regex]::Matches($html, '<img\b[^>]*>')
    if ($renderedImages.Count -ne $expectedImages.Count) { $problems.Add("$($file.Name): incorrect screenshot count.") }
    foreach ($tag in $renderedImages) {
        if ($tag.Value -notmatch 'alt="[^"]+"' -or $tag.Value -notmatch 'width="\d+"' -or $tag.Value -notmatch 'height="\d+"') { $problems.Add("$($file.Name): missing image accessibility/dimensions.") }
    }
    $svgs = [regex]::Matches($html, '<svg\b.*?</svg>', 'Singleline')
    $expectedSvgCount = if ($file.Name -eq 'index.html') { $manifest.topicCount } elseif ($file.BaseName -in @('translation-performance','ase-frontend-scaling')) { 2 } else { 1 }
    if ($svgs.Count -ne $expectedSvgCount) { $problems.Add("$($file.Name): expected $expectedSvgCount visual(s), found $($svgs.Count).") }
    foreach ($svg in $svgs) {
        try { $null = [xml]$svg.Value } catch { $problems.Add("$($file.Name): malformed SVG.") }
        if ($svg.Value -match '<(?:script|foreignObject|image)\b|\son\w+=|(?:href|src)=') { $problems.Add("$($file.Name): unexpected SVG active or external content.") }
        if ($svg.Value -notmatch '(?:aria-label|aria-hidden)=') { $problems.Add("$($file.Name): missing SVG accessibility treatment.") }
    }
    foreach ($match in [regex]::Matches($html, '(?:href|src)="([^"]+)"')) {
        $link = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
        if ($link -match '^https://') { continue }
        if ($link -match '^(?:[a-z][a-z0-9+.-]*:|//|/)') { $problems.Add("$($file.Name): unsupported/non-project link $link"); continue }
        $parts = $link.Split('#', 2)
        $path = [System.Uri]::UnescapeDataString($parts[0].Split('?', 2)[0])
        $target = if (-not $path) { $file.FullName } else { [System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $path.Replace('/', '\'))) }
        if (-not $target.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $problems.Add("$($file.Name): path escapes site root: $link"); continue
        }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { $problems.Add("$($file.Name): missing local target $link"); continue }
        if ($parts.Count -gt 1 -and $parts[1] -and [System.IO.Path]::GetExtension($target) -eq '.html') {
            $anchor = [System.Uri]::UnescapeDataString($parts[1])
            $targetText = Get-Content $target -Raw -Encoding UTF8
            if ($targetText -notmatch ('<[a-zA-Z][^<>]*\sid="' + [regex]::Escape($anchor) + '"[^<>]*>')) { $problems.Add("$($file.Name): missing anchor $link") }
        }
    }
}
$visualData = Get-Content (Join-Path $PSScriptRoot 'visuals.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$translation = Get-Content (Join-Path $PSScriptRoot 'content\translation-performance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($row in $visualData.'translation-performance'.chart.rows) {
    $value = ([int]$row.value).ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($translation.bodyHtml -notmatch ('<td>' + [regex]::Escape($row.label) + '</td><td>' + [regex]::Escape($value) + '</td>')) {
        $problems.Add("Translation chart value not found in source table: $($row.label)")
    }
}
$ase = Get-Content (Join-Path $PSScriptRoot 'content\ase-frontend-scaling.html') -Raw -Encoding UTF8
foreach ($row in $visualData.'ase-frontend-scaling'.chart.rows) {
    $labelParts = $row.label -split ' '
    $sourcePattern = '<td>' + $labelParts[0] + ' &#8594; ' + $labelParts[2] + '</td><td>' + $row.value + ' minutes</td>'
    $normalized = $ase.Replace([string][char]0x2192, '&#8594;')
    if ($normalized -notmatch $sourcePattern) { $problems.Add("ASE chart value not found in source table: $($row.label)") }
}
foreach ($resource in $manifest.resources) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $resource.Replace('/', '\')) -PathType Leaf)) { $problems.Add("Manifest resource missing: $resource") }
}
if (@($manifest.portalScreenshots).Count -ne @($portal.images).Count) { $problems.Add('Screenshot manifest count mismatch.') }
foreach ($image in $portal.images) {
    if ($image.path -notmatch '^assets/portal/[a-z0-9-]+\.png$' -or -not (Test-Path (Join-Path $root $image.path.Replace('/','\')))) {
        $problems.Add("Invalid or missing declared screenshot: $($image.id)")
    }
}
if ($problems.Count) { throw ($problems -join "`n") }
Write-Output "Validated $($manifest.topicCount) topic pages, index, $($manifest.resources.Count) resources, local links, anchors, JSON/XML, language, and publication patterns."
