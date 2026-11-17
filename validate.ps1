$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot 'docs'
$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$portal = Get-Content (Join-Path $PSScriptRoot 'portal-screenshots.json') -Raw -Encoding UTF8 | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'localization.ps1')
$visuals=Get-Content (Join-Path $PSScriptRoot 'visuals.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$portalScreenshots=$portal
Read-KoreanVisualText
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions
$jsonParser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
if ($manifest.topicCount -ne 17) { throw 'The public edition must contain exactly 17 topics.' }
Assert-SameSequence @('en','ko') @($manifest.languages) 'published languages'
if ($manifest.pageCount -ne 36) { throw 'Expected 36 bilingual pages.' }
foreach ($slug in @('openai-foundry-migration','hosted-agent-latency','aks-hyperscale')) {
    $category = if ($slug -eq 'aks-hyperscale') { 'AKS' } else { 'AI' }
    if (@($manifest.topics | Where-Object { $_.slug -eq $slug -and $_.category -eq $category -and $_.publishedOn -eq '2026-10-07' }).Count -ne 1) { throw "New topic missing or incorrect: $slug" }
}
if (@($manifest.topics | Where-Object { $_.slug -eq 'aks-confidential-vm' -and $_.category -eq 'AKS' }).Count -ne 1) { throw 'The AKS CVM topic is missing or duplicated.' }
if (@($manifest.topics | Where-Object { $_.slug -eq 'content-safety-streaming' -and $_.category -eq 'AI' }).Count -ne 1) { throw 'The Content Safety streaming topic is missing or duplicated.' }
if (@($manifest.topics | Where-Object { $_.slug -eq 'self-hosted-aca' -and $_.category -eq 'GitHub' }).Count -ne 1) { throw 'The GitHub ACA runner topic is missing or duplicated.' }
if (@($manifest.topics | Where-Object { $_.slug -eq 'copilot-fusion' -and $_.category -eq 'GitHub' -and $_.publishedOn -eq '2026-11-17' }).Count -ne 1) { throw 'The Copilot Fusion topic is missing or incorrect.' }
if (@($manifest.topics | Where-Object { $_.category -eq 'App Modernization' }).Count) { throw 'Excluded subject present.' }
$files = @(Get-ChildItem $root -File -Recurse -Force)
$problems = New-Object 'System.Collections.Generic.List[string]'
$htmlFiles = @($files | Where-Object { $_.Extension -eq '.html' })
if ($htmlFiles.Count -ne 36) { $problems.Add("Expected 36 HTML files, found $($htmlFiles.Count).") }
$guidPattern = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
$publicRoleIds = @('5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') # Cognitive Services OpenAI User.
$checks = @{
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
    $relativePage=$file.FullName.Substring($root.Length+1).Replace('\','/')
    $locale=if($relativePage.StartsWith('ko/')){'ko'}else{'en'}
    if ($html -notmatch ('<html lang="'+$locale+'">') -or $html -notmatch '<meta charset="utf-8">') { $problems.Add("$relativePage : incorrect language/encoding.") }
    $counterpart=if($locale -eq 'ko'){$relativePage.Substring(3)}else{'ko/'+$relativePage}
    if(-not(Test-Path (Join-Path $root $counterpart.Replace('/','\')))){ $problems.Add("Missing language counterpart: $relativePage") }
    $switches=[regex]::Matches($html,'<a class="language-link" href="([^"]+)" hreflang="(en|ko)" lang="(en|ko)"([^>]*)>')
    if($switches.Count -ne 2){$problems.Add("Missing language switch: $relativePage")}
    foreach($link in $switches){
        $language=$link.Groups[2].Value
        $href=[System.Net.WebUtility]::HtmlDecode($link.Groups[1].Value)
        $destination=[System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $href.Replace('/','\')))
        $want=if($language -eq $locale){$file.FullName}else{Join-Path $root $counterpart.Replace('/','\')}
        if($destination -ne $want){$problems.Add("Language switch does not map same article: $relativePage / $language")}
        if(($language -eq $locale) -ne ($link.Groups[4].Value -match 'aria-current="page"')){$problems.Add("Incorrect current language: $relativePage")}
    }
    foreach($language in @('en','ko','x-default')){
        if($html -notmatch ('<link rel="alternate" hreflang="'+$language+'" href="https://junpark12.github.io/azuretech/')){$problems.Add("Missing alternate language: $relativePage / $language")}
    }
    if($locale -eq 'ko' -and $html -notmatch '[\uAC00-\uD7AF]'){$problems.Add("Korean page is not translated: $relativePage")}
    $ids = @([regex]::Matches($html, '<[a-zA-Z][^<>]*\sid="([^"]+)"[^<>]*>') | ForEach-Object { $_.Groups[1].Value })
    if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { $problems.Add("$($file.Name): duplicate IDs.") }
    $expectedImages = @($portal.images | Where-Object { $_.topic -eq $file.BaseName })
    $renderedImages = [regex]::Matches($html, '<img\b[^>]*>')
    if ($renderedImages.Count -ne $expectedImages.Count) { $problems.Add("$($file.Name): incorrect screenshot count.") }
    foreach ($tag in $renderedImages) {
        if ($tag.Value -notmatch 'alt="[^"]+"' -or $tag.Value -notmatch 'width="\d+"' -or $tag.Value -notmatch 'height="\d+"') { $problems.Add("$($file.Name): missing image accessibility/dimensions.") }
    }
    $svgs = [regex]::Matches($html, '<svg\b.*?</svg>', 'Singleline')
    $expectedSvgCount = if ($file.Name -eq 'index.html') { $manifest.topicCount } elseif ($visuals.($file.BaseName).chart) { 2 } else { 1 }
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
foreach($metadata in Get-ChildItem (Join-Path $PSScriptRoot 'content') -Filter '*.json'){
    $english=Get-Content $metadata.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    if($english.bodyFile){$english|Add-Member -NotePropertyName bodyHtml -NotePropertyValue (Get-Content (Resolve-Within $metadata.DirectoryName $english.bodyFile) -Raw -Encoding UTF8) -Force}
    $korean=Read-KoreanArticle $english
    if($english.bodyHtml -match '[\uAC00-\uD7AF]'){$problems.Add("Korean text leaked into English source: $($english.slug)")}
    foreach($language in @('en','ko')){
        $relative=if($language -eq 'ko'){"ko/topics/$($english.slug).html"}else{"topics/$($english.slug).html"}
        $pageText=Get-Content (Join-Path $root $relative.Replace('/','\')) -Raw -Encoding UTF8
        $expectedBody=if($language -eq 'ko'){$korean.bodyHtml}else{$english.bodyHtml}
        $expectedPre=@([regex]::Matches($expectedBody,'<pre\b[^>]*>.*?</pre>','Singleline')|ForEach-Object{$_.Value.Replace("`r`n","`n")})
        $renderedPre=@([regex]::Matches($pageText,'<pre\b[^>]*>.*?</pre>','Singleline')|ForEach-Object{$_.Value.Replace("`r`n","`n")})
        Assert-SameSequence $expectedPre $renderedPre "$relative rendered examples"
        $dateMarkup = if ($english.publishedOn) { '<time datetime="' + $english.publishedOn + '">' + $english.publishedOn + '</time>' } else { [System.Net.WebUtility]::HtmlEncode((Ui $language 'archiveEditionDate')) }
        if ($pageText -notmatch ('<div class="article-meta">.*?' + [regex]::Escape($dateMarkup) + '</span></div>')) { $problems.Add("Article date mismatch: $relative") }
    }
}
if(Test-Path (Join-Path $root 'ko\downloads')){$problems.Add('Korean locale must use shared downloads, not duplicated files.')}
if(Test-Path (Join-Path $root 'ko\assets')){$problems.Add('Korean locale must use shared assets, not duplicated files.')}
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
$latency = Get-Content (Join-Path $PSScriptRoot 'content\hosted-agent-latency.html') -Raw -Encoding UTF8
$measurementSection = [regex]::Match($latency, '<h2 id="measurements">.*?(?=<h2\b)', 'Singleline').Value
$measurementRows = [regex]::Matches($measurementSection, '<tr><td>(\d+)</td><td>(Cold|Warm|Resume)</td><td>([ABC]):[^<]*</td><td>(\d+\.\d+)</td></tr>')
$chart = $visualData.'hosted-agent-latency'.chart
if ($measurementRows.Count -ne 5 -or @($chart.rows).Count -ne 5 -or $chart.unit -ne 'seconds') { $problems.Add('Hosted latency chart must preserve all five observations in seconds.') }
for ($i=0; $i -lt $measurementRows.Count; $i++) {
    $row = $chart.rows[$i]
    $record = $measurementRows[$i]
    $value = [double]::Parse($record.Groups[4].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    $label = $record.Groups[2].Value + ' ' + $record.Groups[3].Value
    if ($row.sourceRow -ne [int]$record.Groups[1].Value -or $row.label -cne $label -or $row.value -ne $value) { $problems.Add("Hosted latency chart differs from source row $($i + 1).") }
}
foreach ($resource in $manifest.resources) {
    $publishedPath = Resolve-Within $root $resource
    $sourcePath = Resolve-Within $PSScriptRoot $resource
    if (-not (Test-Path -LiteralPath $publishedPath -PathType Leaf)) { $problems.Add("Manifest resource missing: $resource") }
    elseif ((Get-FileHash -LiteralPath $publishedPath).Hash -ne (Get-FileHash -LiteralPath $sourcePath).Hash) { $problems.Add("Shared download differs from source: $resource") }
}
foreach ($asset in @('assets/site.css','assets/site.js')) {
    if ((Get-FileHash -LiteralPath (Resolve-Within $root $asset)).Hash -ne (Get-FileHash -LiteralPath (Resolve-Within $PSScriptRoot $asset)).Hash) {
        $problems.Add("Shared asset is stale: $asset")
    }
}
if (@($manifest.portalScreenshots).Count -ne @($portal.images).Count) { $problems.Add('Screenshot manifest count mismatch.') }
foreach ($image in $portal.images) {
    if ($image.path -notmatch '^assets/portal/[a-z0-9-]+\.png$' -or -not (Test-Path (Join-Path $root $image.path.Replace('/','\')))) {
        $problems.Add("Invalid or missing declared screenshot: $($image.id)")
    }
}
if ($problems.Count) { throw ($problems -join "`n") }
function Assert-ValidationRejects([scriptblock]$action, [string]$expected) {
    try { & $action }
    catch {
        if ($_.Exception.Message -notlike "*$expected*") { throw }
        return
    }
    throw "Regression: validation accepted invalid input ($expected)."
}
$changedUi = $uiLocales | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$changedUi.en.homeTitle += ' changed'
Assert-ValidationRejects { Assert-UiTranslation $changedUi } 'fingerprint: UI text'
Assert-ValidationRejects { Assert-SourceHash (Join-Path $PSScriptRoot 'content\translation-performance.json') ('0' * 64) 'regression source' } 'fingerprint: regression source'
Assert-ValidationRejects { Read-KoreanArticle ([pscustomobject]@{slug='missing-regression-fixture'}) } 'Missing Korean article'
$changedMeasurement = Read-KoreanArticle $translation
$cell = [regex]::Match($changedMeasurement.bodyHtml, '<td>(\d[\d,.]*)</td>')
if (-not $cell.Success) { throw 'Measurement regression fixture is missing.' }
$changedMeasurement.bodyHtml = $changedMeasurement.bodyHtml.Remove($cell.Groups[1].Index, $cell.Groups[1].Length).Insert($cell.Groups[1].Index, '999999999')
Assert-ValidationRejects { Assert-ArticleParity $translation $changedMeasurement } 'measurement cell'
Write-Output "Validated $($manifest.topicCount) bilingual topics, $($manifest.pageCount) pages, $($manifest.resources.Count) shared resources, publication dates, locale links, source/UI fingerprints, code/measurement parity, rejection regressions, and publication safeguards."
