param([int]$Port = 8765)
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'docs'))
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Output "Preview: http://localhost:$Port/azuretech/"
$types = @{ '.html'='text/html; charset=utf-8'; '.css'='text/css; charset=utf-8'; '.js'='text/javascript; charset=utf-8'; '.json'='application/json; charset=utf-8'; '.xml'='application/xml; charset=utf-8'; '.yaml'='text/plain; charset=utf-8'; '.yml'='text/plain; charset=utf-8'; '.py'='text/plain; charset=utf-8'; '.http'='text/plain; charset=utf-8'; '.sh'='text/plain; charset=utf-8'; '.ps1'='text/plain; charset=utf-8'; '.bicep'='text/plain; charset=utf-8' }
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $response = $context.Response
        try {
            $relative = [System.Uri]::UnescapeDataString($context.Request.Url.AbsolutePath)
            if (-not $relative.StartsWith('/azuretech/')) {
                $response.StatusCode = 404
                continue
            }
            $relative = $relative.Substring('/azuretech/'.Length)
            if (-not $relative -or $relative.EndsWith('/')) { $relative += 'index.html' }
            $file = [System.IO.Path]::GetFullPath((Join-Path $root $relative.Replace('/', '\')))
            if (-not $file.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase) -or -not [System.IO.File]::Exists($file)) {
                $response.StatusCode = 404
                continue
            }
            $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
            $response.ContentType = if ($types.ContainsKey($extension)) { $types[$extension] } else { 'application/octet-stream' }
            $response.Headers.Add('X-Content-Type-Options', 'nosniff')
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $response.ContentLength64 = $bytes.Length
            if ($context.Request.HttpMethod -ne 'HEAD') { $response.OutputStream.Write($bytes, 0, $bytes.Length) }
        }
        finally { $response.Close() }
    }
}
finally { $listener.Stop(); $listener.Close() }
