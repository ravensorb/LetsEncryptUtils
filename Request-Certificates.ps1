[
	CmdletBinding(SupportsShouldProcess=$true)
]
param(
    [string]$settingsFile = ".\certificates.settings.json",
    [string]$domainFilter = $null,
    [switch]$AutoMapCertificatesToIIS = $true
)
BEGIN
{
    Start-Transcript -Path ".\$($MyInvocation.MyCommand.Name).$(get-date -Format yyyyddMM).txt"

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

    if ($null -ne $domainFilter) {
        $domains = $settings.domains | ? { $_.displayName -like $domainFilter}
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

        $provider = $settings.providers | ? { $_.name -eq $domain.provider.name }
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

        Write-Verbose (ConvertTo-Json $args -Compress)
        
        switch ($domain.type)
        {
            "http" {
                try {
                    & .\Create-HttpCertificate.ps1 @args
                }
                catch {
                    Write-Host "Failed processing domain" -ForegroundColor Red
                    Write-Host $_ -ForegroundColor Red
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
                }                

                break;
            }
            default {
                Write-Host "`tInvalid Provider Type: $($domain.type)" -ForegroundColor Red

                break;
            }
        }
    }

    if ($AutoMapCertificatesToIIS) {
        & .\Map-CertificatesToWebSites.ps1 -WhatIf:$WhatIfPreference -Verbose:$VerbosePreference
    }
}
END
{
	Write-Verbose "Leaving script $($MyInvocation.MyCommand.Name)"

    Stop-Transcript
}