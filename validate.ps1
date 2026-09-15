$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot 'docs'
$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.topicCount -ne 10) { throw 'The public edition must contain exactly 10 topics.' }
if (@($manifest.topics | Where-Object { $_.category -eq 'App Modernization' }).Count) { throw 'Excluded subject present.' }
$files = @(Get-ChildItem $root -File -Recurse -Force)
$problems = New-Object 'System.Collections.Generic.List[string]'
$htmlFiles = @($files | Where-Object { $_.Extension -eq '.html' })
if ($htmlFiles.Count -ne 11) { $problems.Add("Expected 11 HTML files, found $($htmlFiles.Count).") }
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
    if ($file.Extension -notin @('.html','.css','.js','.json','.xml','.yaml','.yml','.py','.http','.sh','.ps1','.bicep','.txt','.toml','.kql','.promql')) {
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
        try { $null = $text | ConvertFrom-Json } catch { $problems.Add("$($file.Name): invalid JSON: $($_.Exception.Message)") }
    }
    if ($file.Extension -eq '.xml') {
        try { $null = [xml]$text } catch { $problems.Add("$($file.Name): invalid XML: $($_.Exception.Message)") }
    }
}
foreach ($file in $htmlFiles) {
    $html = Get-Content $file.FullName -Raw -Encoding UTF8
    if ($html -notmatch '<html lang="en">' -or $html -notmatch '<meta charset="utf-8">') { $problems.Add("$($file.Name): missing language/encoding.") }
    $ids = @([regex]::Matches($html, '\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { $problems.Add("$($file.Name): duplicate IDs.") }
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
            if ($targetText -notmatch ('\bid="' + [regex]::Escape($anchor) + '"')) { $problems.Add("$($file.Name): missing anchor $link") }
        }
    }
}
foreach ($resource in $manifest.resources) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $resource.Replace('/', '\')) -PathType Leaf)) { $problems.Add("Manifest resource missing: $resource") }
}
if ($problems.Count) { throw ($problems -join "`n") }
Write-Output "Validated 10 topic pages, index, $($manifest.resources.Count) resources, local links, anchors, JSON/XML, language, and publication patterns."
