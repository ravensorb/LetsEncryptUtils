[
	CmdletBinding(SupportsShouldProcess=$true)
]
param(
	[string]$FriendlyName = $null,
	[switch]$RemoveExpiredCertificates
)
BEGIN
{
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Write-Host "This script is not supported in PowerShell Core." -ForegroundColor Red
        exit
    }

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
	# Get a list of Let's Enrypt SSL Certificates that are still valid
	$certs = (Get-ChildItem cert:\localmachine\my | Where-Object { $_.Issuer -Like "*Let's*" -and $_.NotAfter -ge [DateTime]::Now.AddDays(-20) })

	if ($null -ne $FriendlyName -and $FriendlyName.Length -gt 0) {
		$certs = $certs | Where-Object { $_.Subject -like $FriendlyName }
	}

	# Get a list of HTTPS website bindings
	$webSites = Get-WebBinding | Where-Object { $_.Protocol -eq "https" }

	foreach ($c in $certs)
	{
		$hash = $c.Thumbprint
		Write-Host "Processing Cert: $($c.Subject) [Expires:$($c.NotAfter)] [$($c.Thumbprint)]" -ForegroundColor Green
			
		foreach ($dnsNameItem in $c.DnsNameList) 
		{
			$dnsName = $($dnsNameItem.Punycode);
			Write-Host "`tDNS Name: $($dnsName)" -ForegroundColor Yellow

			$sites = $webSites | Where-Object { $_.bindingInformation -like "*$($dnsName)*" }

			foreach ($s in $sites)
			{
				$b = $s.bindingInformation | Where-Object { $_ -like "*$($dnsName)*" }

				# Rebind the SSL cert to the website
				Write-Host "`t`tSetting Binding for $($b) to [$($hash)]" -ForegroundColor Cyan

				if ($PSCmdlet.ShouldProcess("$b", "Adding SSL Certificate to Binding")) {
					try {
						$s.AddSSLCertificate($($hash), "My")
					} catch {
						Write-Host "`t`tFailed to add SSL certificate" -ForegroundColor Red
						Write-Host $_ -ForegroundColor Red
					}
				}

				continue
			}
		}
	}

	if ($RemoveExpiredCertificates) 
	{
		Write-Host "Checking for Certificates that have expired and can be removed" -ForegroundColor Green

		# Get a list of Let's Enrypt SSL Certificates that are still valid
		$certs = (Get-ChildItem cert:\localmachine\my | Where-Object { $_.Issuer -Like "*Let's*" -and $_.NotAfter -le [DateTime]::Now })

		if ($null -ne $friendlyName -and $friendlyName.Length -gt 0) {
			Write-Host "Checking to see if any expired certs match the name '$($FriendlyName)"
			$certs = $certs | Where-Object { $_.Subject -like $friendlyName }
		}

		foreach ($c in $certs)
		{
			Write-Host "`tRemoving Cert: $($c.Subject) [Expires:$($c.NotAfter)] [$($c.Thumbprint)]" -ForegroundColor Green

			try {
				$c | Remove-Item
			}
			catch {
				Write-Host "Failed removing certificate...." -ForegroundColor Red
				Write-Host $_ -ForegroundColor Red
			}                			
		}
	}
}
END
{
	Write-Verbose "Leaving script $($MyInvocation.MyCommand.Name)"
}