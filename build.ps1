param([switch]$AllowPartial)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$output = Join-Path $root 'docs'
$expected = @('acr-streaming', 'ai-gateway', 'ai-gateway-existing', 'cilium-network-policy', 'codex', 'envoy-gateway', 'istio-gateway-api', 'translation-performance', 'ase-frontend-scaling', 'managed-instance', 'self-hosted-aca', 'content-safety-streaming', 'aks-confidential-vm', 'openai-foundry-migration', 'hosted-agent-latency', 'aks-hyperscale')
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Encode([string]$value) { [System.Net.WebUtility]::HtmlEncode($value) }
. (Join-Path $root 'visuals.ps1')
. (Join-Path $root 'portal-screenshots.ps1')
. (Join-Path $root 'localization.ps1')
function Write-Utf8([string]$path, [string]$value) {
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path)) | Out-Null
    [System.IO.File]::WriteAllText($path, $value, $utf8)
}
$topics = @(Get-ChildItem (Join-Path $root 'content') -Filter '*.json' | ForEach-Object {
    $topic = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($topic.slug -notin $expected) { throw "Unexpected topic: $($topic.slug)" }
    if ($topic.publishedOn) {
        $date = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($topic.publishedOn, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date)) { throw "Invalid publication date: $($topic.slug)" }
    }
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
} | Sort-Object @{Expression='publishedOn';Descending=$true}, category, title)
if (@($topics.slug | Select-Object -Unique).Count -ne $topics.Count) { throw 'Duplicate topic slug.' }
if (-not $AllowPartial -and $topics.Count -ne $expected.Count) {
    throw "Expected $($expected.Count) topics; found $($topics.Count). Missing: $($expected | Where-Object { $_ -notin $topics.slug })"
}
Read-KoreanVisualText
$koreanTopics = @{}
foreach ($topic in $topics) { $koreanTopics[$topic.slug] = Read-KoreanArticle $topic }
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
function Page([string]$title, [string]$description, [string]$assetPrefix, [string]$homeHref, [string]$locale, [string]$relativePage, [string]$main) {
    $isTopic = $relativePage.StartsWith('topics/')
    $enHref = if ($locale -eq 'en') { if ($isTopic) { "$($relativePage.Substring(7))" } else { 'index.html' } } else { if ($isTopic) { "../../$relativePage" } else { '../index.html' } }
    $koHref = if ($locale -eq 'ko') { if ($isTopic) { "$($relativePage.Substring(7))" } else { 'index.html' } } else { if ($isTopic) { "../ko/$relativePage" } else { 'ko/index.html' } }
    $enCurrent = if ($locale -eq 'en') { ' aria-current="page"' } else { '' }
    $koCurrent = if ($locale -eq 'ko') { ' aria-current="page"' } else { '' }
    $enCanonical = 'https://junpark12.github.io/azuretech/' + $(if ($relativePage -eq 'index.html') { '' } else { $relativePage })
    $koCanonical = 'https://junpark12.github.io/azuretech/ko/' + $(if ($relativePage -eq 'index.html') { '' } else { $relativePage })
    $canonical = if ($locale -eq 'ko') { $koCanonical } else { $enCanonical }
    return @"
<!doctype html>
<html lang="$locale">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
$theme
<title>$(Encode $title) | Azure Tech Field Notes</title>
<meta name="description" content="$(Encode $description)">
<link rel="canonical" href="$canonical">
<link rel="alternate" hreflang="en" href="$enCanonical">
<link rel="alternate" hreflang="ko" href="$koCanonical">
<link rel="alternate" hreflang="x-default" href="$enCanonical">
<link rel="stylesheet" href="${assetPrefix}assets/site.css">
<script src="${assetPrefix}assets/site.js" defer></script>
</head>
<body>
<a class="skip" href="#main">$(Encode (Ui $locale 'skip'))</a>
<header class="site-header"><a class="brand" href="$homeHref"><span class="brand-mark" aria-hidden="true">AT</span><span>Azure Tech<span class="brand-subtitle">FIELD NOTES</span></span></a><nav aria-label="$(Encode (Ui $locale 'site'))"><a href="$homeHref">$(Encode (Ui $locale 'allTopics'))</a><div class="language-switch" role="group" aria-label="$(Encode (Ui $locale 'language'))"><a class="language-link" href="$koHref" hreflang="ko" lang="ko"$koCurrent>&#54620;&#44397;&#50612;</a><a class="language-link" href="$enHref" hreflang="en" lang="en"$enCurrent>English</a></div><button id="theme-toggle" type="button">$(Encode (Ui $locale 'theme'))</button></nav></header>
$main
<footer><span>Azure Tech Field Notes</span><span>$(Encode (Ui $locale 'footer'))</span><span>$(Encode (Ui $locale 'edition')) &middot; $(Encode (Ui $locale 'editionDate'))</span></footer>
<div class="sr-only" id="status" role="status" aria-live="polite"></div>
</body></html>
"@
}
$resourceManifest = @()
# Resources are shared by both editions and copied exactly once.
foreach ($topic in $topics) {
    foreach ($file in $topic.downloads) {
        if (-not $file.path.StartsWith("downloads/$($topic.slug)/", [System.StringComparison]::Ordinal)) {
            throw "Resource path outside topic scope: $($file.path)"
        }
        $sourceFile = Resolve-Within $root $file.path
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "Missing resource: $($file.path)" }
        $destination = Resolve-Within $output $file.path
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination)) | Out-Null
        Copy-Item -LiteralPath $sourceFile -Destination $destination
        $resourceManifest += $file.path
    }
}
foreach ($locale in @('en','ko')) {
    $localeRoot = if ($locale -eq 'ko') { Join-Path $output 'ko' } else { $output }
    $indexAssetPrefix = if ($locale -eq 'ko') { '../' } else { '' }
    $articleAssetPrefix = if ($locale -eq 'ko') { '../../' } else { '../' }
    $localizedTopics = @($topics | ForEach-Object { if ($locale -eq 'ko') { $koreanTopics[$_.slug] } else { $_ } })
    $categories = @($topics.category | Select-Object -Unique)
    $cards = foreach ($topic in $localizedTopics) {
        $slug=Encode $topic.slug
        $resourceText=if (@($topic.downloads).Count) { (Ui $locale 'resourceCount') -f @($topic.downloads).Count } else { Ui $locale 'inlineExamples' }
        $enTopic=$topics | Where-Object {$_.slug -eq $topic.slug}
        $searchText="$($topic.title) $($topic.summary) $($topic.category) $($enTopic.title) $($koreanTopics[$topic.slug].title)"
        $cardDate=if($topic.publishedOn){' &middot; <time datetime="' + (Encode $topic.publishedOn) + '">' + (Encode $topic.publishedOn) + '</time>'}else{''}
        @"
<article class="topic-card" data-category="$(Encode $topic.category)" data-search="$(Encode $searchText)">
$(Topic-Diagram $topic.slug -Thumbnail -Locale $locale)
<span class="eyebrow">$(Encode $topic.category)$cardDate</span><h2><a href="topics/$slug.html">$(Encode $topic.title)</a></h2><p>$(Encode $topic.summary)</p><div class="card-bottom"><span>$(Encode $resourceText)</span><a href="topics/$slug.html" aria-label="$(Encode ((Ui $locale 'read') + ': ' + $topic.title))">$(Encode (Ui $locale 'read')) <span aria-hidden="true">&#8599;</span></a></div>
</article>
"@
    }
    $filterButtons=($categories | ForEach-Object { '<button type="button" class="filter" data-filter="' + (Encode $_) + '" aria-pressed="false">' + (Encode $_) + '</button>' }) -join ''
    $index=@"
<main id="main" class="home">
<section class="hero"><div class="hero-copy"><p class="eyebrow">$(Encode (Ui $locale 'eyebrow'))</p><h1>$(Ui $locale 'heroHtml')</h1><p class="lead">$(Encode (Ui $locale 'lead'))</p></div><div class="hero-stats" aria-label="$(Encode (Ui $locale 'collectionOverview'))"><div><strong>$($topics.Count.ToString('00'))</strong><span>$(Encode (Ui $locale 'topicGuides'))</span></div><div><strong>$($categories.Count.ToString('00'))</strong><span>$(Encode (Ui $locale 'technicalAreas'))</span></div><p>$(Ui $locale 'heroNotesHtml')</p></div></section>
<aside class="editorial-note" aria-label="$(Encode (Ui $locale 'disclaimerLabel'))"><strong>$(Encode (Ui $locale 'disclaimerTitle'))</strong><p>$(Encode (Ui $locale 'disclaimerText'))</p><p>$(Encode (Ui $locale 'pricingBefore'))<a href="topics/ase-frontend-scaling.html#billing">$(Encode (Ui $locale 'pricingLink'))</a>$(Encode (Ui $locale 'pricingAfter'))</p></aside>
<section aria-labelledby="browse-title"><div class="section-heading"><div><p class="eyebrow">$(Encode (Ui $locale 'collection'))</p><h2 id="browse-title">$(Encode (Ui $locale 'explore'))</h2></div><p id="result-count" role="status">$(Encode ((Ui $locale 'topicCount') -f $topics.Count))</p></div>
<div class="search-controls"><label for="search">$(Encode (Ui $locale 'search'))<input id="search" type="search" placeholder="$(Encode (Ui $locale 'searchPlaceholder'))" autocomplete="off"></label><div class="filters" role="group" aria-label="$(Encode (Ui $locale 'filter'))"><button type="button" class="filter active" data-filter="All" aria-pressed="true">$(Encode (Ui $locale 'allTopics'))</button>$filterButtons</div></div>
<div class="topic-grid">$($cards -join "`n")</div><p id="empty-state" hidden>$(Encode (Ui $locale 'empty'))</p></section>
<section class="about-grid" aria-label="$(Encode (Ui $locale 'about'))"><div><h2>$(Encode (Ui $locale 'designedTitle'))</h2><p>$(Encode (Ui $locale 'designedText'))</p></div><div><h2>$(Encode (Ui $locale 'sharingTitle'))</h2><p>$(Encode (Ui $locale 'sharingText'))</p></div></section>
</main>
"@
    Write-Utf8 (Join-Path $localeRoot 'index.html') (Page (Ui $locale 'homeTitle') (Ui $locale 'homeDescription') $indexAssetPrefix 'index.html' $locale 'index.html' $index)
    foreach ($topic in $localizedTopics) {
        $headings=[regex]::Matches($topic.bodyHtml,'<h2\b[^>]*\bid="([^"]+)"[^>]*>(.*?)</h2>','Singleline,IgnoreCase')
        $ids=@($headings | ForEach-Object {$_.Groups[1].Value})
        if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { throw "Duplicate section ID in $($topic.slug)" }
        if ('resources' -in $ids -or 'editorial-notes' -in $ids -or 'visual-overview' -in $ids) { throw "Reserved section ID in $($topic.slug)" }
        $tocItems=($headings | ForEach-Object { '<li><a href="#' + (Encode $_.Groups[1].Value) + '">' + (Encode ([System.Net.WebUtility]::HtmlDecode([regex]::Replace($_.Groups[2].Value,'<[^>]+>','')))) + '</a></li>' }) -join ''
        $downloads=foreach($file in $topic.downloads) { '<li><a download href="' + $articleAssetPrefix + (Encode $file.path) + '">' + (Encode $file.label) + '</a><p>' + (Encode $file.description) + '</p></li>' }
        $resourceSection=if (@($topic.downloads).Count) { '<p>' + (Encode (Ui $locale 'resourceIntro')) + '</p><ul class="download-list">' + ($downloads -join '') + '</ul>' } else { '<p>' + (Encode (Ui $locale 'noResources')) + '</p>' }
        $omissions=($topic.omissions | ForEach-Object { '<li>' + (Encode $_) + '</li>' }) -join ''
        $sourceTitles=($topic.sourceDocuments | ForEach-Object { '<li>' + (Encode $_) + '</li>' }) -join ''
        $body=if($locale -eq 'ko'){Korean-BodyLinks $topic.bodyHtml}else{$topic.bodyHtml}
        $body=Topic-Chart $topic.slug $body $locale
        $body=Add-PortalScreenshots $topic.slug $body $locale $articleAssetPrefix
        $articleDate=if($topic.publishedOn){'<time datetime="' + (Encode $topic.publishedOn) + '">' + (Encode $topic.publishedOn) + '</time>'}else{Encode (Ui $locale 'archiveEditionDate')}
        $article=@"
<main id="main" class="topic-layout">
<aside class="toc"><details open><summary>$(Encode (Ui $locale 'toc'))</summary><ol><li><a href="#visual-overview">$(Encode (Ui $locale 'architecture'))</a></li>$tocItems<li><a href="#resources">$(Encode (Ui $locale 'resources'))</a></li><li><a href="#editorial-notes">$(Encode (Ui $locale 'editorial'))</a></li></ol></details><a class="back-link" href="../index.html">&#8592; $(Encode (Ui $locale 'allTopics'))</a></aside>
<article class="article"><header class="article-header"><p class="eyebrow">$(Encode $topic.category) / $(Encode (Ui $locale 'fieldNote'))</p><h1>$(Encode $topic.title)</h1><p class="lead">$(Encode $topic.summary)</p><div class="article-meta"><span>$(Encode (Ui $locale 'edition'))</span><span>$(Encode (Ui $locale 'parameterized'))</span><span>$articleDate</span></div><p class="translation-note">$(Encode (Ui $locale 'translationNote'))</p></header>
<aside class="editorial-note"><strong>$(Encode (Ui $locale 'evidenceTitle'))</strong> $(Encode (Ui $locale 'evidenceText'))</aside>
$(Topic-Diagram $topic.slug -Locale $locale)
<div class="article-body">$body<h2 id="resources">$(Encode (Ui $locale 'resources'))</h2>$resourceSection<h2 id="editorial-notes">$(Encode (Ui $locale 'editorial'))</h2><p>$(Encode (Ui $locale 'sourceIntro'))</p><ul>$sourceTitles</ul><ul>$omissions</ul><p>$(Encode (Ui $locale 'noSecrets'))</p></div>
</article></main>
"@
        Write-Utf8 (Join-Path $localeRoot "topics\$($topic.slug).html") (Page $topic.title $topic.summary $articleAssetPrefix '../index.html' $locale "topics/$($topic.slug).html" $article)
    }
}
Write-Utf8 (Join-Path $output '.nojekyll') ''
$manifest = @{
    edition = '2026-10'
    topicCount = $topics.Count
    languages = @('en','ko')
    pageCount = 2 * ($topics.Count + 1)
    topics = @($topics | ForEach-Object { @{ slug = $_.slug; title = $_.title; titleKo = $koreanTopics[$_.slug].title; category = $_.category; publishedOn = $_.publishedOn; sourceDocumentCount = @($_.sourceDocuments).Count; resourceCount = @($_.downloads).Count; paths = @{ en = "topics/$($_.slug).html"; ko = "ko/topics/$($_.slug).html" } } })
    resources = @($resourceManifest | Sort-Object -Unique)
    portalScreenshots = @($portalScreenshots.images | ForEach-Object { @{ id=$_.id; topic=$_.topic; path=$_.path; capturedOn=(Get-PortalCaptureDate $_) } })
}
Write-Utf8 (Join-Path $output 'manifest.json') ($manifest | ConvertTo-Json -Depth 6)
Write-Output "Built $($topics.Count) topics in English and Korean, $($manifest.pageCount) pages, and $($resourceManifest.Count) shared resources in $output"
