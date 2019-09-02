param(
	[string[]]$domainNames,
	[string]$contactEmail = $null,
	[string]$friendlyName = $null,
	[string]$namecomUserName = $null,
	[string]$namecomToken = $null,
	[string]$pfxPassword = $null,
	[string]$letsEncrypServerUrl = "https://acme-v02.api.letsencrypt.org/directory"
)

if ($namecomUserName -eq $null -or $namecomUserName.Length -eq 0) {
	Write-Host "Loading Settings file" -ForegroundColor Yellow
	$settings = (Get-Content -Raw -Path ".\settings.namecom.json" | ConvertFrom-Json)
	$namecomUserName = $settings.key
	$namecomToken = $settings.token
}

# Do we have a user name and password for name.com
if ($namecomUserName -eq $null -or $namecomUserName.Length -eq 0 -or $namecomToken -eq $null -or $namecomToken.Length -eq 0) {
	Write-Warning "name.com username and token must be specfiied"
	exit
}

# Do we have at least one domain name?
if ($domainNames -eq $null -or $domainNames.Count -eq 0 -or $domainNames[0].Length -eq 0) {
	Write-Warning "At least one Domain Name must be specfiied"
	exit
}

# If the first one is a wildcard lets get a version without the *. to use later
$safeDomainName = $domainNames[0]
$safeDomainName = $safeDomainName.Replace("*.", "");

# Do we have online 1 domain name and is it a wildcard?
if ($domainNames.Count -eq 1) {
	if ($domainNames[0].StartsWith("*.")) {
		# if so, lets add in the base domain name to the certificate 
		$domainNames += $safeDomainName
	}
}

# Do we have a valid pfx password?
if ($pfxPassword -eq $null -or $pfxPassword.Length -eq 0) {
	# If not, lets use the API token
	$pfxPassword = $namecomToken
}

# Do we have a friendly name? If not lets use the safe domain as the friendly Name
if ($friendlyName -eq $null -or $friendlyName.Length -eq 0) {
	$friendlyName = $safeDomainName
}

# Do we have a contact email, if not lets set a default one
if ($contactEmail -eq $null -or $contactEmail.Length -eq 0) {
	$contactEmail = "certs@$($safeDomainName)"
}

Import-Module Posh-ACME

Write-Host "Creating Certificate for $domainNames" -ForegroundColor Green
Write-Host "`tContact Email: $contactEmail" -ForegroundColor Yellow
Write-Host "`tFriendly Name: $friendlyName" -ForegroundColor Yellow
Write-Host "`tUserName: $namecomUserName" -ForegroundColor Yellow
Write-Host "`tToken: $namecomToken" -ForegroundColor Yellow

Write-Host "Setting Lets Encrypt to use $letsEncrypServerUrl" -ForegroundColor Green

Set-PAServer -DirectoryUrl $letsEncrypServerUrl

New-PACertificate $domainNames -AcceptTOS -Install -Contact $contactEmail --FriendlyName $friendlyName -DnsPlugin NameCom -PluginArgs @{NameComUserName=$namecomUserName; NameComToken=$namecomToken} -PfxPass $pfxPassword