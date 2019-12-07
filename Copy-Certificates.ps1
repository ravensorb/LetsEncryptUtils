[
    CmdletBinding(SupportsShouldProcess=$true, DefaultParameterSetName = 'Credential')   
]
param(
    [Parameter()][string]$Path,
    [Parameter()][string]$SettingsFile = $null,
    [Parameter(ParameterSetName='Credential')][pscredential]$PathCredentials = $null,
	[Parameter(ParameterSetName='UserNamePassword')][string]$PathUserName = $null,
	[Parameter(ParameterSetName='UserNamePassword')][string]$PathPassword = $null,
	[Parameter(ParameterSetName='UserNamePassword')][SecureString]$PathPasswordSecure = $null
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
    if ($null -ne $SettingsFile -and $SettingsFile.Length -gt 0 -and (Test-Path $SettingsFile)) {
        Write-Host "Load settings file '$SettingsFile'" -ForegroundColor Green

        $settings = (Get-Content -Path $SettingsFile | ConvertFrom-Json)
        
        if ($null -ne $settings.path -and $settings.path.Length -gt 0) { $Path = $settings.path }
        if ($null -ne $settings.userName -and $settings.userName.Length -gt 0) { $PathUserName = $settings.userName }
        if ($null -ne $settings.password -and $settings.password.Length -gt 0) { $PathPassword = $settings.password }
        if ($null -ne $settings.passwordSecure -and $settings.passwordSecure.Length -gt 0) { $PathPasswordSecure = ConvertTo-SecureString $($settings.passwordSecure) }
    }

    if ($null -eq $Path -or $Path.Length -eq 0) {
        Write-Host "No path specificed.  Please check parameters and try again...." -ForegroundColor Red

        return
    }

	$args = @{
		Name = "certPath"
		Root = $($Path)
		PSProvider = "FileSystem"
	}

	if ($null -eq $PathCredentials) {
		if ($null -ne $PathUserName) {
			if ($null -ne $Path -and $Path.StartsWith("\\")) {
				if ($null -ne $PathUserName -and $PathUserName.Length -gt 0) {
					Write-Host "Creating Credential Object" -ForegroundColor Yellow
					if ($null -eq $PathPasswordSecure -and $null -ne $PathPassword) {
						$PathPasswordSecure = ConvertTo-SecureString -String $PathPassword -AsPlainText -Force
					}

					$PathCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($PathUserName, $PathPasswordSecure)
				}
				else {
					$PathCredentials = Get-Credential -Message "Fileshare Path Credentials" -UserName $PathUserName
				}
			}		

			if ($null -eq $PathCredentials) {
				Write-Warning "No credentials supplied for $($Path)"
			}

            $args += @{ Credential = $($PathCredentials) }
		}
	}

	Write-Verbose (ConvertTo-Json $args)

	$psdrive = New-PSDrive @args
	if ($null -eq $psdrive) {
		Write-Warning "Failed to access $($Path)"

		return
    }

    $currentAccount = Get-PAAccount

    $accounts = Get-PAAccount -List

    foreach ($account in $accounts) 
    {
        Set-PAAccount -ID $($account.id)
        Write-Host "Processing Account: $($account.id):$($account.contact)" -ForegroundColor Green
        $certificates = Get-PACertificate -List
        foreach ($cert in $certificates)
        {
            Write-Host "`tCertificate: $($cert.Subject)" -ForegroundColor Yellow

            $domainSafe = Split-Path -Leaf (Split-Path $($cert.CertFile) -Parent)
            $path = "certPath:\$($domainSafe)"

            Write-Host "`tDestination: $($path)" -ForegroundColor Yellow

            if (-Not (Test-Path $path)) {
                New-Item $path -ItemType Directory | Out-Null
            }

            Write-Host "`t`tCopying Cert File" -ForegroundColor Blue
            Copy-Item $($cert.CertFile) $path -Force
            Write-Host "`t`tCopying Key File" -ForegroundColor Blue
            Copy-Item $($cert.KeyFile) $path -Force
            Write-Host "`t`tCopying Chain File" -ForegroundColor Blue
            Copy-Item $($cert.ChainFile) $path -Force
            Write-Host "`t`tCopying Full Cert File" -ForegroundColor Blue
            Copy-Item $($cert.FullChainFile) $path -Force
            Write-Host "`t`tCopying PFX File" -ForegroundColor Blue
            Copy-Item $($cert.PfxFil)e $path -Force
            Write-Host "`t`tCopying Full Full File" -ForegroundColor Blue
            Copy-Item $($cert.PfxFullChain) $path -Force
        }
    }

    Set-PAAccount -ID $($currentAccount.id)
}
END
{
	Remove-PSDrive -Name tokenPath -ErrorAction SilentlyContinue | Out-Null

    Write-Verbose "Leaving script $($MyInvocation.MyCommand.Name)"
    
    Stop-Transcript
}