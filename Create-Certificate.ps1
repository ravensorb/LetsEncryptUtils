[
	CmdletBinding(SupportsShouldProcess=$true)
]
param(
	[Parameter(Mandatory=$true)][string[]]$domainNames,
	[string]$contactEmail = $null,
	[string]$friendlyName = $null,
	[Parameter(Mandatory=$true)][string]$PluginName,
	[System.Management.Automation.PSObject]$PluginArgs,
	[string]$pfxPassword = $null,
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
	if ($null -eq $PluginArgs) {
		Write-Host "Loading Settings file" -ForegroundColor Yellow
		$PluginArgs = (Get-Content -Raw -Path ".\settings.$($PluginName).json" | ConvertFrom-Json)
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

	# Do we have a friendly name? If not lets use the safe domain as the friendly Name
	if ($friendlyName -eq $null -or $friendlyName.Length -eq 0) {
		$friendlyName = $safeDomainName
	}

	# Do we have a contact email, if not lets set a default one
	if ($contactEmail -eq $null -or $contactEmail.Length -eq 0) {
		$contactEmail = "certs@$($safeDomainName)"
	}

	# Do we have a valid pfx password?
	if ($pfxPassword -eq $null -or $pfxPassword.Length -eq 0) {
		# If not, lets use the contact email address
		$pfxPassword = $contactEmail
	}

	Import-Module Posh-ACME

	Write-Host "Creating Certificate for $domainNames" -ForegroundColor Green
	Write-Host "`tContact Email: $contactEmail" -ForegroundColor Yellow
	Write-Host "`tFriendly Name: $friendlyName" -ForegroundColor Yellow
	Write-Host "`tPlugin Name: $PluginName" -ForegroundColor Yellow
	Write-Debug "`tPlugin Args:" 
	Write-Debug (ConvertTo-Json $PluginArgs -Compress)

	Write-Host "Setting Lets Encrypt to use $letsEncrypServerUrl" -ForegroundColor Green

	if ($PSCmdlet.ShouldProcess("$letsEncrypServerUrl", "Setting Lets Encrypt Server Url")) {
		Set-PAServer -DirectoryUrl $letsEncrypServerUrl -Verbose:$VerbosePreference
	}

	if ($PSCmdlet.ShouldProcess("$domainNames", "Creating actual Certificate")) {
		$htPluginArgs = ($PluginArgs.psobject.properties | ForEach-Object -begin {$h=@{}} -process {$h.$($_.Name) = $_.Value} -end {$h})

		New-PACertificate $domainNames -AcceptTOS -Install -Contact $contactEmail -FriendlyName $friendlyName -DnsPlugin $PluginName -PluginArgs $htPluginArgs -PfxPass $pfxPassword -Verbose:$VerbosePreference
	}
}
END
{
	Write-Verbose "Leaving script $($MyInvocation.MyCommand.Name)"
}