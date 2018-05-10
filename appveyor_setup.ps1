# PowerShell script for updating MSYS2 / MinGW, installing OpenSSL and other packages
# Code by MSP-Greg, see https://github.com/MSP-Greg/appveyor-utilities

#————————————————————————————————————————————————————————————————————————————————— Constants
#MinGW
$msys2 = 'C:\msys64\usr\bin'

# Download locations
$ri1_dl   = 'https://dl.bintray.com/oneclick/OpenKnapsack'
$rubyloco = 'https://dl.bintray.com/msp-greg/ruby_trunk'
$ri2_pkgs = 'https://dl.bintray.com/larskanis/rubyinstaller2-packages'

# DevKit paths, windows & unix style, windows prefixed for 7z
$DK32w = '-oC:\ruby23\DevKit\mingw'
$DK32u = 'C:/ruby23/DevKit/mingw'
$DK64w = '-oC:\ruby23-x64\DevKit\mingw'
$DK64u = 'C:/ruby23-x64/DevKit/mingw'

# Misc
$SSL_CERT_FILE = 'C:/ruby25-x64/ssl/cert.pem'
$7z = 'C:\Program Files\7-Zip'
$dash = "$([char]0x2015)"
$ks   = 'na.pool.sks-keyservers.net'
$dash = "$([char]0x2015)"

#—————————————————————————————————————————————————————————————— Ruby version & arch variables
$isRI2 = $env:ruby_version -ge '24'         -Or  $env:ruby_version -eq '_trunk'
$is64  = $env:ruby_version.EndsWith('-x64') -Or  $env:ruby_version -eq '_trunk'

if ($is64) { $m = 'mingw-w64-x86_64-' ; $mingw = 'mingw64' }
  else     { $m = 'mingw-w64-i686-'   ; $mingw = 'mingw32' }

#—————————————————————————————————————————————————————————————————————————————— Check-OpenSSL
function Check-OpenSSL {
  Push-Location -Path 'C:\'

  # Set OpenSSL versions - 2.4 uses standard MinGW 1.0.2 package
  $openssl = if ($env:ruby_version -eq '_trunk') { 'openssl-1.1.0.h' } # trunk
         elseif ($env:ruby_version -lt '22')     { 'openssl-1.0.1l'  } # 2.0, 2.1, 2.2
         elseif ($env:ruby_version -lt '24')     { 'openssl-1.0.2j'  } # 2.3
         else                                    { 'openssl-1.1.0.h' } # 2.5

  $wc = New-Object System.Net.WebClient
  if (!$isRI2) {
    #————————————————————————————————————————————————————————————————————————— RubyInstaller
    if ($is64) { $DKw = $DK64w ; $DKu = $DK64u ; $86_64 = 'x64' }
    else       { $DKw = $DK32w ; $DKu = $DK32u ; $86_64 = 'x86' }

    # Download & upzip into DK folder
    $openssl += '-' + $86_64 + '-windows.tar.lzma'
    $wc.DownloadFile("$ri1_dl/$86_64/$openssl", "$pwd\$openssl")
    &"$7z\7z.exe" e $openssl
    $openssl = $openssl -replace "\.lzma\z", ""
    &"$7z\7z.exe" x -y $openssl $DKw

    $env:SSL_CERT_FILE = $SSL_CERT_FILE
    $env:SSL_VERS = (&"$DKu/bin/openssl.exe" version | Out-String)
    $env:b_config = "-- --with-ssl-dir=$DKu --with-opt-include=$DKu/include"
  } else {
    #————————————————————————————————————————————————————————————————————————— RubyInstaller2
    if ($is64) { $key = '77D8FA18' ; $uri = $rubyloco ; $mingw = 'mingw64' }
      else     { $key = 'BE8BF1C5' ; $uri = $ri2_pkgs ; $mingw = 'mingw32' }

    if ($env:ruby_version.StartsWith('24')) {
      Write-Host 'Use existing OpenSSL 1.0.2 package for Ruby 2.4.x'
    } else {
      $openssl = "$m$openssl-1-any.pkg.tar.xz"
      $wc.DownloadFile("$uri/$openssl"    , "$pwd\$openssl")
      $wc.DownloadFile("$uri/$openssl.sig", "$pwd\$openssl.sig")

      Push-Location -Path $msys2
      $t1 = "pacman-key -r $key --keyserver $ks && pacman-key -f $key && pacman-key --lsign-key $key"
      &"$msys2\bash.exe" -lc $t1 2> $null
      Pop-Location

      &"$msys2\pacman.exe" -Rdd --noconfirm --noprogressbar $($m + 'openssl')
      &"$msys2\pacman.exe" -Udd --noconfirm --noprogressbar --force $openssl
    }
    $env:SSL_VERS = (&"$msys2\..\..\$mingw\bin\openssl.exe" version | Out-String)
    $env:b_config = '-- --use-system-libraries'
  }
  Pop-Location
}

#——————————————————————————————————————————————————————————————————————————————————————— Main
# Update MSYS2 / MinGW or install MinGW packages passed as parameters
# Pass --update to update MSYS2 / MinGW

$need_refresh = $true                    # used to run pacman y option only once

foreach ($arg in $args) {
  $s = if ($need_refresh) { '-Sy' } else { '-S' }
  switch ( $arg ) {
    '--update' {
      if ($isRI2) {
        Write-Host "$($dash * 65) Updating MSYS / MinGW base-devel"
        try   { &"$msys2\pacman.exe" $s --noconfirm --needed --noprogressbar base-devel 2> $null }
        catch { Write-Host 'Cannot update base-devel' }
        Write-Host "$($dash * 65) Updating MSYS / MinGW toolchain"
        try   { &"$msys2\pacman.exe" -S --noconfirm --needed --noprogressbar $($m + 'toolchain') 2> $null }
        catch { Write-Host 'Cannot update toolchain' }
        $need_refresh = $false
      }
    }
    'openssl' {
      Write-Host "$($dash * 65) Checking OpenSSL"
      Check-OpenSSL
    }
    default {
      Write-Host "$($dash * 65) Checking Package: $arg"
      try   { &"$msys2\pacman.exe" $s --noconfirm --needed --noprogressbar $m$arg }
      catch { Write-Host "Cannot install/update $arg package" }
      if (!$ri2 -And $arg -eq 'ragel') { $env:path += ";$msys2\..\..\$mingw\bin" }
      $need_refresh = $false
    }
  }
}
