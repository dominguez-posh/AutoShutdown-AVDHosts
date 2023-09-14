param($Timer)

$AVDVMs=@(
    "AVDRDS01"
    "AVDRDS02"
)#VMs auswählen die berücksichtigt werden sollen

$MaxIdleTime = 90 #Minutes, when idling sessions will be disconnected
$MaxDisconnectTime = 10 # Minutes, after disconnected Sessions will be Logged Off
$VMStartOffset = 10 # Minute offset after VM Start, when the script will do anything. 

###################################################################################################
#START FUNCTION

function Get-ActiveAVDSessions{
Param(
    $AVDHost = ""
)

$AVDHost = $AVDHost + ("*")

$ResourceGroups = Get-AzResourceGroup

$HostPools = @()
$SessionHosts = @()
$UserSessions = @()
$ActiveSessions = @()
foreach($ResourceGroup in $ResourceGroups){$HostPools += Get-AzWvdHostPool -ResourceGroupName $ResourceGroup.ResourceGroupName}

foreach($HostPool in $HostPools)
    {
        $SessionHosts += Get-AzWvdSessionHost -HostPoolName $HostPool.Name  -ResourceGroupName ($HostPool.id -split "resourcegroups/" -split "/providers")[1]

            foreach($SessionHost in $SessionHosts){
                try{$Usersession = Get-AzWvdUserSession -HostPoolName $HostPool.Name -ResourceGroupName ($HostPool.id -split "resourcegroups/" -split "/providers")[1] -SessionHostName ($SessionHost.Name.split("/"))[1]}catch{}
                if($Usersession){
                    $ActiveSession = [PSCustomObject]@{
                        "HostName" = $Usersession.name.Split("/")[1]
                        "UserPrincipalName" = $Usersession.UserPrincipalName
                        "ActiveDirectoryUserName" = $Usersession.ActiveDirectoryUserName
                        "ApplicationType" = $Usersession.ApplicationType
                        "SessionState" = $Usersession.SessionState
                        "SessionID" = $Usersession.Id
                    }
                    $ActiveSessions += $ActiveSession
                }
            }
    }


return $ActiveSessions | ? Hostname -like $AVDHost
}

function Invoke-AVDShutdownVM{
Param(
    $AVDHostName
)

$VM = Get-AZVM $AVDHostName -Status

if($VM.PowerState -notlike "*running*"){

write-Host "VM NOT RUNNING !"
return 0

}



$ResourceGroups = Get-AzResourceGroup

$HostPools = @()
$SessionHosts = @()

foreach($ResourceGroup in $ResourceGroups){$HostPools += Get-AzWvdHostPool -ResourceGroupName $ResourceGroup.ResourceGroupName}

foreach($HostPool in $HostPools)
    {
        $SessionHosts += Get-AzWvdSessionHost -HostPoolName $HostPool.Name  -ResourceGroupName ($HostPool.id -split "resourcegroups/" -split "/providers")[1]
    }

$SessionHost = $SessionHosts | ? Name -Like ("*" + $AVDHostName + "*")

$ActiveSessions = Get-ActiveAVDSessions -AVDHost $AVDHostName

if($ActiveSessions -eq $Null){
    
    Write-Host "Turning on Drainmode for Session Host" $SessionHosts.Name
    $SessionHost | Update-AzWvdSessionHost -AllowNewSession:$false #Bringing SessionHost in Drain Mode

    Write-Host "Waiting 10 Seconds befor checking User Activity Again"

    Start-Sleep 10

    $ActiveSessions = Get-ActiveAVDSessions -AVDHost $AVDHostName

    if($ActiveSessions -eq $Null){ #Session Host has no active Sessions
    
        $VM | Stop-AzVM -Force #Stopping VM


        Write-Host "Turning off Drainmode for Session Host" $SessionHosts.Name
        $SessionHost | Update-AzWvdSessionHost -AllowNewSession:$true #Turning Drainmode Off

        
    }
    else{
        Write-Host "Active Sessions Found. Not Turning off VM"
    }


}
else{
    Write-Host "Active Sessions Found. Not Turning off VM"
}

Return Get-AZVM $AVDHostName -Status


}



