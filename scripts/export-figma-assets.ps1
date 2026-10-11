param(
  [string] $Token = $env:FIGMA_TOKEN,
  [string] $FileKey = '8oMdscx5vXoDNcVsTOKv4N',
  [string] $JsonPath = 'C:\Users\HONOR\Desktop\YGRIK-STUDIO.json',
  [string] $AssetRoot = 'assets\figma',
  [switch] $Offline
)

# Builds a resource manifest from the local Figma JSON.  When a token is
# supplied through FIGMA_TOKEN, it also downloads original image fills and
# exports only explicitly graphical composition nodes.  Tokens are never
# printed or written to disk.
$ErrorActionPreference = 'Stop'
$doc = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
$originals = Join-Path $AssetRoot 'originals'
$renders = Join-Path $AssetRoot 'renders'
New-Item -ItemType Directory -Force -Path $originals, $renders | Out-Null

$images = [System.Collections.Generic.List[object]]::new()
$rendersToExport = [System.Collections.Generic.List[object]]::new()

function Get-VisualInfo($node) {
  $box = $node.absoluteBoundingBox
  [ordered]@{
    x = if ($box) { $box.x } else { $null }
    y = if ($box) { $box.y } else { $null }
    width = if ($box) { $box.width } else { $null }
    height = if ($box) { $box.height } else { $null }
    rotation = $node.rotation
    opacity = $node.opacity
    cornerRadius = $node.cornerRadius
    effects = @($node.effects)
    clipsContent = $node.clipsContent
  }
}

function Walk($node, [string] $parentId = '', [string] $parentName = '') {
  if (-not $node) { return }
  $visual = Get-VisualInfo $node
  $fills = @($node.fills | Where-Object { $_.type -eq 'IMAGE' })
  foreach ($fill in $fills) {
    $images.Add([ordered]@{
      nodeId = $node.id; nodeName = $node.name; nodeType = $node.type
      parentId = $parentId; parentName = $parentName; imageRef = $fill.imageRef
      exportType = 'original'; path = if ($fill.imageRef) { ('originals/{0}.png' -f $fill.imageRef) } else { $null }
      scaleMode = $fill.scaleMode; imageTransform = $fill.imageTransform
      visual = $visual; includedEffects = $false
    })
  }

  # A render is reserved only for an explicitly exportable graphic, a mask,
  # or a vector/boolean operation with visual effects.  Frames and ordinary
  # groups are intentionally excluded: exporting them would bake text/cards.
  $children = @($node.children)
  $hasExportSettings = $null -ne $node.exportSettings -and @($node.exportSettings).Count -gt 0
  $isComposition = $hasExportSettings -or $node.isMask -eq $true -or
    (($node.type -in @('VECTOR','BOOLEAN_OPERATION')) -and @($node.effects).Count -gt 0)
  if ($isComposition -and $node.type -notin @('DOCUMENT','PAGE','FRAME','SECTION')) {
    $safeId = ($node.id -replace ':','-')
    $rendersToExport.Add([ordered]@{
      nodeId = $node.id; nodeName = $node.name; nodeType = $node.type
      parentId = $parentId; parentName = $parentName; imageRef = $null
      exportType = 'rendered'; path = ('renders/{0}.png' -f $safeId)
      scale = 2; format = if ($node.type -eq 'VECTOR' -and @($node.effects).Count -eq 0) { 'svg' } else { 'png' }
      scaleMode = $null; imageTransform = $null; visual = $visual; includedEffects = $true
    })
  }
  foreach ($child in $children) { Walk $child $node.id $node.name }
}

Walk $doc.document
$resources = @($images) + @($rendersToExport)

function Invoke-FigmaGet([string] $Uri) {
  $attempt = 0
  while ($true) {
    try { return Invoke-RestMethod -Headers @{ 'X-Figma-Token' = $Token } -Uri $Uri -Method Get }
    catch {
      $attempt++
      $status = $_.Exception.Response.StatusCode.value__
      if (($status -eq 429 -or $status -ge 500) -and $attempt -le 5) { Start-Sleep -Seconds ([Math]::Min(60, 2 * [Math]::Pow(2, $attempt))); continue }
      throw
    }
  }
}

if (-not $Offline -and $Token) {
  $urlMap = (Invoke-FigmaGet "https://api.figma.com/v1/files/$FileKey/images").meta.images
  foreach ($asset in $images | Group-Object imageRef | ForEach-Object { $_.Group[0] }) {
    $uri = $urlMap.($asset.imageRef); if (-not $uri) { continue }
    $target = Join-Path $AssetRoot $asset.path
    if (-not (Test-Path $target)) { Invoke-WebRequest -Uri $uri -OutFile $target }
  }
  $chunks = @($rendersToExport | ForEach-Object { $_.nodeId } | Select-Object -Unique | ForEach-Object -Begin { $a=@() } -Process { $a += $_; if($a.Count -eq 20){ ,$a; $a=@() } } -End { if($a.Count){,$a} })
  foreach ($chunk in $chunks) {
    $ids = [uri]::EscapeDataString(($chunk -join ','))
    $response = Invoke-FigmaGet "https://api.figma.com/v1/images/$FileKey?ids=$ids&format=png&scale=2"
    foreach ($nodeId in $chunk) {
      $asset = @($rendersToExport | Where-Object nodeId -eq $nodeId)[0]; $uri = $response.images.$nodeId
      if ($asset -and $uri) { Invoke-WebRequest -Uri $uri -OutFile (Join-Path $AssetRoot $asset.path) }
    }
  }
}

[ordered]@{
  fileKey = $FileKey
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  source = 'local Figma JSON'
  exportStatus = if ($Offline -or -not $Token) { 'manifest-only: API credential unavailable' } else { 'download attempted' }
  resources = $resources
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $AssetRoot 'manifest.json') -Encoding utf8

Write-Output ("Manifest created: {0} image fills, {1} graphical composition candidates." -f $images.Count, $rendersToExport.Count)
