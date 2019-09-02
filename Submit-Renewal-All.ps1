param(
	[bool]$requestManualHttpCerts = $true,
	[bool]$mapCertsToSites = $true
)

$accounts = Get-PAAccount -List

Write-Host "Submitting renewal request for all accounts" -ForegroundColor Green

$accounts | ForEach-Object {
	$a = $_

	Write-Host "`tAccount $($a.id) [$($a.contact)]" -ForegroundColor Yellow
	
	Set-PAAccount -ID $a.id
	
	try { Submit-Renewal -ErrorAction Continue }
	catch { "`tFailed to submit renewal" }
}

if ($requestManualHttpCerts -eq $true) {
	Write-Host "Requeting Manul HTTP Certificates" -ForegroundColor Green
	.\Request-HttpSSLCertificates.ps1
}

if ($mapCertsToSites -eq -$true) {
	Write-Host "Mapping Certificates to IIS Web Sites" -ForegroundColor Green
	.\Map-CertificatesToWebSites.ps1
}