param(
	$tokenFilePath = $null,
	$tokenPathUserName = $null,
	$tokenPathPassword = $null,
	$letsEncrypServerUrl = "https://acme-v02.api.letsencrypt.org/directory",
	$forceRenewal = $false
)

Write-Host "Loading Settings file" -ForegroundColor Yellow
$settings = (Get-Content -Raw -Path ".\settings.httpsslcertificates.json" | ConvertFrom-Json)

if ($tokenPathUserName -eq $null -or $tokenPathUserName.Length -eq 0) {
	$tokenFilePath = $settings.fileShare.path
	$tokenPathUserName = $settings.fileShare.userName
	$tokenPathPassword = $settings.fileShare.password
}

Write-Host "Requesting HTTP Based Certificates" -ForegroundColor Green
Write-Host "`tFile Path: $tokenFilePath" -ForegroundColor Yellow
Write-Host "`tUser Name: $tokenPathUserName" -ForegroundColor Yellow
#Write-Host "`tPassword: $tokenPathPassword" -ForegroundColor Yellow

$settings.domains | % {
	Write-Host "`tDomains: $($_.names)" -ForegroundColor Yellow
	.\New-PAHttpCertificate.ps1 -domainName $_.names -contactEmail $contact -tokenFilePath $tokenFilePath -tokenPathUserName $tokenPathUserName -tokenPathPassword $tokenPathPassword -letsEncrypServerUrl $letsEncrypServerUrl -forceRenewal $forceRenewal
}