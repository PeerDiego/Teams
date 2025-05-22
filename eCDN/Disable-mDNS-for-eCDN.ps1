<#
.SYNOPSIS
This script configures a Windows computer for Microsoft eCDN.

.DESCRIPTION
This script adds registry keys to a Windows computer for disabling WebRTC's IP obfuscation behavior solely for the domains required by Microsoft eCDN on the following browsers:
    - Microsoft Edge
    - Google Chrome
    - Mozilla Firefox

Without these registry keys (or other applicable configurations) the browsers will obfuscate the viewer's IP address which will ultimately prevent the eCDN client from connecting to peers.

.PARAMETER eCDN_domain
The domain to add to the registry keys. Default is *.ecdn.teams.microsoft.com, *.ecdn.teams.cloud.microsoft, https://teams.microsoft.com and https://teams.cloud.microsoft

.EXAMPLE
.\Disable-mDNS-for-eCDN.ps1
# This will add the default eCDN domains to the relevant registry keys
.EXAMPLE
.\Disable-mDNS-for-eCDN.ps1 -eCDN_domain "https://teams.cloud.microsoft"
# This will add the specified domain to the relevant registry keys

.EXAMPLE
.\Disable-mDNS-for-eCDN.ps1 -Enumerated
# This will enumerate all eCDN domains in the registry keys instead of using wildcards (*)

.NOTES
Must be run as an Administrator.
As of May 22nd 2025, the upcoming .cloud.microsoft domain migration targets were added to this script.
By July 1st 2025, the domain migration should be complete and the old domains will be deprecated.
Author: Diego Reategui | Github username: PeerDiego

.OUTPUTS
None

.INPUTS
None

.LINK
See more regarding disabling mDNS for Microsoft eCDN here: https://learn.microsoft.com/ecdn/how-to/disable-mdns
This script is based on a version by Alexusa75 found here: https://github.com/alexusa75/Teams
#>
[cmdletbinding(DefaultParameterSetName="Default")] 
param(
    [Parameter(
        Mandatory=$false, 
        ParameterSetName="Default", 
        HelpMessage="Specify the eCDN domain to add to the registry keys. Default is *.ecdn.teams.microsoft.com, *.ecdn.teams.cloud.microsoft, https://teams.microsoft.com and https://teams.cloud.microsoft")]
    [string]
    $eCDN_domain,
    [Parameter(
        ParameterSetName="Add all", 
        HelpMessage="Enumerate all eCDN domains in the registry keys instead of using a wildcard (*)")]
    [switch]
    $Enumerated = $false
)

