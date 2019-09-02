# Get a list of Let's Enrypt SSL Certificates that are still valid
$certs = (dir cert:\localmachine\my | ? { $_.Issuer -Like "*Let's*" -and $_.NotAfter -ge [DateTime]::Now })

# Get a list of HTTPS website bindings
$webSites = Get-WebBinding | ? { $_.Protocol -eq "https" }

$certs | % {
	$c = $_;
	$hash = $_.Thumbprint
	Write-Host "Cert: $($c.Subject) [$($c.Thumbprint)]" -ForegroundColor Yellow
		
	$c.DnsNameList | % { 
		$dnsName = $($_.Punycode);
		#Write-Host "`tDns Name: $($dnsName)"
		$webSites | % {
			$s = $_
			
			[bool] $found = $false
			$s.bindingInformation | % {
				$b = $_;
				#Write-Host "`t`tB: $($b)" -ForegroundColor Yellow
				if ($b -like "*$($dnsName)*") {
					#Write-Host "`t`tFound Matching Binding: $($b)" 
					
					$found = $true
				}
			}
			
			if ($found -eq $true) {
				# Rebind the SSL cert to the website
				Write-Host "`tSetting Binding for $($b) to [$($hash)]" -ForegroundColor Yellow
				$s.AddSSLCertificate($($hash), "My")
			} else {
				#Write-Warning "No Binding Found. $($s)" -ForegroundColor Red
			}
		}
	}
}
