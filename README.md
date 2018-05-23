# SharePoint Kerberos Configurator

## Features
- Creates a SPN configuration script for your farm
- Checks for Host Named Site Collections where every used name needs an SPN
- Checks if the URLs are registered as A records in DNS
- Checks for non-standard ports (other than 80 and 443) due to known issues with Kerberos
- Also adds SPNs for other services like 
    - C2WTS (Claims to Windows Token Service)
- Runs the created SPN configuration with provided Domain Admin credentials (optional)

## Usage

There ~~are~~ will be two ways to use this script. The easiest is the interactive mode where this script goes through your Web Applications and gives you a script for correctly configuring your environment.

### Interactive mode (recommended)

1. Run a PowerShell on one of your SharePoint Servers as a Farm Administrator

    .\SPKerberosConfigurator.ps1

2. You'll get a configuration script that your Domain Administrator can run to set the SPN entries for your farm (by default this will be "ConfigureSPN.ps1")

### Script mode

_not implemented yet_

### Parameters

| Parameter                    | Type        | Description                                                 | Default          | Allowed Values                                |
| ---------------------------- | ----------- | ----------------------------------------------------------- | ---------------- | --------------------------------------------- |
| ~~Step~~                     | ValidateSet | Tells the script which step to run                          | -                | TestSPConfig, TestSPNEntries, CreateSPNScript |
| FileName                     | String      | The name for the SPN script or CSV file                     | ConfigureSPN.ps1 |                                               |
| IncludeCentralAdministration | Bool        | Will also create SPN entries for the Central Administration | $false           | $true, $false                                 |
| OutputFormat                 | ValidateSet | Sets the desired output format                              | Script           | Script, CSV                                   |


## Limitations and Known Issues

- Only works for Accounts in the same domain as the SharePoint Servers
- Not tested against SharePoint 2010 yet
- Alternate Access Mappings are not considered
- Claims to Windows Token Service delegation for SQL service SPNs are not added


## Manual steps
This script does not automate the whole process. There are some manual steps to do after running the configuration script
- If the Claims to Windows Token Service is used, you have to trust the corresponding service account for delegation of the SQL Service (see: https://support.microsoft.com/en-us/help/2722087/how-to-configure-claim-to-windows-token-services-in-sharepoint-2010-wi)

## Next steps

I'll implement the following features in the future

- [ ] Checking the current Kerberos configuration for Web Applications
- [ ] Checking if neccessary Kerberos SPNs are correctly set or already registered
- [ ] Adding SPNs for other services like 
    - [ ] Excel Services (only for SharePoint 2010 and SharePoint 2013 because it's integrated in Office Online Server for SharePoint 2016)
    - [ ] Reporting Services
    - [ ] PowerPivot
    - [ ] PerformancePoint Services
- [ ] Creating an SPN for your App / Add-in domain

