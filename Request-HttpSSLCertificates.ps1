param(
	$tokenFilePath = $null,
	$tokenPathUserName = $null,
	$tokenPathPassword = $null,
	$letsEncrypServerUrl = "https://acme-v02.api.letsencrypt.org/directory",
	$forceRenewal = $false
)

if ($tokenPathUserName -eq $null -or $tokenPathUserName.Length -eq 0) {
	Write-Host "Loading Settings file" -ForegroundColor Yellow
	$settings = (Get-Content -Raw -Path ".\settings.httpsslcertificates.json" | ConvertFrom-Json)
	$tokenFilePath = $settings.path
	$tokenPathUserName = $settings.userName
	$tokenPathPassword = $settings.password
}

Write-Host "Requesting HTTP Based Certificates" -ForegroundColor Green
Write-Host "`tFile Path: $tokenFilePath" -ForegroundColor Yellow
Write-Host "`tUser Name: $tokenPathUserName" -ForegroundColor Yellow
Write-Host "`tPassword: $tokenPathPassword" -ForegroundColor Yellow

.\New-PAHttpCertificate.ps1 -domainName aussierescue.org,www.aussierescue.org,beta.aussierescue.org -contactEmail certs@aussierescue.org -tokenFilePath $tokenFilePath -tokenPathUserName $tokenPathUserName -tokenPathPassword $tokenPathPassword -letsEncrypServerUrl $letsEncrypServerUrl -forceRenewal $forceRenewal
.\New-PAHttpCertificate.ps1 -domainName spm-solutions.com,www.spm-solutions.com,beta.spm-solutions.com -contactEmail certs@liquidlogiclabs.com -tokenFilePath $tokenFilePath -tokenPathUserName $tokenPathUserName -tokenPathPassword $tokenPathPassword -letsEncrypServerUrl $letsEncrypServerUrl -forceRenewal $forceRenewal