$portalScreenshots = Get-Content (Join-Path $PSScriptRoot 'portal-screenshots.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Get-PortalCaptureDate($image) {
    if ($image.capturedOn) { return $image.capturedOn }
    return $portalScreenshots.capturedOn
}
function Add-PortalScreenshots([string]$slug, [string]$body) {
    foreach ($image in @($portalScreenshots.images | Where-Object { $_.topic -eq $slug })) {
        $pattern = '<h2 id="' + [regex]::Escape($image.section) + '">.*?</h2>'
        $match = [regex]::Match($body, $pattern)
        if (-not $match.Success) { throw "Screenshot section missing: $slug / $($image.section)" }
        $path = '../' + (Encode $image.path)
        $html = @"
<figure class="portal-capture" id="portal-$($image.id)">
<div class="visual-heading"><span class="eyebrow">AZURE PORTAL / ENGLISH UI</span><h3>$(Encode $image.title)</h3><p class="portal-navigation">$(Encode $image.navigation)</p></div>
<a class="portal-image-link" href="$path" target="_blank" rel="noopener" aria-label="Open full-size screenshot: $(Encode $image.title)"><img src="$path" alt="$(Encode $image.alt)" width="$($image.width)" height="$($image.height)" loading="lazy" decoding="async"></a>
<figcaption><span class="capture-meta">Captured $(Encode (Get-PortalCaptureDate $image)) &middot; Identifiers redacted or excluded &middot; Open image for full size</span>$(Encode $image.caption)</figcaption>
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
