[
	CmdletBinding(SupportsShouldProcess=$true)
]
param(
    [string]$settingsFile = ".\certificates.settings.json"
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
    if (-Not (Test-Path $settingsFile)) {
        Write-Host "Could not load settings file '$settingsFile'" -ForegroundColor Red

        return
    }

    $settings = (Get-Content -Path $settingsFile | ConvertFrom-Json)

    foreach($domain in $settings.domains) {
        Write-Host "Processing Certificate: $($domain.displayName)" -ForegroundColor Green

        $provider = $settings.providers | ? { $_.name -eq $domain.provider.name }
        if ($provider -eq $nul)
        {
            Write-Host "`tProvider '$($domain.provider.name)' not found..." -ForegroundColor Red

            continue
        }

        Write-Verbose "`t$provider" 
        Write-Debug (ConvertTo-Json $provider -Compress)

        $args = @{
            domainNames = [string[]] $($domain.mainDomain) + $($domain.alternateDomains)
            contactEmail = $($domain.contact)
            friendlyName = $($domain.displayName)            
            PluginName = $($provider.name)
            PluginArgs = $($provider.settings)
            pfxPassword = $($settings.global.certificates.pfxPassword)
            letsEncrypServerUrl = $($settings.global.letsEncrypt.serverUrl)
            WhatIf = $WhatIfPreference 
            Verbose = $VerbosePreference
        }

        Write-Verbose (ConvertTo-Json $args -Compress)
        
        switch ($domain.type)
        {
            "http" {
                & .\Create-HttpCertificate.ps1 @args 
                
                break;
            }
            "dns" {

                & .\Create-Certificate.ps1 @args 

                break;
            }
            default {
                Write-Host "`tInvalid Provider Type: $($domain.type)" -ForegroundColor Red

                break;
            }
        }
    }
}
END
{
	Write-Verbose "Leaving script $($MyInvocation.MyCommand.Name)"
}