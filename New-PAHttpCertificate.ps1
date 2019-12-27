[
	CmdletBinding(SupportsShouldProcess=$true)
]
param(
	[Parameter(Mandatory=$true, Position=0)][string[]]$domainNames,
	[switch]$AcceptTOS,
	[switch]$Install,
	[string]$Contact = $null,
	[string]$FriendlyName = $null,
	[System.Management.Automation.PSObject]$PluginArgs,
	[string]$PfxPass = $null,
	[switch]$CleanUpTokenFiles 
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

	$tokenFilesCreated = @()
}
PROCESS
{
	Import-Module Posh-ACME

	if ($null -eq $domainNames -or $domainNames[0].Length -eq 0) {
		Write-Warning "Domain Name must be specfiied"

		return
	}

	if ($null -eq $PluginArgs.Path -or $PluginArgs.Path.Length -eq 0) {
		Write-Warning "Path must be specfiied"

		return
	}

	$args = @{
		Name = "tokenPath"
		Root = $($PluginArgs.Path)
		PSProvider = "FileSystem"
	}

	if ($null -eq $PluginArgs.PathCredential) {
		if ($null -ne $PluginArgs.UserName) {
			if ($null -ne $PluginArgs.Path -and $PluginArgs.Path.StartsWith("\\")) {
				if ($null -ne $PluginArgs.UserName -and $PluginArgs.UserName.Length -gt 0) {
					Write-Host "Creating Credential Object" -ForegroundColor Yellow
					if ($null -eq $PluginArgs.PasswordSecure -and $null -ne $PluginArgs.Password) {
						Write-Verbose "`tConverting Password to Secure String"
						$PluginArgs.PasswwordSecure = ConvertTo-SecureString -String $PluginArgs.Password -AsPlainText -Force
					}

					$PluginArgs.PathCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $($PluginArgs.UserName), $($PluginArgs.PasswordSecure)
				}
				else {
					$PluginArgs.PathCredential = Get-Credential -Message "Fileshare Path Credentials"
				}
			}		

			if ($null -eq $PluginArgs.PathCredential) {
				Write-Warning "No credentials supplied for $($PluginArgs.Path)"
			}
		}

		$args += @{ Credential = $($PluginArgs.PathCredential) }
	}

	Write-Verbose (ConvertTo-Json $args)

	$psdrive = New-PSDrive @args
	if ($null -eq $psdrive) {
		Write-Warning "Failed to access $($PluginArgs.Path)"

		return
	}

	Write-Verbose (ConvertTo-Json $psdrive)

	$safeDomainName = $domainNames[0]
	$safeDomainName = $safeDomainName.Replace("*.", "");

	if ($null -eq $FriendlyName -or $FriendlyName.Length -eq 0) {
		$FriendlyName = $safeDomainName
	}

	# Do we have a valid pfx password
	#if ($PfxPass -eq $null -or $PfxPass.Length -eq 0) {
		#Write-Warning "Pfx PfxPass is required"
		#return
	#}

	if ($null -eq $Contact -or $Contact.Length -eq 0) {
		$Contact = "mailto:postmaster@$safeDomainName"
	}

	if (-Not $Contact.StartsWith("mailto:")) {
		$Contact = "mailto:$Contact";
	}

	Write-Host "Creating SSL for $domainNames" -ForegroundColor Green
	Write-Host "`tContact Email: $Contact" -ForegroundColor Yellow
	Write-Host "`tFriendly Name: $FriendlyName" -ForegroundColor Yellow
	Write-Host "`tPath: $($PluginArgs.Path)" -ForegroundColor Yellow

	$act = Get-PAAccount -List | ? { $_.contact -eq $Contact }

	if ($null -eq $act) {
		Write-Host "Creating new account for domain $($domainNames[0])" -ForegroundColor Green
		if ($PSCmdlet.ShouldProcess("$Conact", "Creating new PA Account")) {
			New-PAAccount -AcceptTOS -Contact $Contact
		}
	} else {
		Write-Host "Changing active account to $($act.ID) for domain $($domainNames[0])" -ForegroundColor Green
		Set-PAAccount -Id $act.ID
	}

	$order = Get-PAOrder $domainNames[0] -Refresh
	if ($null -ne $order -and $order.status -eq 'invalid') {
		Write-Host "Deleted Old Invalid Order" -ForegroundColor Green
		if ($PSCmdlet.ShouldProcess("$order", "Removing Invalid Order")) {
			Remove-PAOrder $domainNames[0] -ErrorAction Continue -Force
		}
		$order = $null
	}

	if ($null -eq $order) {
		Write-Host "Creating new order" -ForegroundColor Green
		if ($PSCmdlet.ShouldProcess("$domainNames", "Creating new PA Order")) {
			$order = New-PAOrder $domainNames -FriendlyName $FriendlyName -Install
		}
	}
		
	if ($null -eq $order) {
		Write-Warning "No pending orders"

		return
	}

	if ($null -ne $order.RenewAfter -and $order.RenewAfter.Length -gt 0) {
		$renewAfter = [DateTimeOffset]::Parse($order.RenewAfter)
		if ([DateTimeOffset]::Now -le $renewAfter -and $forceRenewal -eq $false) {
			Write-Warning "Existing Order Found. Not time to renew yet. Skipping..."

			return
		}
	}

	Write-Host "Order Details: $($order.status): $($order.FriendlyName)" -ForegroundColor Yellow
	Write-Verbose (ConvertTo-Json $order)

	Write-Host "Getting authorizations for order" -ForegroundColor Green
	$auths = $order | Get-PAAuthorizations
	if ($null -eq $auths) {
		Write-Warning "No pending authentications"

		return
	}

	$auths | ft
	Write-Verbose (ConvertTo-Json $auths) 

	$toPublish = $auths | ? { $_.HTTP01Token.Length -gt 0 } | Select-Object @{L='Url';E={"http://$($_.fqdn)/.well-known/acme-challenge/$($_.HTTP01Token)"}}, `
										@{L='Token';E={"$($_.HTTP01Token)"}}, `
										@{L='Body';E={Get-KeyAuthorization $_.HTTP01Token (Get-PAAccount)}}
								
	Write-Verbose (ConvertTo-Json $toPublish)

	Write-Host "Creating HTTP Challenge Token Files" -ForegroundColor Green

	$toPublish | % {
		$f = "tokenPath:\$($_.Token)"
		Write-Host "`tCreating Token File $f" -ForegroundColor Yellow
		if ($PSCmdlet.ShouldProcess("$f", "Creating Token File")) {
			$tokenFilesCreated += $f
			Out-File -File $f -InputObject $_.Body -Encoding ascii
		}
	}
								
	Write-Host "Sending Challenges" -ForegroundColor Green
	if ($PSCmdlet.ShouldProcess("$auths", "Sending ChallengeAck")) {
		$auths.HTTP01Url | Send-ChallengeAck -Verbose:$VerbosePreference
	}

	$pending = $true
	$counter = 0
	do {
		Write-Host "Sleeping for 10 seconds to wait for status updates" -ForegroundColor Yellow
		Start-Sleep -Seconds 10
	
		Write-Host "Getting Auth Status" -ForegroundColor Green
		$authStatus = Get-PAOrder -Refresh | Get-PAAuthorizations
		$authStatus | ft 
		Write-Verbose (ConvertTo-Json $authStatus)
	
		$pending = ($authStatus | ? { $_.status -eq "pending"} )
		$counter++
	} while ($pending -or $counter -ge 12)

	if ($null -ne ($authStatus | ? { $_.status -eq "invalid"} )) {
		Write-Host "One or more Auth Status are invalid.  Please fix and try again..." -ForegroundColor Red

		foreach ($item in $authStatus)
		{
			Write-Host "--------------------------------------------------------------------------"
			Write-Host "Result for: $($item.fqdn)"
			$item | fl *
			$item.challenges.validationRecord | fl *
		}

		return
	}

	try {
		Write-Host "Creating Certificates" -ForegroundColor Green
		if ($PSCmdlet.ShouldProcess("$domainNames", "Creating actual Certificate")) {
			New-PACertificate $domainNames -FriendlyName $FriendlyName -Install -AcceptTOS -ErrorAction Continue -Verbose:$VerbosePreference -DnsPlugin Manual 
		}
	} catch {
		Write-Warning "New Certificated call Failed"
		Write-Warning $_

		return
	}

	Write-Host "Sleeping for 10 seconds to wait for status updates" -ForegroundColor Yellow
	Start-Sleep -Seconds 10

	Write-Host "Getting Updated Auth Status" -ForegroundColor Green
	$authStatus = Get-PAOrder -Refresh | Get-PAAuthorizations
	$authStatus.challenges | ft
	#$authStatus
	#$authStatus.challenges | ? { $_.type -eq 'http-01' } | fl *
	Write-Verbose (ConvertTo-Json $authStatus)
}
END
{
	if ($CleanUpTokenFiles)
	{
		Write-Host "Removing HTTP Challenge Token Files" -ForegroundColor Green

		$tokenFilesCreated | % {
			Write-Host "`tRemoving Token File $_" -ForegroundColor Yellow
			Remove-Item $_ -ErrorAction SilentlyContinue
		}
	}

	Remove-PSDrive -Name tokenPath -ErrorAction SilentlyContinue | Out-Null

	Write-Verbose "Leaving script $($MyInvocation.MyCommand.Name)"
}