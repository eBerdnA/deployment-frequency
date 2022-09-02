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
