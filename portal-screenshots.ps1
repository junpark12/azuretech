$portalScreenshots = Get-Content (Join-Path $PSScriptRoot 'portal-screenshots.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Get-PortalCaptureDate($image) {
    if ($image.capturedOn) { return $image.capturedOn }
    return $portalScreenshots.capturedOn
}
function Add-PortalScreenshots([string]$slug, [string]$body, [string]$Locale = 'en', [string]$AssetPrefix = '../') {
    foreach ($image in @($portalScreenshots.images | Where-Object { $_.topic -eq $slug })) {
        $pattern = '<h2 id="' + [regex]::Escape($image.section) + '">.*?</h2>'
        $match = [regex]::Match($body, $pattern)
        if (-not $match.Success) { throw "Screenshot section missing: $slug / $($image.section)" }
        $path = $AssetPrefix + (Encode $image.path)
        $copy = if ($Locale -eq 'ko') { $koPortalText.images.($image.id) } else { $image }
        $html = @"
<figure class="portal-capture" id="portal-$($image.id)">
<div class="visual-heading"><span class="eyebrow">$(Encode (Ui $Locale 'portalEyebrow'))</span><h3>$(Encode $copy.title)</h3><p class="portal-navigation">$(Encode $image.navigation)</p></div>
<a class="portal-image-link" href="$path" target="_blank" rel="noopener" aria-label="$(Encode (Ui $Locale 'openImage'))$(Encode $copy.title)"><img src="$path" alt="$(Encode $copy.alt)" width="$($image.width)" height="$($image.height)" loading="lazy" decoding="async"></a>
<figcaption><span class="capture-meta">$(Encode (Ui $Locale 'captured')) $(Encode (Get-PortalCaptureDate $image)) &middot; $(Encode (Ui $Locale 'captureNote')) &middot; $(Encode (Ui $Locale 'fullSize'))</span>$(Encode $copy.caption)</figcaption>
</figure>
"@
        $body = $body.Insert($match.Index + $match.Length, $html)
    }
    return $body
}
function Test-PortalImage([string]$path) {
    $relative = $path.Replace('\','/')
    $entry = @($portalScreenshots.images | Where-Object { $_.path -ceq $relative })
    if ($entry.Count -ne 1) { throw "Unreviewed or duplicate portal image: $relative" }
    $fullPath = Join-Path $PSScriptRoot $path.Replace('/','\')
    if ((Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash -ne $entry[0].sha256) {
        throw "Portal image changed after pixel review: $relative"
    }
}
