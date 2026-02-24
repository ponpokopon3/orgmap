<#
server.ps1
A small local HTTP server using System.Net.HttpListener.
Features:
- Bind starting from `-StartPort` with fallback attempts.
- Serve files from a specified drive (e.g. Q:). 
- Return simple directory listing HTML for folders.
- Generate `index.json` on-the-fly when requested.
- Spawn a detached `watcher.ps1` to cleanup `subst` mapping after this server exits.
#>

param(
	[int]$StartPort = 8080,
	[string]$Drive = 'Q:'
)

function Get-ContentType {
	param([string]$path)
	switch -Regex ([System.IO.Path]::GetExtension($path).ToLower()) {
		'\.html$' { 'text/html; charset=utf-8' ; return }
		'\.json$' { 'application/json; charset=utf-8' ; return }
		'\.md$'   { 'text/markdown; charset=utf-8' ; return }
		'\.css$'  { 'text/css; charset=utf-8' ; return }
		'\.js$'   { 'application/javascript; charset=utf-8' ; return }
		default   { 'application/octet-stream' ; return }
	}
}

function Try-BindPort {
	param([int]$port)
	try {
		$listener = New-Object System.Net.HttpListener
		$listener.Prefixes.Add("http://localhost:$port/")
		$listener.Start()
		return $listener
	} catch {
		return $null
	}
}

function Serve-DirectoryHtml {
	param(
		[System.Net.HttpListenerResponse]$res,
		[string]$dirPath,
		[string]$urlBase
	)
	try {
		$entries = Get-ChildItem -Path $dirPath -File | Sort-Object Name
		$escapedBase = [System.Web.HttpUtility]::HtmlEncode($urlBase)
		$html = "<html><head><meta charset='utf-8'><title>Index of $escapedBase</title></head><body><h1>Index of $escapedBase</h1><ul>"
		foreach ($e in $entries) {
			$name = [System.Web.HttpUtility]::HtmlEncode($e.Name)
			$href = [System.Uri]::EscapeUriString($e.Name)
			$html += "<li><a href='$href'>$name</a></li>"
		}
		$html += "</ul></body></html>"
		$bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
		$res.ContentType = 'text/html; charset=utf-8'
		$res.ContentLength64 = $bytes.Length
		$res.OutputStream.Write($bytes, 0, $bytes.Length)
	} catch {
		$res.StatusCode = 500
	} finally {
		$res.Close()
	}
}

function Serve-File {
	param(
		[System.Net.HttpListenerResponse]$res,
		[string]$filePath
	)
	try {
		$bytes = [System.IO.File]::ReadAllBytes($filePath)
		$res.ContentType = Get-ContentType -path $filePath
		$res.ContentLength64 = $bytes.Length
		$res.OutputStream.Write($bytes, 0, $bytes.Length)
	} catch {
		$res.StatusCode = 500
	} finally {
		$res.Close()
	}
}

function Generate-IndexJson {
	param([string]$dirPath)
	try {
		$items = Get-ChildItem -Path $dirPath -File | Sort-Object Name | ForEach-Object { $_.Name }
		return $items | ConvertTo-Json -Depth 2
	} catch {
		return $null
	}
}

# --- bind listener with fallback ---
$maxAttempts = 20
$listener = $null
$boundPort = $StartPort
for ($i = 0; $i -lt $maxAttempts; $i++) {
	$p = $StartPort + $i
	$listener = Try-BindPort -port $p
	if ($listener) { $boundPort = $p; break }
}

if (-not $listener) {
	Write-Error "Failed to bind any port starting at $StartPort"
	exit 1
}

Write-Output "Listening on http://localhost:$boundPort/"
# open root URL (server will serve index.html if present) to reduce duplicate index.html loads
Start-Process "http://localhost:$boundPort/"

# spawn detached watcher to cleanup subst mapping after server exits
try {
	$watcherPath = Join-Path $PSScriptRoot 'watcher.ps1'
	$watcherArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$watcherPath,'-ParentPid',$PID,'-Drive',$Drive)
	Start-Process -FilePath powershell -ArgumentList $watcherArgs -WindowStyle Hidden -WorkingDirectory $PSScriptRoot | Out-Null
} catch {
	# ignore watcher spawn failures
}

# --- main loop ---
while ($listener.IsListening) {
	try {
		$context = $listener.GetContext()
	} catch {
		break
	}

	$req = $context.Request
	$res = $context.Response
	# Log incoming request for debugging duplicate loads
	try {
		$remote = $req.RemoteEndPoint.ToString()
	} catch {
		$remote = 'unknown'
	}
	Write-Output "[$(Get-Date -Format o)] REQUEST: $($req.HttpMethod) $($req.Url.AbsolutePath) from $remote"

	$rawPath = $req.Url.LocalPath
	$decodedPath = [System.Uri]::UnescapeDataString($rawPath).TrimStart('/')
	$fsPath = Join-Path "$Drive\" $decodedPath

	# directory request: if index.html exists in the directory, serve it (avoid double-load from / and /index.html)
	if ($rawPath.EndsWith('/') -or (Test-Path $fsPath -PathType Container)) {
		if (-not (Test-Path $fsPath)) {
			$res.StatusCode = 404
			$res.Close()
			continue
		}
		$indexFile = Join-Path $fsPath 'index.html'
		if (Test-Path $indexFile -PathType Leaf) {
			Write-Output "[$(Get-Date -Format o)] Serving index.html for directory $fsPath"
			Serve-File -res $res -filePath $indexFile
			continue
		}
		Serve-DirectoryHtml -res $res -directoryPath $fsPath -urlBase $rawPath
		continue
	}

	# serve file if exists
	if (Test-Path $fsPath -PathType Leaf) {
		Serve-File -res $res -filePath $fsPath
		continue
	}

	# if index.json requested, try generate
	if ($decodedPath -match '/?([^/]+/)*index\.json$' -or $decodedPath -ieq 'index.json') {
		$parent = Split-Path $fsPath -Parent
		if (Test-Path $parent) {
			$json = Generate-IndexJson -dirPath $parent
			if ($json -ne $null) {
				$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
				$res.ContentType = 'application/json; charset=utf-8'
				$res.ContentLength64 = $bytes.Length
				$res.OutputStream.Write($bytes, 0, $bytes.Length)
				$res.Close()
				continue
			}
		}
	}

	# not found
	$res.StatusCode = 404
	$res.Close()
}

$listener.Stop()
$listener.Close()

