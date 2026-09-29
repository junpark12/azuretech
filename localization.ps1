$uiLocales = Get-Content (Join-Path $PSScriptRoot 'locales\ui.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Resolve-Within([string]$base, [string]$relative) {
    if ([System.IO.Path]::IsPathRooted($relative)) { throw "Absolute path not allowed: $relative" }
    $prefix=[System.IO.Path]::GetFullPath($base).TrimEnd('\')+'\'
    $resolved=[System.IO.Path]::GetFullPath((Join-Path $base $relative.Replace('/','\')))
    if (-not $resolved.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes allowed directory: $relative" }
    return $resolved
}
function Ui([string]$locale, [string]$key) {
    $property = $uiLocales.$locale.PSObject.Properties[$key]
    if (-not $property -or -not ($property.Value -is [string]) -or -not $property.Value) { throw "Missing UI translation: $locale/$key" }
    return $property.Value
}
function Assert-SourceHash([string]$path, [string]$hash, [string]$description) {
    if ($hash -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hash) {
        throw "Stale or missing translation fingerprint: $description. Review and update both language editions."
    }
}
function Assert-SameSequence($first, $second, [string]$description) {
    if (@($first).Count -ne @($second).Count) { throw "Translation coverage differs: $description" }
    for ($i=0; $i -lt @($first).Count; $i++) {
        if ($first[$i] -cne $second[$i]) { throw "Translation changed protected content: $description item $i" }
    }
}
function Assert-UiTranslation($locales) {
    Assert-SameSequence @($locales.en.PSObject.Properties.Name | Sort-Object) @($locales.ko.PSObject.Properties.Name | Sort-Object) 'UI keys'
    foreach ($locale in @('en','ko')) {
        foreach ($property in $locales.$locale.PSObject.Properties) {
            if (-not ($property.Value -is [string]) -or -not $property.Value) { throw "Missing UI translation: $locale/$($property.Name)" }
        }
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($locales.en | ConvertTo-Json -Depth 10 -Compress))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') }
    finally { $sha.Dispose() }
    if ($locales.koSourceSha256 -cne $hash) { throw 'Stale or missing translation fingerprint: UI text. Review Korean UI before refreshing koSourceSha256.' }
}
function Assert-ArticleParity($english, $korean) {
    if ($english.slug -cne $korean.slug -or $english.category -cne $korean.category) { throw "Translation topic identity mismatch: $($english.slug)" }
    $enBody = $english.bodyHtml.Replace("`r`n","`n")
    $koBody = $korean.bodyHtml.Replace("`r`n","`n")
    foreach ($pattern in @('<pre\b[^>]*>.*?</pre>', '<code\b[^>]*>.*?</code>', '<[a-zA-Z][^<>]*\sid="[^"]+"[^<>]*>', '<a\b[^>]*>')) {
        $enValues = @([regex]::Matches($enBody,$pattern,'Singleline') | ForEach-Object {$_.Value})
        $koValues = @([regex]::Matches($koBody,$pattern,'Singleline') | ForEach-Object {$_.Value})
        Assert-SameSequence $enValues $koValues "$($english.slug) / $pattern"
    }
    foreach ($tag in @('h2','h3','p','li','table','tr','td','th','blockquote')) {
        $enCount=[regex]::Matches($enBody,('<'+$tag+'\b'),'IgnoreCase').Count
        $koCount=[regex]::Matches($koBody,('<'+$tag+'\b'),'IgnoreCase').Count
        if ($enCount -ne $koCount) { throw "Translation structure differs: $($english.slug) <$tag>" }
    }
    $enCells = [regex]::Matches($enBody, '<(td|th)\b[^>]*>(.*?)</\1>', 'Singleline,IgnoreCase')
    $koCells = [regex]::Matches($koBody, '<(td|th)\b[^>]*>(.*?)</\1>', 'Singleline,IgnoreCase')
    for ($i=0; $i -lt $enCells.Count; $i++) {
        $enText = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($enCells[$i].Groups[2].Value, '<[^>]+>', '')).Trim()
        # Narrative quantities can localize "million" to Korean units; literal measurement cells cannot.
        if ($enText -match '^[~<>\u2264\u2265\u00b1$]?\s*\d[\d,]*(?:\.\d+)?\s*(?:%|ms|seconds?|minutes?|hours?|GB|GiB|MB|MiB|vCPU|USD|KRW)?$') {
            $koText = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($koCells[$i].Groups[2].Value, '<[^>]+>', ''))
            $enNumbers = @([regex]::Matches($enText, '\d+(?:[.,]\d+)*') | ForEach-Object { $_.Value })
            $koNumbers = @([regex]::Matches($koText, '\d+(?:[.,]\d+)*') | ForEach-Object { $_.Value })
            Assert-SameSequence $enNumbers $koNumbers "$($english.slug) measurement cell $i"
        }
    }
    if ($koBody -notmatch '[\uAC00-\uD7AF]' -or $korean.title -notmatch '[\uAC00-\uD7AF]') { throw "Korean article lacks translated text: $($english.slug)" }
    if (@($english.sourceDocuments).Count -ne @($korean.sourceDocuments).Count -or @($english.omissions).Count -ne @($korean.omissions).Count) {
        throw "Translation metadata coverage mismatch: $($english.slug)"
    }
    Assert-SameSequence @($english.downloads | ForEach-Object {$_.path}) @($korean.downloads | ForEach-Object {$_.path}) "$($english.slug) downloads"
}
function Read-KoreanArticle($english) {
    $source = Join-Path $PSScriptRoot "content\$($english.slug).json"
    $path = Join-Path $PSScriptRoot "content\ko\$($english.slug).json"
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing Korean article: $($english.slug)" }
    $translation=Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-SourceHash $source $translation.sourceJsonSha256 $english.slug
    if ($english.bodyFile) {
        Assert-SourceHash (Resolve-Within (Join-Path $PSScriptRoot 'content') $english.bodyFile) $translation.sourceBodySha256 "$($english.slug) body"
    } elseif ($translation.sourceBodySha256) { throw "Unexpected body fingerprint: $($english.slug)" }
    if (-not $translation.bodyFile -or -not $translation.summary) { throw "Incomplete Korean article: $($english.slug)" }
    $bodyPath=Resolve-Within (Join-Path $PSScriptRoot 'content\ko') $translation.bodyFile
    $translation | Add-Member -NotePropertyName bodyHtml -NotePropertyValue (Get-Content $bodyPath -Raw -Encoding UTF8) -Force
    Assert-ArticleParity $english $translation
    if ($translation.bodyHtml -match '<\s*(script|iframe|object|embed|style|img|form)\b|<[^>]+\son[a-z]+\s*=') {
        throw "Unexpected active content in Korean article: $($english.slug)"
    }
    return $translation
}
function Read-KoreanVisualText {
    $script:koVisualText=Get-Content (Join-Path $PSScriptRoot 'locales\ko-visuals.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:koPortalText=Get-Content (Join-Path $PSScriptRoot 'locales\ko-portal-screenshots.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-SourceHash (Join-Path $PSScriptRoot 'visuals.json') $koVisualText.sourceSha256 'diagram captions'
    Assert-SourceHash (Join-Path $PSScriptRoot 'portal-screenshots.json') $koPortalText.sourceSha256 'portal captions'
    foreach ($topic in $visuals.PSObject.Properties) {
        $translated=$koVisualText.topics.($topic.Name)
        if (-not $translated.title -or -not $translated.caption) { throw "Missing diagram caption: $($topic.Name)" }
        if ($topic.Value.chart -and (-not $translated.chart.title -or -not $translated.chart.subtitle -or -not $translated.chart.caption)) { throw "Missing chart caption: $($topic.Name)" }
    }
    foreach ($image in $portalScreenshots.images) {
        $translated=$koPortalText.images.($image.id)
        if (-not $translated.title -or -not $translated.alt -or -not $translated.caption) { throw "Missing screenshot caption: $($image.id)" }
    }
}
function Korean-BodyLinks([string]$body) {
    # Only actual hyperlink attributes are rewritten. Code samples remain byte-identical.
    return [regex]::Replace($body, '(<a\b[^>]*\bhref=")(\.\./(?:downloads|assets)/[^"]+)(")', '$1../$2$3')
}
Assert-UiTranslation $uiLocales
