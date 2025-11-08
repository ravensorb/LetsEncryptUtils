[
	CmdletBinding(SupportsShouldProcess=$true)
]
param(
    [string]$settingsFile = ".\certificates.settings.json",
    [string]$domainFilter = $null,
    [switch]$AutoMapCertificatesToIIS = $true,
    [switch]$RemoveExpiredCertificates = $true,
    [switch]$ForceRenewal
)
BEGIN
{
    Start-Transcript -Path ".\logs\$($MyInvocation.MyCommand.Name).$(get-date -Format yyyyMMdd).txt"

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
    if (-Not (Test-Path $settingsFile)) {
        Write-Host "Could not load settings file '$settingsFile'" -ForegroundColor Red

        return
    }

    $settings = (Get-Content -Path $settingsFile | ConvertFrom-Json)

    if (-Not ([string]::IsNullOrEmpty($domainFilter))) {
        Write-Host "Filtering Domains to match $domainFilter" -ForegroundColor Yellow
        $domains = $settings.domains | Where-Object { $_.displayName -like $domainFilter -or $_.mainDomain -like $domainFilter }
    } else {
        $domains = $settings.domains
    }

    foreach($domain in $domains) {
        if ($domain.enabled -eq $false) 
        {
            Write-Host "Skipping Certificate: $($domain.displayName)" -ForegroundColor Yellow

            continue
        }

        Write-Host "Processing Certificate: $($domain.displayName)" -ForegroundColor Green

        $provider = $settings.providers | Where-Object { $_.name -eq $domain.provider.name }
        if ($provider -eq $nul)
        {
            Write-Host "`tProvider '$($domain.provider.name)' not found..." -ForegroundColor Red

            continue
        }

        Write-Verbose "`t$provider" 
        Write-Debug (ConvertTo-Json $provider -Compress)

        [SecureString]$pfxPasswordSecure = $null
        if (-Not ([string]::IsNullOrEmpty($settings.global.certificates.pfxPasswordSecure))) {
            $pfxPasswordSecure = ConvertTo-SecureString $settings.global.certificates.pfxPasswordSecure
        }

        $args = @{
            domainNames = [string[]] $($domain.mainDomain) + $($domain.alternateDomains)
            contactEmail = $($domain.contact)
            friendlyName = $($domain.displayName)            
            PluginName = $($provider.name)
            PluginArgs = $($provider.settings)
            pfxPassword = $($settings.global.certificates.pfxPassword)
            pfxPasswordSecure = $pfxPasswordSecure
            letsEncrypServerUrl = $($settings.global.letsEncrypt.serverUrl)
            WhatIf = $WhatIfPreference 
            Verbose = $VerbosePreference
            Debug = $DebugPreference
        }

        if ($ForceRenewal.IsPresent) {
            $args += @{ force = $true }
        }

		if (-Not [string]::IsNullOrEmpty($provider.plugin)) {
            $args.PluginName = $($provider.plugin)
		}

        Write-Verbose (ConvertTo-Json $args -Compress)
        
		$processingError = $false
        switch ($domain.type)
        {
            "http" {
                try {
                    & .\Create-HttpCertificate.ps1 @args
                }
                catch {
                    Write-Host "Failed processing domain" -ForegroundColor Red
                    Write-Host $_ -ForegroundColor Red
					
					$processingError = $true
                }  

                break;
            }
            "dns" {

                try {
                    & .\Create-Certificate.ps1 @args 
                }
                catch {
                    Write-Host "Failed processing domain" -ForegroundColor Red
                    Write-Host $_ -ForegroundColor Red
					
					$processingError = $true
                }                

                break;
            }
            default {
                Write-Host "`tInvalid Provider Type: $($domain.type)" -ForegroundColor Red

                break;
            }
        }
    }

    if ($AutoMapCertificatesToIIS -and -not $processingError) {
        Write-Host "Mapping Certificates" -ForegroundColor Green
        & .\Map-CertificatesToWebSites.ps1 -RemoveExpiredCertificates:$RemoveExpiredCertificates -WhatIf:$WhatIfPreference -Verbose:$VerbosePreference
    }
}
END
{
	Write-Verbose "Leaving script $($MyInvocation.MyCommand.Name)"

    Stop-Transcript
}