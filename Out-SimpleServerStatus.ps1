<# 
.SYNOPSIS
	Simple HTML report generator for UP/DOWN status of servers.
.DESCRIPTION
	Create a simple UP/DOWN report, with length of uptime report in a simple HTML
	report.  Also includes a "lowest" disk alert, showing you whichever disk has the
    lowest amount of disk space and how much that is (bar graph).  There is also
    a detailed disk report you can click on to view.
    
    Will accept an secondary credential and use that to gather information.  The
    username and password are stored in an encrypted file in the path you designate.
    
    Since this script is intended to be run from a scheduled task, it is important
    to modify the PARAM section to suit your needs.  
    
    How to Run:
    Make sure to run the script once on the server you intend to run the scheduled
    task.  The script will prompt for the specified credential password on the first
    run (or any time you change the credential username).  After that first run it
    will run without prompting.
	
	*** IMPORTANT ***
    Required:  Modify the $Key variable (line 74) to get unique encryption on your
    credentials.
.PARAMETER Name
	Will accept a comma seperated array of server names and if not specified default
	to load the server names from a text file.  Make sure to edit the Param section
	to fit your environment.  Will also accept object input from Get-ADComputer.
.PARAMETER AlertThreshold
	A number representing the % that free space has to go below to trigger an alert
	(changing the display to red).
.PARAMETER Path
	The output path and file name for the HTML report.  Make sure to edit the Param 
	section to fit your environment.
.PARAMETER Credential
    Specify the alternative credential, this is a string in domain\username format.
.PARAMETER PathToCred
    Path where the script will store the encrypted password file.  Not needed if you are not
    using the Credential parameter.
.EXAMPLE
	.\Uptime.ps1
	Produces the report based on the servers in C:\utils\servers.txt and will save the
	report at c:\utils\uptime.html
.EXAMPLE
	.\Uptime.ps1 -Servers server1,server2,server3 -path \\webserver\share\uptimereport.html
	Will create the uptime report for servers 1,2 and 3 and save the report at
	\\webserver\share\uptimereport.html
.EXAMPLE
	.\Uptime.ps1 -Servers server1,server2,server3 -AlertThreshold 25
	Will create the uptime report for servers 1,2 and 3 and if the lowest disk free percentage
	is below 25% it will show up in red.
.LINK
	http://community.spiceworks.com/scripts/show/1641-simple-server-uptime-report
.NOTES
	Author:        Martin Pugh 
	Twitter:       @TheSurlyAdm1n
	Spiceworks:    Martin9700
	Blog:          www.thesurlyadmin.com
	
	Changelog
        1.8        Added CIMSession support for compatibility with 2012.  Added ability to query 
                   AD for computer description.  Added a column for Operating System.
        1.7        Added the ability to use alternative credentials.  Added quite a bit of error
                   handling and verbose output (if wanted).  Added the ability for the script to
                   accept pipeline input from Get-ADComputer as well as other pipeline items.
		1.6        Added remaining disk information in a more detailed report below the primary
	               status table.  Click on the "Show Disk Detail Report" link to display the detailed 
                   report.
		1.5        Added the "Lowest Disk Status" column.  The script will now look at all disk
	               volumes and report on the one with the lowest free disk space.  It will so the free
	               space as a percentage of the total.  By default if that percentage drops below 10%
	               it will "alert" and show that percentage in red.  This setting is configurable
	               using the -AlertThreshold parameter.
		1.0        Initial release
#>
[CmdletBinding()]
Param (
    [Parameter(ValueFromPipeline=$true,
        ValueFromPipelinebyPropertyName=$true)]
    [Alias("Servers")]
	[string[]]$Name = (Get-Content "c:\utils\servers.txt"),
	[int]$AlertThreshold = 10,
	[string]$Path = "c:\utils\uptime.html",
    [string]$Credential,
    [string]$PathToCred = "c:\utils"
)

