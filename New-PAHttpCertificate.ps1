param(
	[string[]]$domainNames,
	[string]$contactEmail = $null,
	[string]$friendlyName = $null,
	[string]$tokenFilePath = $null,
	[System.Management.Automation.PSCredential]$tokenPathCredential = $null,
	[string]$tokenPathUserName = $null,
	[string]$tokenPathPassword = $null,
	[System.Security.SecureString]$tokenPathPasswordSecure = $null,
	[bool]$forceRenewal = $false,
	[string]$pfxPassword = $null,
	[string]$letsEncrypServerUrl = "https://acme-v02.api.letsencrypt.org/directory"
)

Import-Module Posh-ACME

if ($domainNames -eq $null -or $domainNames[0].Length -eq 0) {
	Write-Warning "Domain Name must be specfiied"
	exit
}

if ($tokenFilePath -eq $null -or $tokenFilePath.Length -eq 0) {
	Write-Warning "Token Path must be specfiied"
	exit
}

if ($tokenPathCredential -eq $null -and $tokenFilePath.StartsWith("\\")) {
	if ($tokenPathUserName -ne $null -and $tokenPathUserName.Length -gt 0) {
		Write-Host "Creating Credential Object" -ForegroundColor Yellow
		if ($tokenPathPasswordSecure -eq $null -and $tokenPathPassword -ne $null) {
			$tokenPathPasswordSecure = ConvertTo-SecureString -String $tokenPathPassword -AsPlainText -Force
		}
		$tokenPathCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($tokenPathUserName, $tokenPathPasswordSecure)
	}
	else {
		$tokenPathCredential = Get-Credential
	}
}

if ($tokenPathCredential -eq $null) {
	Write-Warning "No credentials supplied for $tokenFilePath"
}

$psdrive = New-PSDrive -Name tokenPath -Root $tokenFilePath -PSProvider FileSystem -Credential $tokenPathCredential
if ($psdrive -eq $null) {
	Write-Warning "Failed to access $tokenFilePath"
	exit
}

$safeDomainName = $domainNames[0]
$safeDomainName = $safeDomainName.Replace("*.", "");

if ($friendlyName -eq $null -or $friendlyName.Length -eq 0) {
	$friendlyName = $safeDomainName
}

# Do we have a valid pfx password
#if ($pfxPassword -eq $null -or $pfxPassword.Length -eq 0) {
	#Write-Warning "Pfx Password is required"
	#exit
#}

if ($contactEmail -eq $null -or $contactEmail.Length -eq 0) {
	$contactEmail = "mailto:postmaster@$safeDomainName"
}

if (-Not $contactEmail.StartsWith("mailto:")) {
	$contactEmail = "mailto:$contactEmail";
}

Write-Host "Creating SSL for $domainNames" -ForegroundColor Green
Write-Host "`tContact Email: $contactEmail" -ForegroundColor Yellow
Write-Host "`tFriendly Name: $friendlyName" -ForegroundColor Yellow
Write-Host "`tToken Path: $tokenFilePath" -ForegroundColor Yellow

Write-Host "Setting Lets Encrypt to use $letsEncrypServerUrl" -ForegroundColor Green

Set-PAServer -DirectoryUrl $letsEncrypServerUrl

$act = Get-PAAccount -List | ? { $_.contact -eq $contactEmail }

if ($act -eq $null) {
	Write-Host "Creating new account for domain $($domainNames[0])" -ForegroundColor Green
	New-PAAccount -AcceptTOS -Contact $contactEmail
} else {
	Write-Host "Changing active account to $($act.ID) for domain $($domainNames[0])" -ForegroundColor Green
	Set-PAAccount -Id $act.ID
}

$order = Get-PAOrder $domainNames[0] -Refresh
if ($order -ne $null -and $order.status -eq 'invalid') {
    Write-Host "Deleted Old Invalid Order" -ForegroundColor Green
	Remove-PAOrder $domainNames[0] -ErrorAction Continue 
	$order = $null
}

if ($order -eq $null) {
	Write-Host "Creating new order" -ForegroundColor Green
	$order = New-PAOrder $domainNames -FriendlyName $friendlyName -Install
}
	
if ($order -eq $null) {
	Write-Warning "No pending orders"
	exit
}

if ($order.RenewAfter -ne $null -and $order.RenewAfter.Length -gt 0) {
	$renewAfter = [DateTimeOffset]::Parse($order.RenewAfter)
	if ([DateTimeOffset]::Now -le $renewAfter -and $forceRenewal -eq $false) {
		Write-Host "Existing Order Found. Not time to renew yet. Skipping..."
		exit
	}
}

Write-Host "Order Details" -ForegroundColor Yellow
$order

Write-Host "Getting authorizations for order" -ForegroundColor Green
$auths = $order | Get-PAAuthorizations

Write-Host "Authorization Details" -ForegroundColor Yellow
$auths;

if ($auths -eq $null) {
	Write-Warning "No pending authentications"
	exit
}

$toPublish = $auths | Select @{L='Url';E={"http://$($_.fqdn)/.well-known/acme-challenge/$($_.HTTP01Token)"}}, `
                             @{L='Token';E={"$($_.HTTP01Token)"}}, `
                             @{L='Body';E={Get-KeyAuthorization $_.HTTP01Token (Get-PAAccount)}}
							 
Write-Host "Publish  Details" -ForegroundColor Yellow
$toPublish
							 
$toPublish | % {
	$f = "tokenPath:\$($_.Token)"
	Write-Host "Creating Token File $f" -ForegroundColor Green
	Out-File -File $f -InputObject $_.Body -Encoding ascii
}

Remove-PSDrive -Name tokenPath
							 
Write-Host "Sending Challenges" -ForegroundColor Green
$auths.HTTP01Url | Send-ChallengeAck -Verbose

Write-Host "Sleeping for 10 seconds to wait for status updates"
Start-Sleep -Seconds 10

Write-Host "Getting Auth Status" -ForegroundColor Green
$authStatus = Get-PAOrder -Refresh | Get-PAAuthorizations
$authStatus | ft

try {
	Write-Host "Creating Certificates" -ForegroundColor Green
	New-PACertificate $domainNames -FriendlyName $friendlyName -Install -AcceptTOS -ErrorAction Continue -Verbose -DnsPlugin Manual 
} catch {
	Write-Warning "New Certificated call Failed"
	Write-Warning $_
}

Write-Host "Sleeping for 10 seconds to wait for status updates"
Start-Sleep -Seconds 10

Write-Host "Getting Updated Auth Status" -ForegroundColor Green
$authStatus = Get-PAOrder -Refresh | Get-PAAuthorizations
$authStatus
$authStatus.challenges | ? { $_.type -eq 'http-01' } | fl *
