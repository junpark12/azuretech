param([switch]$AllowPartial)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$output = Join-Path $root 'docs'
$expected = @('acr-streaming', 'ai-gateway', 'ai-gateway-existing', 'cilium-network-policy', 'codex', 'envoy-gateway', 'istio-gateway-api', 'translation-performance', 'ase-frontend-scaling', 'managed-instance', 'self-hosted-aca', 'content-safety-streaming')
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Encode([string]$value) { [System.Net.WebUtility]::HtmlEncode($value) }
. (Join-Path $root 'visuals.ps1')
. (Join-Path $root 'portal-screenshots.ps1')
function Write-Utf8([string]$path, [string]$value) {
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path)) | Out-Null
    [System.IO.File]::WriteAllText($path, $value, $utf8)
}
function Resolve-Within([string]$base, [string]$relative) {
    if ([System.IO.Path]::IsPathRooted($relative)) { throw "Absolute path not allowed: $relative" }
    $prefix = [System.IO.Path]::GetFullPath($base).TrimEnd('\') + '\'
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $base $relative.Replace('/', '\')))
    if (-not $resolved.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes allowed directory: $relative"
    }
    return $resolved
}
$topics = @(Get-ChildItem (Join-Path $root 'content') -Filter '*.json' | ForEach-Object {
    $topic = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($topic.slug -notin $expected) { throw "Unexpected topic: $($topic.slug)" }
    if ($topic.bodyFile) {
        $bodyPath = Resolve-Within (Join-Path $root 'content') $topic.bodyFile
        $topic | Add-Member -NotePropertyName bodyHtml -NotePropertyValue (Get-Content $bodyPath -Raw -Encoding UTF8) -Force
    }
    if (-not $topic.title -or -not $topic.summary -or -not $topic.bodyHtml -or -not $topic.sourceDocuments) {
        throw "Incomplete topic: $($topic.slug)"
    }
    if ($topic.bodyHtml -match '<\s*(script|iframe|object|embed|style|img|form)\b' -or $topic.bodyHtml -match '<[^>]+\son[a-z]+\s*=') {
        throw "Active or unreviewed embedded content in $($topic.slug)"
    }
    $topic
} | Sort-Object category, title)
if (@($topics.slug | Select-Object -Unique).Count -ne $topics.Count) { throw 'Duplicate topic slug.' }
if (-not $AllowPartial -and $topics.Count -ne $expected.Count) {
    throw "Expected $($expected.Count) topics; found $($topics.Count). Missing: $($expected | Where-Object { $_ -notin $topics.slug })"
}
foreach ($image in $portalScreenshots.images) {
    if ($image.path -notmatch '^assets/portal/[a-z0-9-]+\.png$') { throw "Invalid portal image path: $($image.path)" }
    Test-PortalImage $image.path
}
foreach ($file in Get-ChildItem (Join-Path $root 'assets') -Recurse -File) {
    if ($file.Extension -eq '.png') {
        Test-PortalImage ('assets/' + $file.FullName.Substring((Join-Path $root 'assets').Length + 1).Replace('\','/'))
    }
}
if (Test-Path $output) {
    # Only this generated directory is replaced; source and downloads remain untouched.
    Remove-Item -LiteralPath $output -Recurse -Force
}
[System.IO.Directory]::CreateDirectory((Join-Path $output 'assets')) | Out-Null
Copy-Item (Join-Path $root 'assets\*') (Join-Path $output 'assets') -Recurse
$theme = @'
<script>
  (() => {
    const param = new URLSearchParams(window.location.search).get("scoutTheme");
    const theme =
      param || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    document.documentElement.setAttribute("data-theme", theme);
  })();
</script>
'@
function Page([string]$title, [string]$description, [string]$prefix, [string]$main) {
    return @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
$theme
<title>$(Encode $title) | Azure Tech Field Notes</title>
<meta name="description" content="$(Encode $description)">
<link rel="stylesheet" href="${prefix}assets/site.css">
<script src="${prefix}assets/site.js" defer></script>
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<header class="site-header"><a class="brand" href="${prefix}index.html"><span class="brand-mark" aria-hidden="true">AT</span><span>Azure Tech<span class="brand-subtitle">FIELD NOTES</span></span></a><nav aria-label="Site"><a href="${prefix}index.html">All topics</a><button id="theme-toggle" type="button" aria-label="Switch color theme">Switch theme</button></nav></header>
$main
<footer><span>Azure Tech Field Notes</span><span>Independent technical notes. Not an official Microsoft publication.</span><span>English edition &middot; September 2026</span></footer>
<div class="sr-only" id="status" role="status" aria-live="polite"></div>
</body></html>
"@
}
$cards = foreach ($topic in $topics) {
    $slug = Encode $topic.slug
    $category = Encode $topic.category
    $title = Encode $topic.title
    $summary = Encode $topic.summary
    $downloadCount = @($topic.downloads).Count
    $resources = if ($downloadCount -eq 0) { 'In-page examples' } else { "$downloadCount resource files" }
    @"
<article class="topic-card" data-category="$category" data-search="$(Encode "$($topic.title) $($topic.summary) $($topic.category)")">
$(Topic-Diagram $topic.slug -Thumbnail)
<span class="eyebrow">$category</span><h2><a href="topics/$slug.html">$title</a></h2><p>$summary</p><div class="card-bottom"><span>$resources</span><a href="topics/$slug.html" aria-label="Read $title">Read field note <span aria-hidden="true">&#8599;</span></a></div>
</article>
"@
}
$categories = @($topics.category | Select-Object -Unique)
$filterButtons = ($categories | ForEach-Object { '<button type="button" class="filter" data-filter="' + (Encode $_) + '" aria-pressed="false">' + (Encode $_) + '</button>' }) -join ''
$index = @"
<main id="main" class="home">
<section class="hero"><div class="hero-copy"><p class="eyebrow">AZURE / APPLIED ENGINEERING</p><h1>From investigation<br>to implementation.</h1><p class="lead">Practical field notes on AI gateways, Kubernetes, App Service, and GitHub automation. Procedures, measured results, and the caveats that matter.</p></div><div class="hero-stats" aria-label="Collection overview"><div><strong>$($topics.Count.ToString('00'))</strong><span>topic guides</span></div><div><strong>$($categories.Count.ToString('00'))</strong><span>technical areas</span></div><p>English guides<br>Parameterized examples<br>Source-derived downloads</p></div></section>
<aside class="editorial-note" aria-label="Important disclaimer"><strong>Important disclaimer: observations are not guarantees.</strong><p>Some articles report measurements and behavior observed in specific test environments. Results may vary by configuration, region, service version, and time. They are not guaranteed and do not constitute official Microsoft guidance or a service-level agreement (SLA).</p><p>In particular, the <a href="topics/ase-frontend-scaling.html#billing">ASE v3 front-end pricing analysis</a> is an interpretation of observed billing data, not an official Microsoft pricing statement. Confirm current documentation, pricing, and your agreement before making design or cost decisions. Replace placeholders locally and check permissions before using any example.</p></aside>
<section aria-labelledby="browse-title"><div class="section-heading"><div><p class="eyebrow">THE COLLECTION</p><h2 id="browse-title">Explore the field notes</h2></div><p id="result-count" role="status">$($topics.Count) topics</p></div>
<div class="search-controls"><label for="search">Search topics<input id="search" type="search" placeholder="Try gateway, scaling, private endpoint..." autocomplete="off"></label><div class="filters" role="group" aria-label="Filter by technical area"><button type="button" class="filter active" data-filter="All" aria-pressed="true">All topics</button>$filterButtons</div></div>
<div class="topic-grid">$($cards -join "`n")</div><p id="empty-state" hidden>No topics match your search. Try another term or choose All topics.</p></section>
<section class="about-grid" aria-label="About this edition"><div><h2>Designed to be used</h2><p>Each topic brings related technical notes together in one page, with a section index, copyable examples, and companion downloads when available.</p></div><div><h2>Prepared for public sharing</h2><p>Environment identifiers are replaced with variables or placeholders. Original private screenshots, customer assessments, and unavailable local files are not distributed.</p></div></section>
</main>
"@
Write-Utf8 (Join-Path $output 'index.html') (Page 'Home' 'English Azure engineering guides, measured findings, and parameterized resources.' '' $index)
$resourceManifest = @()
foreach ($topic in $topics) {
    $headings = [regex]::Matches($topic.bodyHtml, '<h2\b[^>]*\bid="([^"]+)"[^>]*>(.*?)</h2>', 'Singleline,IgnoreCase')
    $ids = @($headings | ForEach-Object { $_.Groups[1].Value })
    if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { throw "Duplicate section ID in $($topic.slug)" }
    if ('resources' -in $ids -or 'editorial-notes' -in $ids -or 'visual-overview' -in $ids) { throw "Reserved section ID in $($topic.slug)" }
    $tocItems = ($headings | ForEach-Object {
        '<li><a href="#' + (Encode $_.Groups[1].Value) + '">' + (Encode ([System.Net.WebUtility]::HtmlDecode([regex]::Replace($_.Groups[2].Value, '<[^>]+>', '')))) + '</a></li>'
    }) -join ''
    $downloads = foreach ($file in $topic.downloads) {
        if (-not $file.path.StartsWith("downloads/$($topic.slug)/", [System.StringComparison]::Ordinal)) {
            throw "Resource path outside topic scope: $($file.path)"
        }
        $sourceFile = Resolve-Within $root $file.path
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "Missing resource: $($file.path)" }
        $destination = Resolve-Within $output $file.path
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination)) | Out-Null
        Copy-Item -LiteralPath $sourceFile -Destination $destination
        $resourceManifest += $file.path
        '<li><a download href="../' + (Encode $file.path) + '">' + (Encode $file.label) + '</a><p>' + (Encode $file.description) + '</p></li>'
    }
    $resourceSection = if (@($topic.downloads).Count -gt 0) {
        '<p>Source-derived, parameterized resources. Review every placeholder, permission, dependency, and deployment effect before use. These files are not a one-click deployment.</p><ul class="download-list">' + ($downloads -join '') + '</ul>'
    } else {
        '<p>No standalone companion files are distributed for this topic. Use the in-page examples and review the editorial notes below for source availability.</p>'
    }
    $omissions = ($topic.omissions | ForEach-Object { '<li>' + (Encode $_) + '</li>' }) -join ''
    $sourceTitles = ($topic.sourceDocuments | ForEach-Object { '<li>' + (Encode $_) + '</li>' }) -join ''
    $article = @"
<main id="main" class="topic-layout">
<aside class="toc"><details open><summary>On this page</summary><ol><li><a href="#visual-overview">Architecture at a glance</a></li>$tocItems<li><a href="#resources">Resources</a></li><li><a href="#editorial-notes">Editorial notes</a></li></ol></details><a class="back-link" href="../index.html">&#8592; All topics</a></aside>
<article class="article"><header class="article-header"><p class="eyebrow">$(Encode $topic.category) / FIELD NOTE</p><h1>$(Encode $topic.title)</h1><p class="lead">$(Encode $topic.summary)</p><div class="article-meta"><span>English edition</span><span>Parameterized examples</span><span>September 2026</span></div></header>
<aside class="editorial-note"><strong>Environment-specific evidence.</strong> Measurements and preview behavior reflect the source investigation. They are not current service guarantees. All configuration values must be supplied for your own environment.</aside>
$(Topic-Diagram $topic.slug)
<div class="article-body">$(Add-PortalScreenshots $topic.slug (Topic-Chart $topic.slug $topic.bodyHtml))<h2 id="resources">Resources</h2>$resourceSection<h2 id="editorial-notes">Editorial notes</h2><p>This page consolidates the following source documents into an English technical guide:</p><ul>$sourceTitles</ul><ul>$omissions</ul><p>No original credentials or private repository links are included. Do not put populated configuration files or copied production outputs back into this public site.</p></div>
</article></main>
"@
    Write-Utf8 (Join-Path $output "topics\$($topic.slug).html") (Page $topic.title $topic.summary '../' $article)
}
Write-Utf8 (Join-Path $output '.nojekyll') ''
$manifest = @{
    edition = '2026-09'
    topicCount = $topics.Count
    topics = @($topics | ForEach-Object { @{ slug = $_.slug; title = $_.title; category = $_.category; sourceDocumentCount = @($_.sourceDocuments).Count; resourceCount = @($_.downloads).Count } })
    resources = @($resourceManifest | Sort-Object -Unique)
    portalScreenshots = @($portalScreenshots.images | ForEach-Object { @{ id=$_.id; topic=$_.topic; path=$_.path; capturedOn=$portalScreenshots.capturedOn } })
}
Write-Utf8 (Join-Path $output 'manifest.json') ($manifest | ConvertTo-Json -Depth 6)
Write-Output "Built $($topics.Count) topics and $($resourceManifest.Count) resource links in $output"
