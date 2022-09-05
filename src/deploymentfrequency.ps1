# TODO 
# - There are tons of bugs
# - no versioning/tags/releases - (just use @main tag for now)
# - minimal error handling
# - some rounding errors
# - some questionable decisions made for the output. 

Param(
    [string] $ownerRepo,
    [string] $workflows,
    [string] $branch,
    [Int32] $numberOfDays,
    [string] $appId,
    [string] $appInstallationId,
    [string] $privateKey
)

function ConvertTo-Base64UrlString(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]$in
    ) 
{
    if ($in -is [string]) {
        return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($in)) -replace '\+','-' -replace '/','_' -replace '='
    }
    elseif ($in -is [byte[]]) {
        return [Convert]::ToBase64String($in) -replace '\+','-' -replace '/','_' -replace '='
    }
    else {
        throw "ConvertTo-Base64UrlString requires string or byte array input, received $($in.GetType())"
    }
}

function Get-JwtToken(
    [string]$appId, 
    [string] $appInstallationId,
    [string] $privateKey
)
{
    # Write-Host "appId: $appId"
    $now = (Get-Date).ToUniversalTime()
    $createDate = [Math]::Floor([decimal](Get-Date($now) -UFormat "%s"))
    $expiryDate = [Math]::Floor([decimal](Get-Date($now.AddMinutes(4)) -UFormat "%s"))
    $rawclaims = [Ordered]@{
        iat = [int]$createDate
        exp = [int]$expiryDate
        iss = $appId
    } | ConvertTo-Json
    # Write-Host "expiryDate: $expiryDate"
    # Write-Host "rawclaims: $rawclaims"

    $Header = [Ordered]@{
        alg = "RS256"
        typ = "JWT"
    } | ConvertTo-Json
    # Write-Host "Header: $Header"
    $base64Header = ConvertTo-Base64UrlString $Header
    # Write-Host "base64Header: $base64Header"
    $base64Payload = ConvertTo-Base64UrlString $rawclaims
    # Write-Host "base64Payload: $base64Payload"

    $jwt = $base64Header + '.' + $base64Payload
    $toSign = [System.Text.Encoding]::UTF8.GetBytes($jwt)

    $rsa = [System.Security.Cryptography.RSA]::Create(); 
    # DEBUG ONLY
    Write-Host "'$($privateKey)'"
    # https://stackoverflow.com/a/70132607 lead to the right import
    $rsa.ImportRSAPrivateKey([System.Convert]::FromBase64String($privateKey), [ref] $null);

    try { $sig = ConvertTo-Base64UrlString $rsa.SignData($toSign,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1) }
    catch { throw New-Object System.Exception -ArgumentList ("Signing with SHA256 and Pkcs1 padding failed using private key $($rsa): $_", $_.Exception) }
    Write-Host "sig: $sig"
    $jwt = $jwt + '.' + $sig
    Write-Host "jwt: $jwt"
    # send headers
    $uri = "https://api.github.com/app/installations/$appInstallationId/access_tokens"
    $jwtHeader = @{
        Accept = "application/vnd.github+json"
        Authorization = "Bearer $jwt"
    }
    $tokenRespone = Invoke-RestMethod -Uri $uri -Headers $jwtHeader -Method Post -ErrorAction Stop
    # Write-Host $tokenRespone.token
    return $tokenRespone.token
}

#==========================================
#Input processing
$ownerRepoArray = $ownerRepo -split '/'
$owner = $ownerRepoArray[0]
$repo = $ownerRepoArray[1]
Write-Output "Owner/Repo: $owner/$repo"
$workflowsArray = $workflows -split ','
Write-Output "Workflows: $($workflowsArray[0])"
Write-Output "Branch: $branch"
$numberOfDays = $numberOfDays        
Write-Output "Number of days: $numberOfDays"

