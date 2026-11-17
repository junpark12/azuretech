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
function Topic-Thumbnail([string]$slug) {
    $art = switch ($slug) {
        'openai-foundry-migration' {
            @{
                product = 'AZURE AI FOUNDRY'; detail = 'OPENAI / PRIVATE ENDPOINT'; tone = 'violet'
                symbol = '<path class="card-art-fill" d="M64 8 108 34v52l-44 26-44-26V34Z"/><path d="m20 34 44 26 44-26M64 60v52"/><path class="card-art-solid" d="m64 23 5 15 15 5-15 5-5 15-5-15-15-5 15-5Z"/><path d="M12 91v18h27m-9-9 9 9-9 9M116 29V11H89m9-9-9 9 9 9"/>'
            }
        }
        'hosted-agent-latency' {
            @{
                product = 'HOSTED AGENTS'; detail = 'STARTUP / RESPONSE TIME'; tone = 'teal'
                symbol = '<circle class="card-art-fill" cx="64" cy="72" r="44"/><path d="M52 8h24M64 8v20m29 11 10-10m-5-5 10 10M64 72V46m0 26 19 12"/><path d="M40 1H10v30h10l10 10V31h10Z"/><circle class="card-art-solid" cx="64" cy="72" r="4"/><path d="M29 72h5m60 0h5M64 107v-5"/>'
            }
        }
        'aks-hyperscale' {
            @{
                product = 'AZURE KUBERNETES SERVICE'; detail = 'HYPERSCALE CONTROL PLANE'; tone = 'azure'
                symbol = '<circle class="card-art-fill" cx="57" cy="59" r="32"/><circle cx="57" cy="59" r="10"/><path d="M57 9v40m0 20v40M7 59h40m20 0h40M22 24l28 28m14 14 28 28M22 94l28-28m14-14 28-28"/><circle cx="57" cy="9" r="4"/><circle cx="57" cy="109" r="4"/><circle cx="7" cy="59" r="4"/><circle cx="107" cy="59" r="4"/><path class="card-art-solid" d="M89 119V99h8v20Zm14 0V87h8v32Zm14 0V73h8v46Z"/>'
            }
        }
        'aks-confidential-vm' {
            @{
                product = 'AKS CONFIDENTIAL VMS'; detail = 'HARDWARE TRUST BOUNDARY'; tone = 'azure'
                symbol = '<path class="card-art-fill" d="m64 7 44 17v34c0 28-22 49-44 62C42 107 20 86 20 58V24Z"/><rect x="43" y="40" width="42" height="42" rx="6"/><path d="M53 32v8m11-8v8m11-8v8M53 82v8m11-8v8m11-8v8M35 50h8m-8 11h8m-8 11h8m42-22h8m-8 11h8m-8 11h8"/><path class="card-art-solid" d="M56 53h16v16H56Z"/>'
            }
        }
        'content-safety-streaming' {
            @{
                product = 'AZURE AI CONTENT SAFETY'; detail = 'STREAMING RESPONSE FILTER'; tone = 'teal'
                symbol = '<path class="card-art-fill" d="m64 9 34 13v34c0 23-16 42-34 54-18-12-34-31-34-54V22Z"/><path d="m46 55 12 12 25-27M4 35h15M1 55h18M7 75h12m90-40h15m-15 20h18m-18 20h12"/><path class="card-art-solid" d="m56 117 8 7 8-7Z"/>'
            }
        }
        'ai-gateway' {
            @{
                product = 'AZURE API MANAGEMENT'; detail = 'AI GATEWAY / MODELS / MCP'; tone = 'violet'
                symbol = '<path class="card-art-fill" d="M29 113V28L64 9l35 19v85H78V70H50v43Z"/><path d="M18 113h92M40 38h48M40 50h48M64 70v43"/><path class="card-art-solid" d="m110 8 4 11 11 4-11 4-4 11-4-11-11-4 11-4ZM13 54l3 8 8 3-8 3-3 8-3-8-8-3 8-3Z"/>'
            }
        }
        'ai-gateway-existing' {
            @{
                product = 'AZURE API MANAGEMENT'; detail = 'BACKEND POOLS / IDENTITY'; tone = 'azure'
                symbol = '<rect class="card-art-fill" x="14" y="15" width="66" height="96" rx="9"/><path d="M26 35h42M26 51h42M26 67h24M26 83h18"/><circle cx="84" cy="82" r="22"/><circle cx="84" cy="78" r="7"/><path d="m84 85 1 11m14 3 19 19m-5-15-5 5M24 111v7m46-7v7"/>'
            }
        }
        'codex' {
            @{
                product = 'CODEX ON AZURE'; detail = 'CODING / ROUTING / CAPACITY'; tone = 'teal'
                symbol = '<rect class="card-art-fill" x="7" y="20" width="114" height="87" rx="10"/><path d="M7 42h114m-95 0v-1m11 1v-1m11 1v-1M28 61l16 13-16 13m28 0h22"/><path class="card-art-solid" d="m104 2 4 11 11 4-11 4-4 11-4-11-11-4 11-4Z"/>'
            }
        }
        'copilot-fusion' {
            @{
                product = 'GITHUB COPILOT'; detail = 'FUSION / MODEL ORCHESTRATION'; tone = 'violet'
                symbol = '<path class="card-art-fill" d="M22 44c0-15 17-25 42-25s42 10 42 25v40c0 20-20 32-42 32S22 104 22 84Z"/><rect x="31" y="44" width="26" height="28" rx="10"/><rect x="71" y="44" width="26" height="28" rx="10"/><path d="M57 53h14M22 59H12v23h10m84-23h10v23h-10M49 93c10 6 20 6 30 0M64 19V9"/><circle class="card-art-solid" cx="64" cy="5" r="4"/><path d="m9 17 2 6 6 2-6 2-2 6-2-6-6-2 6-2Zm105-6 3 8 8 3-8 3-3 8-3-8-8-3 8-3Z"/>'
            }
        }
        'translation-performance' {
            @{
                product = 'AZURE OPENAI'; detail = 'TRANSLATION BENCHMARK'; tone = 'violet'
                symbol = '<path class="card-art-fill" d="M8 14h73v62H41L23 92V76H8Z"/><path d="M81 43h38v65h-15v15l-18-15H49V91"/><text class="card-art-glyph" x="29" y="58">A</text><text class="card-art-glyph" x="72" y="92">&#25991;</text><path d="M92 14h24m-8-8 8 8-8 8M35 108H11m8-8-8 8 8 8"/>'
            }
        }
        'acr-streaming' {
            @{
                product = 'AZURE CONTAINER REGISTRY'; detail = 'AKS / ARTIFACT STREAMING'; tone = 'azure'
                symbol = '<path class="card-art-fill" d="m70 12 45 26v52l-45 26-45-26V38Z"/><path d="m25 38 45 26 45-26M70 64v52M48 25l45 26v25"/><path d="M1 52h34M7 67h28M1 82h34"/><path class="card-art-solid" d="m29 97 17 9-17 9Z"/>'
            }
        }
        'cilium-network-policy' {
            @{
                product = 'CILIUM ON AKS'; detail = 'NETWORK POLICY / EBPF'; tone = 'amber'
                symbol = '<ellipse class="card-art-fill" cx="43" cy="59" rx="20" ry="28" transform="rotate(-30 43 59)"/><ellipse class="card-art-fill" cx="85" cy="59" rx="20" ry="28" transform="rotate(30 85 59)"/><ellipse class="card-art-fill" cx="64" cy="78" rx="23" ry="35"/><circle cx="64" cy="32" r="16"/><path d="m54 18-8-11m28 11 8-11M43 69h42M42 84h44m-39 14h34M41 78l-13 9m59-9 13 9M64 113v8"/><circle class="card-art-solid" cx="58" cy="31" r="2"/><circle class="card-art-solid" cx="70" cy="31" r="2"/>'
            }
        }
        'envoy-gateway' {
            @{
                product = 'ENVOY GATEWAY'; detail = 'KUBERNETES GATEWAY API'; tone = 'violet'
                symbol = '<path class="card-art-fill" d="m8 45 111-32-37 85-24-30-24 14V54Z"/><path d="m34 54 85-41-61 55M34 54v28M21 98H7m25 13H14m71-2h35"/><path d="M47 120v-20a15 15 0 0 1 30 0v20M39 120h46"/>'
            }
        }
        'istio-gateway-api' {
            @{
                product = 'ISTIO ON AKS'; detail = 'APPLICATION ROUTING / TLS'; tone = 'azure'
                symbol = '<path class="card-art-fill" d="M58 10 17 85h41Zm9 25v50h40Z"/><path d="M58 7v90M9 96h107l-21 19H30Z"/><path d="M5 122c10-7 18 7 28 0s18 7 28 0 18 7 28 0 18 7 28 0"/><rect x="88" y="26" width="27" height="23" rx="4"/><path d="M94 26v-7a8 8 0 0 1 16 0v7"/>'
            }
        }
        'ase-frontend-scaling' {
            @{
                product = 'AZURE APP SERVICE'; detail = 'ASE V3 / FRONT-END SCALING'; tone = 'coral'
                symbol = '<path class="card-art-fill" d="M12 117V79h25v38Zm40 0V54h25v63Zm40 0V29h25v88Z"/><path d="M4 117h120M19 93h11m29-25h11m29-25h11M16 60 51 35l23 5 33-27m-20 0h20v20"/><circle class="card-art-solid" cx="25" cy="105" r="2"/><circle class="card-art-solid" cx="65" cy="105" r="2"/><circle class="card-art-solid" cx="105" cy="105" r="2"/>'
            }
        }
        'managed-instance' {
            @{
                product = 'AZURE APP SERVICE'; detail = 'MANAGED INSTANCE'; tone = 'coral'
                symbol = '<path class="card-art-fill" d="M27 89a22 22 0 0 1-4-44 31 31 0 0 1 59-10 27 27 0 0 1 24 48"/><rect x="35" y="55" width="58" height="53" rx="7"/><path d="M35 70h58M48 63h1m8 0h1M49 83h29m-29 12h20M47 108v10m17-10v10m17-10v10M25 81h10m-10 16h10m58-16h10m-10 16h10"/>'
            }
        }
        'self-hosted-aca' {
            @{
                product = 'GITHUB ACTIONS'; detail = 'CONTAINER APPS / KEDA'; tone = 'teal'
                symbol = '<rect class="card-art-fill" x="12" y="70" width="104" height="46" rx="5"/><path d="M25 81v24m14-24v24m14-24v24m14-24v24m14-24v24m14-24v24M19 116v7m90-7v7"/><circle class="card-art-fill" cx="64" cy="37" r="29"/><path class="card-art-solid" d="m57 23 22 14-22 14Zm53-15L97 29h11l-5 17 21-26h-13l9-12Z"/>'
            }
        }
        default { throw "Missing topic thumbnail: $slug" }
    }
    '<div class="topic-illustration" data-topic="' + (Encode $slug) + '"><svg class="card-art card-art-' + $art.tone + '" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 300" aria-hidden="true" focusable="false"><ellipse class="card-art-halo" cx="320" cy="148" rx="113" ry="106"/><text class="card-art-product" x="28" y="34">' + (Encode $art.product) + '</text><g class="card-art-symbol" transform="translate(232 50) scale(1.38)">' + $art.symbol + '</g><text class="card-art-detail" x="28" y="278">' + (Encode $art.detail) + '</text></svg></div>'
}
function Topic-Diagram([string]$slug, [switch]$Thumbnail, [string]$Locale = 'en') {
    $v = $visuals.$slug
    if (-not $v -or @($v.nodes).Count -lt 3) { throw "Missing diagram definition: $slug" }
    $copy = if ($Locale -eq 'ko') { $koVisualText.topics.$slug } else { $v }
    $marker = 'arrow-' + $slug + $(if ($Thumbnail) { '-card' } else { '-article' })
    $edges = foreach ($e in $v.edges) {
        $dash = if ($e.dashed) { ' diagram-dashed' } else { '' }
        '<path class="diagram-edge' + $dash + '" marker-end="url(#' + $marker + ')" d="' + (Encode $e.d) + '"/><text class="diagram-edge-label" x="' + $e.x + '" y="' + $e.y + '">' + (Encode $e.label) + '</text>'
    }
    $nodes = foreach ($n in $v.nodes) {
        $accent = if ($n.accent) { ' diagram-accent' } else { '' }
        '<g class="diagram-node' + $accent + '" transform="translate(' + $n.x + ' ' + $n.y + ')"><rect width="170" height="80" rx="12"/><g transform="translate(12 12) scale(.7)">' + (Svg-Icon $n.icon) + '</g><text class="diagram-node-title" x="12" y="47">' + (Encode $n.title) + '</text><text class="diagram-node-detail" x="12" y="65">' + (Encode $n.detail) + '</text></g>'
    }
    $access = if ($Thumbnail) { 'aria-hidden="true" focusable="false"' } else { 'role="img" aria-label="' + (Encode ($copy.title + '. ' + $copy.caption)) + '"' }
    $boundary = ''
    if ($v.boundary) {
        $b = $v.boundary
        $boundary = '<rect class="diagram-boundary" x="' + $b.x + '" y="' + $b.y + '" width="' + $b.width + '" height="' + $b.height + '" rx="16"/><text class="diagram-kicker" x="' + ($b.x + 16) + '" y="' + ($b.y + 18) + '">' + (Encode $b.label) + '</text>'
    }
    $svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 344" ' + $access + '><defs><marker id="' + $marker + '" viewBox="0 0 8 8" refX="8" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="diagram-arrow" d="M0 0L8 4L0 8z"/></marker></defs><path class="diagram-guide" d="M24 32H696M24 324H696"/><text class="diagram-kicker" x="24" y="23">SYSTEM VIEW / ' + (Encode $slug.ToUpperInvariant().Replace('-', ' ')) + '</text>' + $boundary + ($edges -join '') + ($nodes -join '') + '</svg>'
    if ($Thumbnail) { return '<div class="topic-illustration">' + $svg + '</div>' }
    '<figure class="technical-visual"><div class="visual-heading"><span class="eyebrow">' + (Encode (Ui $Locale 'diagramEyebrow')) + '</span><h2 id="visual-overview">' + (Encode $copy.title) + '</h2></div><div class="visual-canvas" tabindex="0" role="region" aria-label="' + (Encode (Ui $Locale 'diagramScroll')) + '">' + $svg + '</div><figcaption>' + (Encode $copy.caption) + (Encode (Ui $Locale 'diagramNote')) + '</figcaption></figure>'
}
function Topic-Chart([string]$slug, [string]$body, [string]$Locale = 'en') {
    $c = $visuals.$slug.chart
    if (-not $c) { return $body }
    $copy = if ($Locale -eq 'ko') { $koVisualText.topics.$slug.chart } else { $c }
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
    $chart = '<figure class="technical-visual measurement-chart"><div class="visual-heading"><span class="eyebrow">' + (Encode (Ui $Locale 'chartEyebrow')) + '</span><h3>' + (Encode $copy.title) + '</h3><p>' + (Encode $copy.subtitle) + '</p></div><div class="visual-canvas" tabindex="0" role="region" aria-label="' + (Encode (Ui $Locale 'chartScroll')) + '"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 ' + $height + '" role="img" aria-label="' + (Encode ($copy.title + '. ' + $description)) + '"><text class="diagram-kicker" x="174" y="22">' + (Encode $c.unit.ToUpperInvariant()) + '</text>' + ($ticks -join '') + ($rows -join '') + '</svg></div><figcaption>' + (Encode $copy.caption) + '</figcaption></figure>'
    $pattern = '<h2 id="' + [regex]::Escape($c.after) + '">.*?</h2>'
    $match = [regex]::Match($body, $pattern)
    if (-not $match.Success) { throw "Chart section missing: $slug / $($c.after)" }
    $body.Insert($match.Index + $match.Length, $chart)
}
