param(
  [Parameter(Mandatory = $true)] [string] $Token,
  [string] $FileKey = '8oMdscx5vXoDNcVsTOKv4N',
  [string] $OutputDirectory = 'image/figma-originals',
  [int] $StartAt = 0,
  [int] $Limit = 10
)

# Downloads image fills only. It deliberately never renders a parent node,
# because node renders can include text, cards, masks, or other child layers.
$ErrorActionPreference = 'Stop'
$headers = @{ 'X-Figma-Token' = $Token }
$figmaFile = Get-Content -LiteralPath 'C:\Users\HONOR\Desktop\YGRIK-STUDIO.json' -Raw | ConvertFrom-Json
$imageNodes = [System.Collections.Generic.List[object]]::new()

function Find-ImageNodes($node) {
  if ($null -eq $node) { return }
  $imageFills = @($node.fills | Where-Object { $_.type -eq 'IMAGE' })
  foreach ($fill in $imageFills) {
    $imageNodes.Add([pscustomobject]@{
      nodeId = $node.id
      nodeName = $node.name
      imageRef = $fill.imageRef
      bounds = $node.absoluteBoundingBox
      rotation = $node.rotation
      scaleMode = $fill.scaleMode
      imageTransform = $fill.imageTransform
    })
  }
  foreach ($child in @($node.children)) { Find-ImageNodes $child }
}
Find-ImageNodes $figmaFile.document

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$refs = @($imageNodes.imageRef | Select-Object -Unique | Select-Object -Skip $StartAt -First $Limit)
$response = Invoke-RestMethod -Headers $headers -Uri "https://api.figma.com/v1/files/$FileKey/images" -Method Get
$urls = $response.meta.images
$assets = [System.Collections.Generic.List[object]]::new()

foreach ($ref in $refs) {
  $url = $urls.($ref)
  if (-not $url) { Write-Warning "Figma did not return an original image for $ref"; continue }
  $filename = "$ref.png"
  $relativePath = ($OutputDirectory + '/' + $filename).Replace('\','/')
  try { Invoke-WebRequest -Uri $url -OutFile (Join-Path $OutputDirectory $filename) }
  catch { Write-Warning ("Could not download image {0}: {1}" -f $ref, $_.Exception.Message); continue }
  $assets.Add([pscustomobject]@{
    imageRef = $ref
    sourceNodes = @($imageNodes | Where-Object { $_.imageRef -eq $ref } | ForEach-Object { $_.nodeId })
    renderPath = $relativePath
  })
}

[pscustomobject]@{
  fileKey = $FileKey
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  assets = $assets
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath 'figma-originals-manifest.json' -Encoding utf8

Write-Output ("Exported {0} original image fills without parent blocks." -f $assets.Count)