if (-not [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")) {
    Write-Host "This script must be run as an Administrator" -ForegroundColor Red
    return
}

$all_eCDN_Domains = @{
    "Default" = @(
        "*.ecdn.teams.microsoft.com",
        "*.ecdn.teams.cloud.microsoft"
    )
    "Enumerated" = @(
        "https://sdk.ecdn.teams.microsoft.com",
        "https://sdk.ecdn.teams.cloud.microsoft",
        "https://sdk.msit.ecdn.teams.microsoft.com",
        "https://sdk.msit.ecdn.teams.cloud.microsoft"
    )
    "Constant" = @(
        "https://teams.microsoft.com",
        "https://teams.cloud.microsoft"
    )
}

$Domains_to_add = switch ($eCDN_domain) {
    ({-not $eCDN_domain -and -not $Enumerated}) {
        $all_eCDN_Domains["Constant"] + $all_eCDN_Domains["Default"]
    }
    ({$Enumerated}) {
        $all_eCDN_Domains["Constant"] + $all_eCDN_Domains["Enumerated"]
    }
    default { @($eCDN_domain) }
}

$HKLM_SW_Policies_Path = "HKLM:\SOFTWARE\Policies"


$browser_list = @(
    @{
        name = "Microsoft Edge";
        executable = "msedge.exe"; 
        reg_path = "$HKLM_SW_Policies_Path\Microsoft\Edge"; # keeping here for reference
        webRTCkey = "WebRtcLocalIpsAllowedUrls"
    },
    @{
        name = "Google Chrome";
        executable = "chrome.exe"; 
        reg_path = "$HKLM_SW_Policies_Path\Google\Chrome";
        webRTCkey = "WebRtcLocalIpsAllowedUrls"
    },
    @{
        name = "Mozilla Firefox";
        executable = "firefox.exe"; 
        reg_path = "$HKLM_SW_Policies_Path\Mozilla\Firefox";
        webRTCkey = "Preferences"
    }
)
function _create_RegKey_if_not_exists($key_path) {
    $key = Get-Item -Path $key_path -ErrorAction SilentlyContinue
    if (!$key) {
        New-Item -Path $key_path -ErrorAction SilentlyContinue -Force | Out-Null
        Write-Verbose "Created key: $key_path"
    }
    else {
        Write-Verbose "Key already exists: $key_path"
    }
}


function Add-WebRtcLocalIpsAllowedUrl {
    param (
        [Parameter(Mandatory=$true, HelpMessage="URL is required")]
        [string] $URL,

        [Parameter(Mandatory=$true, HelpMessage="Browser is required")]
        # [ValidateSet("Microsoft Edge", "Google Chrome", "Mozilla Firefox")]
        $Browser #= "Microsoft Edge"
    )
    Write-Verbose "Adding to $($Browser.name)'s WebRTC Local IPs Allowed URLs list $URL"
    $browser_path = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$($Browser.executable)" -ErrorAction SilentlyContinue).'(Default)'
    if ($browser_path) {
        $browser_version = (Get-Item -Path $browser_path -ErrorAction SilentlyContinue).VersionInfo
        if ($browser_version) {
            Write-Host " $($Browser.name) v.$($browser_version.FileVersion) found " -ForegroundColor DarkGray # -BackgroundColor White -ForegroundColor Black # at $browser_path" -ForegroundColor Yellow
        }
        else {
            Write-Host " $($Browser.name) purportedly installed but unable to determine version info." -BackgroundColor Red -ForegroundColor White
            Write-Host "Proceeding with adding registry key(s) to disable mDNS for $($Browser.name) Browser" -ForegroundColor Yellow
        }

        # create the registry keys if they don't exist
        $Browser_Company, $Browser_Name = $Browser.name.Split()
        $Company_KeyPath = Join-Path $HKLM_SW_Policies_Path $Browser_Company
        _create_RegKey_if_not_exists $Company_KeyPath

        $Browser_KeyPath = Join-Path $Company_KeyPath $Browser_Name
        _create_RegKey_if_not_exists $Browser_KeyPath

        $WebRtcLocalIpsAllowedUrls_KeyPath = Join-Path $Browser_KeyPath $Browser.webRTCkey
        _create_RegKey_if_not_exists $WebRtcLocalIpsAllowedUrls_KeyPath

        $WebRtcLocalIpsAllowedUrls  = Get-Item -Path $WebRtcLocalIpsAllowedUrls_KeyPath -ErrorAction SilentlyContinue
        if (!$WebRtcLocalIpsAllowedUrls) {
            Write-Host "Failed to create key(s) >_>" -ForegroundColor Red
            return
        }
        $value_names = $WebRtcLocalIpsAllowedUrls.GetValueNames()
        foreach ($value_name in $value_names) {
            $value = $WebRtcLocalIpsAllowedUrls.GetValue($value_name)
            Write-Verbose "Found $($WebRtcLocalIpsAllowedUrls.GetValueKind($value_name)) $value_name with value $value"
            if ($value -eq $URL) {
                Write-Host "eCDN domain already exists in $($WebRtcLocalIpsAllowedUrls.GetValueKind($value_name)) $value_name" -ForegroundColor DarkGreen
                return
            }
        }
        # create new value
        $value_name = $value_names.Count + 1
        while ($value_name -in $value_names) {
            $value_name++
        }
        try {
            if ($Browser_Name -eq "Firefox") {
                $value_name = 'media.peerconnection.ice.obfuscate_host_addresses.blocklist'
                
                # check if the value already exists within a list of domains
                if ($values = $WebRtcLocalIpsAllowedUrls.GetValue($value_name)) {
                    $values = $values.split(",").foreach({$_.trim()})
                    if ($values -contains $URL) {
                        Write-Host "eCDN domain already exists in $($WebRtcLocalIpsAllowedUrls.GetValueKind($value_name)) $value_name" -ForegroundColor DarkGreen
                        return
                    }
                    $URL = $values + $URL -join ", "
                }
            }
            New-ItemProperty -Path $WebRtcLocalIpsAllowedUrls_KeyPath -Name $value_name -PropertyType String -Value $URL -ErrorAction Stop -Force | Out-Null
            Write-Verbose "eCDN domain added to $($WebRtcLocalIpsAllowedUrls.GetValueKind($value_name)) $value_name"
            Write-Host "Registry key to disable mDNS for $Browser_Name Browser was created" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to create registry key to disable mDNS for $Browser_Name Browser" -ForegroundColor Red
        }
    }
    else {
        Write-Host " $($browser.name) not found" -BackgroundColor DarkGray -ForegroundColor Black
        return
    }
}

foreach ($domain in $Domains_to_add) {
    Write-Host "Adding to allowed eCDN domains lists $domain" -ForegroundColor Yellow
    foreach ($browser in $browser_list) {
        . Add-WebRtcLocalIpsAllowedUrl -URL $domain -Browser $browser
        Write-Host ""
    }
    Write-Host ""
}
