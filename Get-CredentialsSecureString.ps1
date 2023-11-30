param(
    [pscredential]$Credentials = (Get-Credential -Message "Enter Network Path Credentials" -UserName $env:USERNAME )
)

ConvertFrom-SecureString $Credentials.Password

# $SettingsFile=".\copy-certificates.settings.json"

# $settings = (Get-Content -Path $SettingsFile | ConvertFrom-Json)

# if ($null -ne $settings.passwordSecure -and $settings.passwordSecure.Length -gt 0) { $PathPasswordSecure = ConvertTo-SecureString $($settings.passwordSecure) }

# if ($null -eq $PathPasswordSecure -and $null -ne $PathPassword) {
#     $PathPasswordSecure = ConvertTo-SecureString -String $PathPassword -AsPlainText -Force
# }

# $PathCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($PathUserName, $PathPasswordSecure)

# $PathCredentials.GetNetworkCredential().Password