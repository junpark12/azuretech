$visuals = Get-Content (Join-Path $PSScriptRoot 'visuals.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Svg-Icon([string]$kind) {
    $shapes = @{
        client = '<rect x="1" y="2" width="26" height="18" rx="3"/><path d="M8 26h12M14 20v6M6 8l3 3-3 3M13 14h7"/>'
        gateway = '<path d="M3 26V3h22v23M1 26h26M9 26V13h10v13M8 8h12"/>'
        model = '<path d="M14 1l12 7v13l-12 7-12-7V8zM2 8l12 7 12-7M14 15v13"/><circle cx="14" cy="8" r="2"/>'
        chart = '<path d="M2 2v24h26M8 20v-6M15 20V8M22 20V3"/>'
        tools = '<circle cx="14" cy="14" r="7"/><path d="M14 1v6M14 21v6M1 14h6M21 14h6M5 5l4 4M19 19l4 4M5 23l4-4M19 9l4-4"/>'
        registry = '<ellipse cx="14" cy="5" rx="12" ry="4"/><path d="M2 5v18c0 6 24 6 24 0V5M2 14c0 6 24 6 24 0"/>'
        layers = '<path d="M14 2L1 9l13 7 13-7zM2 16l12 7 12-7M2 22l12 7 12-7"/>'
        cluster = '<rect x="1" y="1" width="10" height="10" rx="2"/><rect x="17" y="1" width="10" height="10" rx="2"/><rect x="9" y="19" width="10" height="10" rx="2"/><path d="M6 11v4h16v-4M14 15v4"/>'
        shield = '<path d="M14 1L3 5v9c0 7 11 14 11 14s11-7 11-14V5zM8 14l4 4 8-9"/>'
    }
    if (-not $shapes.ContainsKey($kind)) { throw "Unknown diagram icon: $kind" }
    '<g class="diagram-icon">' + $shapes[$kind] + '</g>'
}
function Topic-Diagram([string]$slug, [switch]$Thumbnail) {
    $v = $visuals.$slug
    if (-not $v -or @($v.nodes).Count -lt 3) { throw "Missing diagram definition: $slug" }
    $marker = 'arrow-' + $slug + $(if ($Thumbnail) { '-card' } else { '-article' })
    $edges = foreach ($e in $v.edges) {
        $dash = if ($e.dashed) { ' diagram-dashed' } else { '' }
        '<path class="diagram-edge' + $dash + '" marker-end="url(#' + $marker + ')" d="' + (Encode $e.d) + '"/><text class="diagram-edge-label" x="' + $e.x + '" y="' + $e.y + '">' + (Encode $e.label) + '</text>'
    }
    $nodes = foreach ($n in $v.nodes) {
        $accent = if ($n.accent) { ' diagram-accent' } else { '' }
        '<g class="diagram-node' + $accent + '" transform="translate(' + $n.x + ' ' + $n.y + ')"><rect width="170" height="80" rx="12"/><g transform="translate(12 12) scale(.7)">' + (Svg-Icon $n.icon) + '</g><text class="diagram-node-title" x="12" y="47">' + (Encode $n.title) + '</text><text class="diagram-node-detail" x="12" y="65">' + (Encode $n.detail) + '</text></g>'
    }
    $access = if ($Thumbnail) { 'aria-hidden="true" focusable="false"' } else { 'role="img" aria-label="' + (Encode ($v.title + '. ' + $v.caption)) + '"' }
    $svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 344" ' + $access + '><defs><marker id="' + $marker + '" viewBox="0 0 8 8" refX="8" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="diagram-arrow" d="M0 0L8 4L0 8z"/></marker></defs><path class="diagram-guide" d="M24 32H696M24 324H696"/><text class="diagram-kicker" x="24" y="23">SYSTEM VIEW / ' + (Encode $slug.ToUpperInvariant().Replace('-', ' ')) + '</text>' + ($edges -join '') + ($nodes -join '') + '</svg>'
    if ($Thumbnail) { return '<div class="topic-illustration">' + $svg + '</div>' }
    '<figure class="technical-visual"><div class="visual-heading"><span class="eyebrow">ARCHITECTURE AT A GLANCE</span><h2 id="visual-overview">' + (Encode $v.title) + '</h2></div><div class="visual-canvas" tabindex="0" role="region" aria-label="Scrollable architecture diagram">' + $svg + '</div><figcaption>' + (Encode $v.caption) + ' Lines show the relationships labeled above; dashed lines distinguish configuration or other non-primary paths. The full procedure below explains the details.</figcaption></figure>'
}
function Topic-Chart([string]$slug, [string]$body) {
    $c = $visuals.$slug.chart
    if (-not $c) { return $body }
    $height = 90 + 48 * @($c.rows).Count
    $ticks = foreach ($tick in $c.ticks) {
        $x = 174 + 446 * ([double]$tick / $c.max)
        $xText = $x.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
        '<path class="chart-grid" d="M' + $xText + ' 36V' + ($height - 40) + '"/><text class="chart-tick" x="' + $xText + '" y="' + ($height - 18) + '">' + $tick + '</text>'
    }
    $i = 0
    $rows = foreach ($row in $c.rows) {
        if ($row.value -le 0 -or $row.value -gt $c.max) { throw "Invalid chart value: $slug" }
        $y = 42 + 48 * $i
        $width = (446 * ([double]$row.value / $c.max)).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
        '<text class="chart-label" x="158" y="' + ($y + 21) + '">' + (Encode $row.label) + '</text><rect class="chart-bar" x="174" y="' + $y + '" width="' + $width + '" height="30" rx="4"/><text class="chart-value" x="635" y="' + ($y + 21) + '">' + $row.value + '</text>'
        $i++
    }
    $description = ($c.rows | ForEach-Object { "$($_.label): $($_.value) $($c.unit)" }) -join '; '
    $chart = '<figure class="technical-visual measurement-chart"><div class="visual-heading"><span class="eyebrow">MEASURED, NOT ASSUMED</span><h3>' + (Encode $c.title) + '</h3><p>' + (Encode $c.subtitle) + '</p></div><div class="visual-canvas" tabindex="0" role="region" aria-label="Scrollable measurement chart"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 ' + $height + '" role="img" aria-label="' + (Encode ($c.title + '. ' + $description)) + '"><text class="diagram-kicker" x="174" y="22">' + (Encode $c.unit.ToUpperInvariant()) + '</text>' + ($ticks -join '') + ($rows -join '') + '</svg></div><figcaption>' + (Encode $c.caption) + '</figcaption></figure>'
    $pattern = '<h2 id="' + [regex]::Escape($c.after) + '">.*?</h2>'
    $match = [regex]::Match($body, $pattern)
    if (-not $match.Success) { throw "Chart section missing: $slug / $($c.after)" }
    $body.Insert($match.Index + $match.Length, $chart)
}
