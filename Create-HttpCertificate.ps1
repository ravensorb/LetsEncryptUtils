[
	CmdletBinding(SupportsShouldProcess=$true)
]
param(
	[Parameter(Mandatory=$true)][string[]]$domainNames,
	[string]$contactEmail = $null,
	[string]$friendlyName = $null,
	[string]$PluginName,
	[Parameter(Mandatory=$true)][System.Management.Automation.PSObject]$PluginArgs,
	[string]$pfxPassword = $null,
	[SecureString]$pfxPasswordSecure = $null,
	[string]$letsEncrypServerUrl = "https://acme-v02.api.letsencrypt.org/directory"
)
BEGIN
{
	if (-not $PSBoundParameters.ContainsKey('Verbose'))
	{
		$VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')
	}  

	# $ErrorPreference = 'Stop'
	# if ( $PSBoundParameters.ContainsKey('ErrorAction')) {
	# 	$ErrorPreference = $PSBoundParameters['ErrorAction']
	# }

	Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
	Write-Verbose "Parameter Values"
	$PSBoundParameters.Keys | ForEach-Object { Write-Verbose "$_ = '$($PSBoundParameters[$_])'" }
}
PROCESS
{
	# Do we have a valid file path
	if ($null -eq $PluginArgs.path -or $PluginArgs.path.Length -eq 0) {
		Write-Warning "filepath must be specfiied"
		exit
	}

	# Do we have at least one domain name?
	if ($null -eq $domainNames -or $domainNames.Count -eq 0 -or $domainNames[0].Length -eq 0) {
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

	if ($null -ne $pfxPasswordSecure -and $pfxPasswordSecure.Length -ne 0) {
		$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pfxPasswordSecure)
		$pfxPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
	}

	# Do we have a valid pfx password?
	if ($null -eq $pfxPassword -or $pfxPassword.Length -eq 0) {
		# If not, lets use the contact email address
		$pfxPassword = $contactEmail
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
	Write-Debug "`tPlugin Args:" 
	Write-Debug (ConvertTo-Json $PluginArgs -Compress)

	Write-Host "Setting Lets Encrypt to use $letsEncrypServerUrl" -ForegroundColor Green

	if ($PSCmdlet.ShouldProcess("$letsEncrypServerUrl", "Setting Lets Encrypt Server Url")) {
		Set-PAServer -DirectoryUrl $letsEncrypServerUrl -Verbose:$VerbosePreference
	}	

	#if ($PSCmdlet.ShouldProcess("$domainNames", "Creating actual Certificate")) {
		& .\New-PAHttpCertificate.ps1 $domainNames -AcceptTOS -Install -Contact $contactEmail -FriendlyName $friendlyName -PluginArgs @{Path=$($PluginArgs.path); UserName=$($PluginArgs.userName); Password=$($PluginArgs.password); PasswordSecure=$($PluginArgs.passwordSecure)} -PfxPass $pfxPassword -WhatIf:$WhatIfPreference -Verbose:$VerbosePreference -CleanUpTokenFiles
	#}
}
END
{
	Write-Verbose "Leaving script $($MyInvocation.MyCommand.Name)"
}