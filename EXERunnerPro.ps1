function Get-PowerShot {

$results = @{}  #Hash that contains all the relevant properties of the files
$rootDir   = "Z:\TestDir"

$rootItems = Get-ChildItem $rootDir  #All files and folders in the top level directory given
$i=0
foreach ($rootItem in $rootItems) {   #Iterate through all items (files and folders) in given root directory 
    Write-Host "Processing $rootItem" #Tell user what it happening
    Write-Progress -Activity "Filesystem Snapshot" -Status "Percent Complete" -PercentComplete ($i /$rootItems.count * 100); $i++ #Update Progressbar
    foreach ($file in (Get-ChildItem -Path $rootItem.FullName -recurse )) {
        Write-Host "`tProcessing $file" #Tell user what it happening

        $object = New-Object –TypeName PSObject  #Object to hold information on file/folder
        #$object | Add-Member –MemberType NoteProperty –Name FullPath –Value $file.FullName
        $object | Add-Member –MemberType NoteProperty –Name SHA256   –Value (Get-FileHash $file.FullName  -Algorithm SHA256).hash
        $object | Add-Member –MemberType NoteProperty –Name MD5      –Value (Get-FileHash $file.FullName  -Algorithm MD5   ).hash
        $object | Add-Member –MemberType NoteProperty –Name SHA1     –Value (Get-FileHash $file.FullName  -Algorithm SHA1  ).hash
        $object | Add-Member –MemberType NoteProperty –Name TimeModified –Value $file.LastWriteTimeUtc.Ticks
        $object | Add-Member –MemberType NoteProperty –Name TimeAccessed –Value $file.LastAccessTimeUtc.Ticks
        $object | Add-Member –MemberType NoteProperty –Name TimeCreated  –Value $file.CreationTimeUtc.Ticks
        $results.Add($file.FullName, $object)
    }
}
return $results
}


function Power-FakeRunnerInstallerMax {
    param($dir,$first,$second,$third)
    $first = Get-PowerShot -getReg $false
    $neverthesame                      = "$dir\neverthesame.txt"
    $MadeAfter1SnapDeletedAfter2ndSnap = "$dir\MadeAfter1SnapDeletedAfter2ndSnap.txt"
    $AddedAfter2ndSnap                 = "$dir\AddedAfter2ndSnap.txt"
    Get-Date | Out-File $neverthesame  #add a change for debugging
    Get-Date | Out-File $MadeAfter1SnapDeletedAfter2ndSnap     #add a change for debugging
    sleep -Seconds 1
    $second = Get-PowerShot   -getReg $false
    rm $MadeAfter1SnapDeletedAfter2ndSnap
    Get-Date | Out-File $AddedAfter2ndSnap     #add a change for debugging
    Get-Date | Out-File $neverthesame  #add a change for debugging
    sleep -Seconds 1
    $third = Get-PowerShot  -getReg $false
    rm $AddedAfter2ndSnap
    return($first,$second,$third)
}




function Retrieve-NonMACMetrics {
    param($hash)  #hashtable that contains objects
    return @((($hash.Values[0] | Get-Member -MemberType NoteProperty).name) | Where-Object {$_ -NotLike "Time*"})  #Only get non-time related metrics
}

function Retrieve-MACMetrics {
    param($hash)  #hashtable that contains objects
    return @((($hash.Values[0] | Get-Member -MemberType NoteProperty).name) | Where-Object {$_ -Like "Time*"})  #Only get non-time related metrics
}

function Compare-HashTables {
    param($hash1, $hash2)	#Hash1 is for the first (before) snapshot. Hash2 is for the second (after) snapshot
    $results = @{}          #Hashtable to hold whats different. Key is the full path, value is an object with only what changed

    $keys=@()  #array to hold all the possible key values
    $keys+=$hash1.Keys
    $keys+=$hash2.Keys
    $keys = $keys | Sort | Get-Unique  #Make it so the array only has one copy of each key 

    #Get all the metrics being recorded. This is done dynamically here for scalability
    $metricNames = Retrieve-NonMACMetrics -hash $hash1  #Only get non-time related metrics

    #Compare
    foreach ($key in $keys) {  #Iterate through all keys
        if($hash1[$key] -notmatch $hash2[$key]) {           
            $object = New-Object –TypeName PSObject  #Object to hold different items
            foreach($metric in $metricNames) {       #Iterate through all the recorded metrics                  

                #Get Metric Values
                $hash1Value = ($hash1[$key]).$metric #Get Hash1's value
                $hash2Value = ($hash2[$key]).$metric #Get Hash2's value

                #Compare Metric Data and save it to the  object
                if($hash1Value -cne $hash2Value) { 
                    #$object | Add-Member –MemberType NoteProperty -name ($metric+'_Before') -value $hash1Value   #The before value. Commented out as this functionality is not needed
                    $object | Add-Member –MemberType NoteProperty -name ($metric)  -value $hash2Value             #The after value
                }
            }
            #Save the results
            $results.Add($key, $object)
        }
    }
    return $results
}

function Artifact-Finder {
    param($Artifacts, $Machine)	
    $results = @{}          #Hashtable to hold whats different. Key is the full path, value is an object with only what changed

    $keys=@()  #array to hold all the possible key values
    $keys+=$Artifacts.Keys
    $keys+=$Machine.Keys
    $keys = $keys | Sort | Get-Unique  #Make it so the array only has one copy of each key 

    #Get all the metrics being recorded. This is done dynamically here for scalability
    $metricNames = Retrieve-NonMACMetrics -hash $Machine #Only get non-time related metrics

    #Compare
    foreach ($key in $Artifacts.Keys) {           #Iterate through all keys
        $object = New-Object –TypeName PSObject   #Object to hold found artifacts
        foreach($metric in $metricNames) {        #Iterate through all the recorded metrics not related to MAC Times                 

            #Get Metric Values
            $object | Add-Member –MemberType NoteProperty -name ($metric+'_Artifact') -value ($Artifacts[$key]).$metric
            $object | Add-Member –MemberType NoteProperty -name ($metric+'_Machine')  -value ($Machine[$key]).$metric
        }
        #Add MAC times for Machine
        foreach($metric in (Retrieve-MACMetrics -hash $Machine)) { $object | Add-Member –MemberType NoteProperty -name ($metric+'_Machine')  -value ($Machine[$key]).$metric}

        #Save the results
        $results.Add($key, $object)
    }
    return $results
}


($first,$second,$third) = Power-FakeRunnerInstallerMax -dir 'Z:\TestDir'


$whatsDiff = Compare-HashTables -hash1 $first -hash2 $second 

$tempsave = 'Z:\artifact.txt'
$whatsDiff | Export-Clixml -Path "$tempsave.xml"
$artifact =  Import-Clixml -Path "$tempsave.xml"

$foundArts = Artifact-Finder -Artifacts $artifact -Machine $third
cls
foreach ($key in $foundArts.keys) { 
    write-host $key -ForegroundColor Green
    $foundArts[$key] 
}