$Content = @'
$MaxIdleTime = <MaximumIdleTime>
$MaxDisconnectTime = <MaximumDisconnectTime>
$VMStartOffset = <VMStartOffset>

Function Get-QueryUser(){
Param()
    $HT = @()
    $Lines = @(query user).foreach({$(($_) -replace('\s{2,}',','))}) # REPLACES ALL OCCURENCES OF 2 OR MORE SPACES IN A ROW WITH A SINGLE COMMA
    $header=@(
    "username"
    "sessionname"
    "id"
    "status"
    "idle"
    "logontime"
    )  
    
    for($i=1;$i -lt $($Lines.Count);$i++){ # NOTE $i=1 TO SKIP THE HEADER LINE
        $Res = "" | Select-Object $header # CREATES AN EMPTY PSCUSTOMOBJECT WITH PRE DEFINED FIELDS
        $Line = $($Lines[$i].split(',')).foreach({ $_.trim().trim('>') }) # SPLITS AND THEN TRIMS ANOMALIES 
        if($Line.count -eq 5) { $Line = @($Line[0],"$($null)",$Line[1],$Line[2],$Line[3],$Line[4] ) } # ACCOUNTS FOR DISCONNECTED SCENARIO
            for($x=0;$x -lt $($Line.count);$x++){
                $Res.$($header[$x]) = $Line[$x] # DYNAMICALLY ADDS DATA TO $Res
            }

            try{$logonTime = [datetime]::ParseExact($Res.logontime, "dd.MM.yyyy HH:mm", $null)} catch{}
            try{$logonTime = [datetime]::ParseExact($Res.logontime, "yyyy-MM-dd HH:mm:ss", $null)}catch{}

            if($Res.status -like "a*"){
                $UserActive = $True
            }
            else{
                $UserActive = $False
            }

            
            if($res.idle -eq "."){$IdleTime = "0"}
            else{ $IdleTime = $res.idle}
            

            $Session = [PSCustomObject]@{
            "sessionid" = $res.id 
            "username" = $res.username
            "idletime" = [convert]::ToInt32($IdleTime.replace(" ",""), 10)
            "sessionname"  = $Res.sessionname
            "useractive" = $UserActive
            "logontime" = $logonTime
            "userinformedforlogoff" = $false
            }
        $HT += $Session # APPENDS THE LINE OF DATA AS PSCUSTOMOBJECT TO AN ARRAY
        Remove-Variable Res # DESTROYS THE LINE OF DATA BY REMOVING THE VARIABLE
        Remove-Variable Session
    }
    return $HT
}

$Users = Get-QueryUser

foreach($User in $Users){
    if($User.useractive){ #Check if user is active
        if($User.idletime -ge $MaxIdleTime){# Check if Active Session is idling Longer Than Max Idling Time
            
            $Content = '
            $SessionID = <SessionID>
            $MaxIdleTime = <MaxIdleTime>

            $UserIdleTime = $((@(query user $SessionID)[1].foreach({$(($_) -replace("\s{2,}",","))})).split(",")).foreach({ $_.trim().trim(">") })[4]
            if($UserIdleTime -eq "."){$UserIdleTime = "0"}
            $UserIdleTime = [convert]::ToInt32($UserIdleTime.replace(" ",""), 10)

            msg $SessionID /TIME:10 "Sitzung wird in 15 Sekunden wegen Inaktivitaet getrennt. Zum abbrechen auf OK klicken"
            Start-Sleep 15

            $UserIdleTime = $((@(query user $SessionID)[1].foreach({$(($_) -replace("\s{2,}",","))})).split(",")).foreach({ $_.trim().trim(">") })[4]
            if($UserIdleTime -eq "."){$UserIdleTime = "0"}
            $UserIdleTime = [convert]::ToInt32($UserIdleTime.replace(" ",""), 10)

            if($UserIdleTime -ge $MaxIdleTime){
                msg $SessionID "Die Sitzung wurde wegen Inaktivitaet getrennt"
                tsdiscon $SessionID
            }
            '
            $Content = $Content.Replace("<SessionID>",$User.sessionid)
            $Content = $Content.Replace("<MaxIdleTime>",$MaxIdleTime)

            $Job = Start-Job -ScriptBlock ([scriptblock]::Create($Content)) 
        }
        
    }
    else{ # If Session is disconnected
        if($User.idletime -ge $MaxDisconnectTime){# Check if Session is disconnected longer than Max Disconect Time
            reset session $user.sessionid
        }

    }

}
Get-Job | Wait-Job | Remove-Job

