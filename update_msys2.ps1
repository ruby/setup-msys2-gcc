<#
  Original code by MSP-Greg
  Updates Actions Windows runner's MSYS2 packages, also adding common build tools.
  Exits on error, sets ENV['Create7z'] equal to 'yes' if an updated 7z file
  needs to be created and uploaded.
#>

$dash = "$([char]0x2500)"
$line = $($dash * 50)
$yel  = "`e[93m"
$grn  = "`e[92m"
$rst  = "`e[0m"

function Array-2-Column($ary, $wid, $hdr) {
  $pad = [int][Math]::Floor(($wid - $hdr.length - 5)/2)

  $hdr_pad = ($pad -gt 0) ? "$($dash * $pad) $hdr $($dash * $pad)" : $hdr

  echo "`n$yel$($hdr_pad.PadRight($wid))$hdr_pad$rst"

  $mod = $ary.length % 2
  $split  = [int][Math]::Floor($ary.length/2)
  $offset = $split + $mod
  for ($i = 0; $i -lt $split; $i ++) {
    echo "$($ary[$i].PadRight($wid))$($ary[$i + $offset])"
  }
  if ($mod -eq 1) { echo $ary[$split] }
}

function Run-Check($msg, $cmd) {
  echo "`n$yel$line $msg$rst"
  if (!$cmd) { $cmd = $msg }
  iex $cmd
  if ($LastExitCode -and $LastExitCode -ne 0) { exit 1 }
}

$current_pkgs = $(pacman -Q | grep -v ^mingw-w64- | sort) -join "`n"

Run-Check 'pacman -Syyuu --noconfirm'
taskkill /f /fi "MODULES eq msys-2.0.dll"

Run-Check 'pacman --noconfirm -Syuu (2nd pass)' 'pacman -Syuu  --noconfirm'
taskkill /f /fi "MODULES eq msys-2.0.dll"

$pkgs = 'autoconf-wrapper autogen automake-wrapper bison diffutils libtool m4 make patch texinfo texinfo-tex compression'
Run-Check "Install MSYS2 packages$rst`n$yel$pkgs" "pacman -S --noconfirm --needed --noprogressbar $pkgs"

Run-Check 'Clean packages' 'pacman -Scc --noconfirm'

$updated_pkgs = $(pacman -Q | grep -v ^mingw-w64- | sort)

Array-2-Column $updated_pkgs 38 'Installed MSYS2 Packages'

$updated_pkgs = $updated_pkgs -join "`n"

if ($current_pkgs -eq $updated_pkgs) {
  echo "Create7z=no"  | Out-File -FilePath $env:GITHUB_ENV -Append
  echo "`n** No update needed **`n"
} else {
  echo "Create7z=yes" | Out-File -FilePath $env:GITHUB_ENV -Append
  echo "`n$grn** Creating and Uploading MSYS2 tools 7z **$rst`n"
}