Begin {
    #Region Functions
    Function Get-Credentials {
	    Param (
		    [String]$AuthUser = $env:USERNAME
	    )
        $Key = [byte]29,36,18,74,72,75,85,52,73,44,0,21,98,76,99,28
    
	    #Build the path to the credential file
        $CredFile = $AuthUser.Replace("\","~")
	    $File = $PathToCred + "\Credentials-$CredFile.crd"
    	#And find out if it's there, if not create it
	    If (-not (Test-Path $File))
    	{	(Get-Credential $AuthUser).Password | ConvertFrom-SecureString -Key $Key | Set-Content $File
	    }
    	#Load the credential file 
	    $Password = Get-Content $File | ConvertTo-SecureString -Key $Key
        $AuthUser = (Split-Path $File -Leaf).Substring(12).Replace("~","\")
        $AuthUser = $AuthUser.Substring(0,$AuthUser.Length - 4)
    	$Credential = New-Object System.Management.Automation.PsCredential($AuthUser,$Password)
	    Return $Credential
    }
    
    Function Get-WQLQuery
    {   [CmdletBinding()]
        Param (
            [string]$ComputerName,
            [string]$Query,
            [string]$NameSpace,
            [System.Management.Automation.PSCredential]$Credential
        )
        If (-not $NameSpace)
        {   $NameSpace = "root\CIMV2"
        }
        
        $SessionParams = @{
            ComputerName  = $ComputerName
        }
        
        $Status = $false
        If ($PSVersionTable.PSVersion.Major -gt 2)
        {   If ($PSBoundParameters["Credential"])
            {   $SessionParams.Add("Credential",$Credential)
            }
            Try {
                Write-Verbose "$($ComputerName): Attempting to connect using WSMAN..."
                $CimSession = New-CimSession @SessionParams -ErrorAction Stop
            }
            Catch {
                Write-Verbose "$($ComputerName): Unable to connect with WSMAN"
                Write-Verbose "$($ComputerName): Attempting to connect with DCOM..."
                $CimSession = New-CimSession @SessionParams -SessionOption (New-CimSessionOption -Protocol Dcom) -ErrorAction SilentlyContinue -ErrorVariable EV
            }
            If ($CimSession)
            {   Write-Verbose "$($ComputerName): Successfully connected using $($CimSession.Protocol)"
                Try {
                    $Object = Get-CimInstance -CimSession $CimSession -Query $Query -ErrorAction Stop -Namespace $NameSpace
                }
                Catch {
                    $ErrorText= $Error[0]
                    $Status = $true
                }
            }
            Else
            {   Write-Warning "$($ComputerName): Unable to connect with DCOM"
                $ErrorText= $Error[0]
                $Status = $true
            }
        }
        Else
        {   Write-Verbose "$($ComputerName): Powershell 2.0 or older detected on host, attempting to connect with WMI..."
            If ($PSBoundParameters["Credential"] -and $ComputerName -ne $Env:COMPUTERNAME)
            {   $SessionParams.Add("Credential",$Credential)
            }
            Try {
                $Object = Get-WmiObject @SessionParams -Query $Query -ErrorAction Stop
            }
            Catch {
                Write-Warning "$($ComputerName): Unable to connect with WMI"
                $ErrorText= $Error[0]
                $Status = $true
            }
        }
        
        If ($Status)
        {   Write-Warning "$($ComputerName): Failed to get query information"
            New-Object PSObject -Property @{
                Computer = $ComputerName
                ErrorStatus = $Status
                Error = $ErrorText
                Object = $null
            }
        }
        Else
        {   ForEach ($Line in $Object)
            {   New-Object PSObject -Property @{
                    Computer = $ComputerName
                    ErrorStatus = $Status
                    Error = $ErrorText
                    Object = $Line
                }
            }
        }   
    }
    #EndRegion
    
    #Load RSAT, if available
    Try { Import-Module ActiveDirectory -ErrorAction Stop }
    Catch { Write-Host "Unable to load Active Directory module, is RSAT installed?"; Exit }

    Write-Verbose "$(Get-Date): Script begins!"
    $Error.Clear | Out-Null

    #Define static HTML
    $HeaderHTML = @"
<html>
<head>
<style type='text/css'>
body { background-color:#DCDCDC;
}
table { border:1px solid gray;
  font:normal 12px verdana, arial, helvetica, sans-serif;
  border-collapse: collapse;
  padding-left:30px;
  padding-right:30px;
}
th { color:black;
  text-align:left;
  border: 1px solid black;
  font:normal 16px verdana, arial, helvetica, sans-serif;
  font-weight:bold;
  background-color: #6495ED;
  padding-left:6px;
  padding-right:6px;
}
td.up { background-color:#32CD32;
  border: 1px solid black;
}
td.down { background-color:#B22222;
  border: 1px solid black;
}
td { border: 1px solid black;
  padding-left:6px;
  padding-right:6px;
}
div.red { background-color:#B22222;
  float:left;
  text-align:right;
}
div.green { background-color:#32CD32;
  float:left; 
}
div.free { background-color:#7FFF00;
  float:left;
  text-align:right;
}
a.detail { cursor:pointer;
  color:#1E90FF;
  text-decoration:underline;
}
</style>
</head>
<body>
<script type='text/javascript'>
<!--
window.onload=function(){
	document.getElementById("ShowHideLink").innerHTML="<h6>Show Disk Detail Report</h6>"
	document.getElementById("diskdetail").style.visibility="hidden"
}
function ShowHide() {
	if (document.getElementById("diskdetail").style.visibility=="visible")
	{
		document.getElementById("diskdetail").style.visibility="hidden"
		document.getElementById("ShowHideLink").innerHTML="<h6>Show Disk Detail Report</h6>"
	}
	else
	{
		document.getElementById("diskdetail").style.visibility="visible"
		document.getElementById("ShowHideLink").innerHTML="<h6>Hide Disk Detail Report</h6>"
	}
 }
//-->
</script>
<h1>Server Uptime Status Report - $(Get-Date)</h1>
<p>
<table class="Main">
<tr><th style="width:125px;">Server Name</th><th style="width:150px;">Description</th><th>OS</th><th style="width:125px;">Status</th><th style="width:475px;">Lowest Disk Status</th></tr>

"@

    $DiskDetailHeaderHTML = @"
</table>
<a id="ShowHideLink" class="detail" onClick="ShowHide()"></a>
<br>
<br>
<div id="diskdetail">
<h1>Disk Detail Report</h1><p>

"@

    $FooterHTML = @"
</div>
</body>
</html>
"@

    $AllComputers = @()
}

Process {
    #Gather all computer names before processing
    ForEach ($Computer in $Name)
    {   $AllComputers += $Computer
    }
}

End {
    #Sort the servers by name, then start getting information
    Write-Verbose "Sort server names and gather Credential information"
    $AllComputers = $AllComputers | Sort
    $DiskData = @()

    $ParamSplat = @{
        Query = "Select DeviceID,Size,FreeSpace,VolumeName From Win32_LogicalDisk where DriveType = '3'"
    }
    If ($Credential)
    {   $Cred = Get-Credentials $Credential
        $ParamSplat.Add("Credential",$Cred)
    }

    ForEach ($Computer in $AllComputers)
    {	Write-Verbose "Testing $Computer..."
        $OS = ""
        $Description = ""
        $ErrorReport = $null
	    If (Test-Connection $Computer -Quiet -Count 2)
    	{	#Get uptime information
            $WMI = Get-WQLQuery -ComputerName $Computer -Query "Select LastBootUpTime,Caption From Win32_OperatingSystem"
            If ($WMI.ErrorStatus)
            {   Write-Verbose "Error encountered gathering information for $Computer"
                $UpText = "<td class=""up"">Up</td>"
                $ErrorReport = $WMI.Error
            }
            Else
            {   If (($WMI.Object.LastBootUpTime.GetType()).Name -eq "DateTime")
                {   $StartDate = $WMI.Object.LastBootUpTime
                }
                Else
                {   $StartDate = $($WMI.Object.ConvertToDateTime($WMI.Object.LastBootUpTime))
                }
                $Uptime = New-TimeSpan -Start $StartDate -End (Get-Date)
			    $UpText = "<td class=""up"">$($Uptime.Days)d, $($Uptime.Hours)h, $($Uptime.Minutes)m</td>"
                $OS = $WMI.Object.Caption
                
                #Get disk information and pretty up the data
                Try {
                    $Description = (Get-ADComputer $Computer -Properties Description -ErrorAction Stop).Description
                }
                Catch {
                    $Description = ""
                }
                $Disks = Get-WQLQuery -ComputerName $Computer @ParamSplat | Select `
    	    	    @{LABEL="Server";EXPRESSION={$Computer}},
                    @{LABEL="DriveLetter";EXPRESSION={$_.Object.DeviceID}},
			        @{LABEL="Size";EXPRESSION={[int]("{0:N0}" -f ($_.Object.Size/1gb))}},
    			    @{LABEL="FreeSize";EXPRESSION={[int]("{0:N0}" -f ($_.Object.FreeSpace/1gb))}},
	    		    @{LABEL="perUsed";EXPRESSION={[int]("{0:N0}" -f ((($_.Object.Size - $_.Object.FreeSpace)/$_.Object.Size)*100))}},
		    	    @{LABEL="perFree";EXPRESSION={[int]("{0:N0}" -f (100-(($_.Object.Size - $_.Object.FreeSpace)/$_.Object.Size)*100))}},
			        VolumeName
                $DiskData += $Disks
            }
            
    	    #Create the simple Status table
            If ($ErrorReport)
            {   $UpText = "<td class=""down"">WMI Error</td>"
                $DiskHTML = "<div class=""red"">$($Error[0])</div>"
            }
    		ElseIf ($Disks)
        	{	$LowDisk = $Disks | Sort FreeSize | Select -First 1
    	    	If ($LowDisk.perFree -le $AlertThreshold)
    		   	{	$FreeClass = "red"
    		    }
        		Else
    	    	{	$FreeClass = "free"
    		   	}
    		    $DiskHTML = "<div class=""green"" style=""width:$($LowDisk.perUsed)%"">$($LowDisk.DriveLetter) $($LowDisk.Size)gb ($($LowDisk.perUsed)% used)</div><div class=""$FreeClass"" style=""width:$($LowDisk.perFree)%"">$($LowDisk.FreeSize)gb free ($($LowDisk.perFree)%)</div>`n"
    		}
    		Else
    		{	$DiskHTML = ""
    		}
    		$DetailHTML += "<tr><td>$Computer</td><td>$Description</td><td>$OS</td>$UpText<td>$DiskHTML</td></tr>`n"
    	}
    	Else
    	{	$DetailHTML += "<tr><td class=""down"">$Computer</td><td class=""down"">$Description</td><td class=""down"">$OS</td><td class=""down"">DOWN</td><td class=""down""></td></tr>`n"
    	}
    }

    #Disk Details Report
    Write-Verbose "WMI data gathered, making the report"
    $Servers = $DiskData | Select Server -Unique
    ForEach ($Server in $Servers)
    {	$Server = $Server.Server
    	$DiskDetailHTML += "<h3>$Server</h3>"
    	$DiskDetailHTML += "<table>"
    	$DiskDetailHTML += "<tr><th>Drive Letter</th><th>Volume Name</th><th>Total Disk Space</th><th>Used</th><th>Free</th><th style=""width:350px;"">Usage</th></tr>`n"
    	$Disks = $DiskData | Where { $_.Server -eq $Server } | Sort DriveLetter
    	ForEach ($Disk in $Disks)
    	{	$DiskDetailHTML += "<tr><td>$($Disk.DriveLetter)</td><td>$($Disk.VolumeName)</td><td>$($Disk.Size)gb</td><td>$($Disk.Size - $Disk.FreeSize)gb</td><td>$($Disk.FreeSize)gb</td>"
    		If ($Disk.perFree -le $AlertThreshold)
    		{	$FreeClass = "red"
    		}
    		Else
    		{	$FreeClass = "free"
    		}
    		$DiskDetailHTML += "<td><div class=""green"" style=""width:$($Disk.perUsed)%"">&nbsp;</div><div class=""$FreeClass"" style=""width:$($Disk.perFree)%"">$($Disk.perFree)%</div></td></tr>`n"
    	}
    	$DiskDetailHTML += "</table><br>`n"
    }

    #Combine all the HTML fragments and save to a file
    $HTML = $HeaderHTML + $DetailHTML + $DiskDetailHeaderHTML + $DiskDetailHTML + $FooterHTML
    $HTML | Out-File $Path
    & $Path

    Write-Verbose "$(Get-Date): Script completed!"
}