$Users = Get-QueryUser

$bootuptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
$CurrentDate = Get-Date
$uptime =  ($CurrentDate - $bootuptime).TotalMinutes

if ($Users -eq $Null){
    
    if($uptime -ge $VMStartOffset){
        $Return = ("NO-USER-SESSION-CONNECTED-AND-UPTIME-OVER-"+ $VMStartOffset + "-MIN")
    }
    else{
        $Return = ("UPTIME-NOT-OVER-" + $VMStartOffset + "-MIN")
    }


}
else{
    $Return = "ACTIVE-USER-SESSION-CONNECTED"
}

$Return

'@

$Content = $Content.Replace("<MaximumIdleTime>", $MaxIdleTime)
$Content = $Content.Replace("<MaximumDisconnectTime>", $MaxDisconnectTime)
$Content = $Content.Replace("<VMStartOffset>", $VMStartOffset)

$AZVMs = Get-AZVM -Status | ? Powerstate -like "*running*"

$Jobs = @()
foreach($AVDVM in $AVDVMs.trim()){
    Write-Host "Processing VM : " $AVDVM
    $VM = $AZVMs | ? Name -eq $AVDVM
    if($VM){
        $Verbose = ("Starting Job for VM to Check if Users Connected : " + $VM.name)
        Write-Host $Verbose

        $Obj = [PSCustomObject]@{
            "AZVMName" = $VM.Name
            "Job" = $vm | Invoke-AzVMRunCommand -CommandId "RunPowerShellScript" -ScriptString $Content -AsJob
            "JobResult" = ""
            "ShutDownVM" = $False
            }
        $Jobs += $Obj
    
    }
    else {Write-Host "    VM is not started ! Skipping VM ..."}

}

if($Jobs){
    Write-Host "All Jobs Created, waiting for Jobs to be Compled ..."
    $DMP = Get-Job | Wait-Job
    Write-Host "All Processing Jobs has been completed! "

}


$i = 0
foreach($Job in $Jobs){

    if(-not $Jobs[$i].JobResult){
        $Jobs[$i].JobResult = $Jobs[$i] | Receive-Job
        if($Jobs[$i].JobResult[0].value[0].Message -contains ("NO-USER-SESSION-CONNECTED-AND-UPTIME-OVER-" + $VMStartOffset + "-MIN")){
            $Jobs[$i].ShutDownVM = $True
            
        }
    $Job[$i] | Remove-Job
    }
$i++
}

if (($Jobs | ? ShutdownVM -eq $true) -eq $Null){

    Write-Host "No VMs needed has been shutdown, waiting for the next run !"
    exit 0
}

foreach($Job in ($Jobs | ? ShutdownVM -eq $true)){
    
    Write-Host "Triggering VM Stop for VM :" $Job.AZVMName
    $Status = (Invoke-AVDShutdownVM $Job.AZVMName).PowerState
    Write-Host "Trigger Complete ! State of VM is now : " $Status
    $Exit = 100
    
}


exit $Exit
