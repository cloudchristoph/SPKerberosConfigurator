param(
    # Filename for exported SPN configuration script
    [Parameter()]
    [string]
    $FileName = "ConfigureSPN.ps1",

    # Step to run
    [Parameter()]
    [ValidateSet("TestSPConfig", "TestSPNEntries", "CreateSPNScript")]
    $Step = $null,

    # IncludeCentralAdministration
    [Parameter()]
    [bool]
    $IncludeCentralAdministration = $false,

    [Parameter()]
    [ValidateSet("Script", "CSV")]
    $OutputFormat = "Script"

)

Set-StrictMode -Version Latest

function CreateSpnEntry {
    param(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
        [string]$ServiceClass = "HTTP",
		[Parameter()]
		[ValidateNotNullOrEmpty()]
        [string]$Hostname = "",
        [string]$Port = "",
		[Parameter(Mandatory=$true)]
        [string]$Username
    )

    $SpnString = $ServiceClass + "/" + $Hostname
    if (-not [string]::IsNullOrEmpty($Port) -and $Port -ne 80 -and $Port -ne 443) {
        $SpnString += ":" + $Port
    }

    return @{
        UserName = $Username
        SpnString = $SpnString
    }
}

function GetNonHostHeaderWebApp {
    # TODO - find Binding with no host header other than CA
    
    $webApplications = Get-SPWebApplication
    foreach ($webApplication in $webApplications) {
        write-host "webapp $($webApplication.Url)"
        foreach ($settings in $webApplication.IisSettings) {
            foreach ($binding in $settings.ServerBindings) {
                if ($binding.HostHeader -eq "") {
                    return $webApplication
                }
            }
        }
    }
    
    #$webapp.IisSettings[0].ServerBindings
    
}

function FindSPN {
    # TODO - Filter account for SPN

    $search = New-Object DirectoryServices.DirectorySearcher([ADSI]"")
    $search.filter = "(servicePrincipalName=*)"
    $results = $search.Findall()
    $results

}

function PromptYesNo {
    param(
        [string]$Title,
        [string]$Message
    )

    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Yes"
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "No"
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    $choice = $Host.ui.PromptForChoice($Title, $Message, $options, 1)

    return ($choice -eq 0)
}

try {

    Add-PSSnapIn Microsoft.SharePoint.PowerShell

    [System.Collections.ArrayList]$SpnCollection = @()

    Write-Host "Trying to get the SharePoint Farm..."
    $farm = Get-SPFarm -ErrorAction Stop
    $SharePointVersion = $farm.BuildVersion.Major

    Write-Host "Getting Web Applications..."
    if ($IncludeCentralAdministration) {
        $webApplications = Get-SPWebApplication -IncludeCentralAdministration -ErrorAction Stop
    } else {
        $webApplications = Get-SPWebApplication -ErrorAction Stop
    }

    foreach ($webApplication in $webApplications) {

        # Is central admin?
        #if ($webApplication.IsAdministrationWebApplication) {
        #}

        $Url = [System.Uri]$webApplication.Url
        write-host $Url

        # Port other that 80 or 443 - not recommended
        if ($Url.Port -ne 80 -and $Url.Port -ne 443) {
            Write-Warning ("The Web Application '" + $webApplication.DisplayName + "' uses a port other than 80 or 443; There are known problems with Kerberos if you're using non-standard ports.")
        }

        # DNS is registered as A records?
        write-host "Checking DNS entry for $($Url.Host)..."
        $dns = Resolve-DnsName -Name $Url.Host -NoHostsFile -Type All -ErrorAction SilentlyContinue
        if ($null -ne $dns) {
            if ($dns.Type -ne "A") {
                Write-Warning ("The URL " + $Url.Host + " is registered with a " + $dns.Type + " record. Consider changing this entry to an A record because there are known issues (see: https://technet.microsoft.com/en-us/library/gg502606(v=office.14).aspx)")
            }
        } else {
            Write-Warning ("The URL " + $Url.Host + " seems to have no DNS record. Consider adding an A record.")
        }

        # Add to collection
        $SpnCollection.Add((CreateSpnEntry -Hostname $Url.Host -Port $Url.Port -Username $webApplication.ApplicationPool.Username));        

    }

    # AppDomain - get WebApp w/o HostHeader Binding
    # C2WTS
    Get-SPServiceInstance | Where-Object { $_.TypeName -eq "Claims to Windows Token Service" } | ForEach-Object {
        if ($_.Status -ne "Disabled") {
            write-host "Found activated Claims to Windows Token Service, adding SPN..."
            $SpnCollection.Add((CreateSpnEntry -ServiceClass "SP" -Hostname "C2WTS" -Username $_.Service.ProcessIdentity.Username));            
            return
        }
    }

    # Excel Services - only for SP 2010 and 2013, because it is integrated in OOS for SP 2016
    if ($SharePointVersion -lt 16) {
    }
    # Reporting Services
    Get-SPServiceInstance | Where-Object { $_.TypeName -eq "SQL Server Reporting Services Service" } | Select -Last 1 | ForEach-Object {
        write-host "Found installed Reporting Services, getting Service Application and adding SPN..."
        $sa = Get-SPRSServiceApplication        
        $SpnCollection.Add((CreateSpnEntry -ServiceClass "SP" -Hostname "SSRS" -Username $sa.ApplicationPool.ProcessAccountName));
    }

    # PowerPivot
    # PerformancePoint Services

    # Host Named Site Collections
    write-host "Getting Host Named Site Collections..."
    Get-SPSite -Limit All | Where-Object { $_.HostHeaderIsSiteName -eq $true} | ForEach-Object {

        if ($_.IsSiteMaster) {
            return
        }
        $Url = [System.Uri]$_.Url
        $SpnCollection.Add((CreateSpnEntry -Hostname $Url.Host -Port $Url.Port -Username $_.WebApplication.ApplicationPool.Username));
    }

    if ($OutputFormat -eq "Script") {
        "# Script for configuring SPN" | Out-File -FilePath $FileName
        foreach ($entry in $SpnCollection) {
            ("setspn -S " + $entry["SPNString"] + " " + $entry["UserName"]) | Out-File -FilePath $FileName -Append
        }
    } elseif ($OutputFormat -eq "CSV") {
        $SpnCollection | Export-Csv -Path $FileName -NoTypeInformation -Delimiter ";"
    }

    # Start Configuration script
    if (PromptYesNo -Title "Run the created SPN configuration script?" -Message "You'll need Domain Admin or Enterprise Admin credentials to run this script.") {
        write-host "Running script with new credentials..."
        Start-Process powershell.exe -ArgumentList ("-file $FileName") -RunAs (Get-Credential -Message "Domain Admin or Enterprise Admin account")
    } else {
        write-host "Skipped script execution"
    }


}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName

    Write-Error $ErrorMessage
    Write-Error $FailedItem
}