#==========================================
#Get workflow definitions from github
$uri = "https://api.github.com/repos/$owner/$repo/actions/workflows"
$token = Get-JwtToken -appId $appId -appInstallationId $appInstallationId -privateKey $privateKey
$jwtHeader = @{
    Accept = "application/vnd.github+json"
    Authorization = "token $token"
}
$workflowsResponse = Invoke-RestMethod -Uri $uri -ContentType application/json -Method Get -Headers $jwtHeader -ErrorAction Stop
#==========================================
#Extract workflow ids from the definitions, using the array of names. Number of Ids should == number of workflow names
$workflowIds = [System.Collections.ArrayList]@()
Foreach ($workflow in $workflowsResponse.workflows){

    Foreach ($arrayItem in $workflowsArray){
        if ($workflow.name -eq $arrayItem)
        {
            #Write-Output "'$($workflow.name)' matched with $arrayItem"
            $result = $workflowIds.Add($workflow.id)
            if ($result -lt 0)
            {
                Write-Output "unexpected result"
            }
        }
        else 
        {
            #Write-Output "'$($workflow.name)' DID NOT match with $arrayItem"
        }
    }
}

#==========================================
#Filter out workflows that were successful. Measure the number by date/day. Aggegate workflows together
$dateList = @()

#For each workflow id, get the last 100 workflows from github
Foreach ($workflowId in $workflowIds){
    #Get workflow definitions from github
    $uri2 = "https://api.github.com/repos/$owner/$repo/actions/workflows/$workflowId/runs?per_page=100"
    $workflowRunsResponse = Invoke-RestMethod -Uri $uri2 -ContentType application/json -Method Get -Headers $jwtHeader -ErrorAction Stop

    $buildTotal = 0
    Foreach ($run in $workflowRunsResponse.workflow_runs){
        #Count workflows that are completed, on the target branch, and were created within the day range we are looking at
        if ($run.status -eq "completed" -and $run.head_branch -eq $branch -and $run.created_at -gt (Get-Date).AddDays(-$numberOfDays))
        {
            #Write-Output "Adding item with status $($run.status), branch $($run.head_branch), created at $($run.created_at), compared to $((Get-Date).AddDays(-$numberOfDays))"
            $buildTotal++       
            #get the workflow start and end time            
            $dateList += New-Object PSObject -Property @{start_datetime=$run.created_at;end_datetime=$run.updated_at}     
        }
    }
}


#==========================================
#Calculate deployments per day
$deploymentsPerDay = 0

if ($dateList.Count -gt 0 -and $numberOfDays -gt 0)
{
    $deploymentsPerDay = $dateList.Count / $numberOfDays
}


#==========================================
#output result
$dailyDeployment = 1
$weeklyDeployment = 1 / 7
$monthlyDeployment = 1 / 30
$everySixMonthsDeployment = 1 / (6 * 30) #//Every 6 months
$yearlyDeployment = 1 / 365

#Calculate rating 
$rating = ""
if ($deploymentsPerDay -le 0)
{
    $rating = "None"
}
elseif ($deploymentsPerDay -ge $dailyDeployment)
{
    $rating = "Elite"
}
elseif ($deploymentsPerDay -le $dailyDeployment -and $deploymentsPerDay -ge $monthlyDeployment)
{
    $rating = "High"
}
elseif (deploymentsPerDay -le $monthlyDeployment -and $deploymentsPerDay -ge $everySixMonthsDeployment)
{
    $rating = "Medium"
}
elseif ($deploymentsPerDay -le $everySixMonthsDeployment)
{
    $rating = "Low"
}

#Calculate metric and unit
if ($deploymentsPerDay -gt $dailyDeployment) 
{
    $displayMetric = [math]::Round($deploymentsPerDay,2)
    $displayUnit = "per day"
}
elseif ($deploymentsPerDay -le $dailyDeployment -and $deploymentsPerDay -ge $weeklyDeployment)
{
    $displayMetric = [math]::Round($deploymentsPerDay * 7,2)
    $displayUnit = "times per week"
}
elseif ($deploymentsPerDay -lt $weeklyDeployment -and $deploymentsPerDay -ge $monthlyDeployment)
{
    $displayMetric = [math]::Round($deploymentsPerDay * 30,2)
    $displayUnit = "times per month"
}
elseif ($deploymentsPerDay -lt $monthlyDeployment -and $deploymentsPerDay -gt $yearlyDeployment)
{
    $displayMetric = [math]::Round($deploymentsPerDay * 30,2)
    $displayUnit = "times per month"
}
elseif ($deploymentsPerDay -le $yearlyDeployment)
{
    $displayMetric = [math]::Round($deploymentsPerDay * 365,2)
    $displayUnit = "times per year"
}

Write-Output "Deployment frequency over last $numberOfDays days, is $displayMetric $displayUnit, with a DORA rating of '$rating'"
