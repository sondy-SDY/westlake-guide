param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z]$')][string]$DriveLetter)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$volume=Get-Volume -DriveLetter $DriveLetter
if($volume.FileSystem -ne 'FAT32' -or $volume.DriveType -ne 'Removable'){throw 'Target must be a removable FAT32 volume'}
$target=$DriveLetter+':\'
$manifest=Get-Content -Raw -LiteralPath (Join-Path $root 'reports/assets.json') | ConvertFrom-Json
$backup=Join-Path $root ('build/card-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
$records=@()
# Retire the superseded 1024x600 interface pages: the FPGA draws the whole
# 1024x600 interface now, so only the 640x480 cards are read from the volume.
# 图片已改裸 RGB565（PICxx.DAT），旧的 BMP 留在卡上会被误当成有效卡片，一并清掉
$stale = @('UI00.BMP','UI01.BMP','UI02.BMP','UI03.BMP','UI04.BMP','UI05.BMP')
$stale += @(Get-ChildItem -LiteralPath $target -Filter 'PIC*.BMP' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
foreach($old in $stale){
 $p=Join-Path $target $old
 if(Test-Path -LiteralPath $p){
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  Copy-Item -LiteralPath $p -Destination (Join-Path $backup $old) -Force
  Remove-Item -LiteralPath $p -Force
  Write-Output ('retired '+$old)
 }
}
foreach($entry in $manifest.files){
 $src=Join-Path $root ('card/'+$entry.name)
 $dst=Join-Path $target $entry.name
 $hash=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLower()
 if($hash -ne $entry.sha256){throw ('Source checksum mismatch: '+$entry.name)}
 if(Test-Path -LiteralPath $dst){
  $old=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower()
  if($old -ne $hash){
   New-Item -ItemType Directory -Force -Path $backup | Out-Null
   Copy-Item -LiteralPath $dst -Destination (Join-Path $backup $entry.name)
  }
 }
 Copy-Item -LiteralPath $src -Destination $dst -Force
 $verified=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower()
 if($verified -ne $hash){throw ('Card verification failed: '+$entry.name)}
 $records+=@{name=$entry.name;bytes=$entry.bytes;sha256=$verified}
}
@{target=$target;verified_at=(Get-Date).ToString('o');files=$records;method='filesystem copy and SHA256 readback; no formatting or raw writes'} |
 ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $root 'reports/card_deployment.json')
Write-Output ('Verified '+$records.Count+' files on '+$target+'; unrelated files preserved.')
