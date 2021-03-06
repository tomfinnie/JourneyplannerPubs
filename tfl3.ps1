$scriptpath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptpath

$dataDir = 'C:\Users\tom\SkyDrive\github\JourneyplannerPubs'

#Returns the time in miniutes between two postcodes

function Get-Journey {

    param (
    $start,
    $finish,
    $date=(get-date).getdatetimeformats()[4].replace("-",""),
    $time=(get-date).getdatetimeformats()[70].replace(":",""))
    
    
    $url = "http://journeyplanner.tfl.gov.uk/user/XML_TRIP_REQUEST2?language=en&sessionID=0&place_origin=London&type_origin=locator&name_origin="+$start+"&place_destination=London&type_destination=locator&name_destination="+$finish+"itdDate="+$date+"&itdTime="+$time
    #below is with busses excluded
    #$url = "http://journeyplanner.tfl.gov.uk/user/XML_TRIP_REQUEST2?language=en&sessionID=0&place_origin=London&type_origin=locator&name_origin="+$start+"&place_destination=London&type_destination=locator&name_destination="+$finish+"itdDate="+$date+"&itdTime="+$time"&excludedMeans=checkbox&exclMOT_5=1"
    [xml]$plan = (New-Object System.Net.WebClient).DownloadString($url)

    $times = $plan.itdRequest.itdTripRequest.itdItinerary.itdRouteList.itdRoute | % {$_.publicDuration}

    $timesMinutes = $times | % {60*[int]($_.split(":"))[0] + [int]($_.split(":"))[1]}

    #return ($timesMinutes | sort)[0]
    return $plan}

# Finds the time from $pubPostcode to all the postcodes in mates.csv, which has columns labeled name, postcode and weight.
# Calculates the average and maximum time to this pub for all mates with weight 1
# If given a valid path for $pubDBPath, it gets the journey times from there, otherwise goes to tfl via Get-Journey

function Test-Pub {

    param ($pubPostcode,
           $pubName,
           $pubDBPath="$dataDir\pubDB.csv",
           $matesPath="$dataDir\mates.csv")
   
    $mates = Import-Csv $matesPath
    
    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -MemberType NoteProperty -Name Name -Value $pubName
    $obj | Add-Member -MemberType NoteProperty -Name Postcode -Value $pubPostcode
    
    if (!(Test-Path $pubDBPath)) {
        $mates | % {
            $matePostcode = $_.postcode
            $obj | Add-Member -MemberType NoteProperty -Name $_.name -Value (Get-Journey $matePostcode $pubPostcode)
                    }
                 }
    else {
        $output = import-csv $pubDBPath | where {$_.postcode -eq  $pubPostcode}
        $mates | % {
            $mateName = $_.name
            $obj | Add-Member -MemberType NoteProperty -Name $_.name -Value ($output.$matename)
                    }
         }
         
#    $obj | Add-Member -MemberType NoteProperty -Name average -Value $average
#    $maximum =  ($mates | % {$obj.($_.name)*[math]::truncate([math]::pow($_.weight,0.0000))} | Measure-Object -max).maximum

    $maximum =  ($mates | % {$obj.($_.name)*($_.weight)} | Measure-Object -max).maximum
    [int]$total = ($mates | % {[int]($obj.($_.name))*$_.weight} | Measure-Object -sum).sum
    [int]$journeys =  ($mates | % {$_.weight} | Measure-Object -sum).sum
    [int]$average = ($total / $journeys)
    
    $obj | Add-Member -MemberType NoteProperty -Name Average -Value $average
    $obj | Add-Member -MemberType NoteProperty -Name maximum -Value $maximum
    
    Write-Output $obj
    Write-Host "Testing the $pubname in $pubpostcode"
}

#Tests every pub in pubs.csv using pubDB.csv, lists the 10 with lowest maximum, and 10 with lowest average times.

function Best-Pub {

    $pubs = import-csv "$dataDir\pubs.csv"
    $output = ($pubs | % {
    test-pub $_.postcode $_.name})
    Write-Host "Sorted by Maximum"
    $output | where {$_.maximum -gt 0} | sort maximum | select name,postcode,maximum,average -first 10 | format-table
    Write-Host "Sorted by Average"
    $output | where {$_.average -gt 0} | sort average | select name,postcode,average,maximum -first 10 | format-table
                    }
#Tests every pubs.csv using Get-Journey. Limited to 40 requests at once, otherwise TFL might moan.
                    
function Populate-DB 
{

    param ($requests = 40,
           $matesPath="$dataDir\mates.csv"
           )
    
    $pubs = (import-csv "$dataDir\pubs.csv")

    $pubs | % `
    {
        $scriptblock=`
        {
            param ($inPostcode,$inPub,$matesPath,$scriptDir)
            . "$scriptDir\tfl3.ps1"
            test-pub $inPostcode $inPub $false $matesPath
        }      
        While ( (get-job -state "running" | Measure-Object).count -gt $requests) {Start-Sleep 1}
    
        start-job $scriptblock -arg $_.postcode,$_.name,$matesPath,$scriptDir
    }
    
    #Start-Sleep 60 
    
    #Below doesn't work because jobs sometimes get stuck      
    While (get-job -state "running"){Start-Sleep 1}

    Get-Job | Receive-Job | Export-csv "$dataDir\pubDB.csv"
}
                      