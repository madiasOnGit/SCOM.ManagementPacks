Param($ServiceAccountUser, $ServiceAccountPassword,$Tenant,$SubscriptionId,$ResourceGroup,$WorkspaceName,$Query)

$ScriptName = "logAnalyticsQuery.ps1"
$EventID = "11116"
$oAPI = New-Object -ComObject 'MOM.ScriptAPI'
$sw = New-Object Diagnostics.Stopwatch
$sw.Start()
#$oAPI.LogScriptEvent($ScriptName,$EventID,0,"Script is starting.`n Running as $(whoami).`n WS=$WorkspaceName , AppID=$ServiceAccountUser")

#Functions from LogAnalytics Module

function Invoke-LogAnalyticsQuery ($WorkspaceName,$SubscriptionId,$ResourceGroup,$Query){

    $ErrorActionPreference = "Stop"
    $accessToken = GetAccessToken
	$uri =  "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/microsoft.operationalinsights/workspaces/$workspaceName/api/query?api-version=2017-01-01-preview"
	$Timespan = ""
	$ServerTimeout = ""

    $body = @{"query" = $Query;"timespan" = $Timespan} | ConvertTo-Json

	$preferString = "response-v1=true"
    if ($ServerTimeout -ne $null) {
        $preferString += ",wait=$ServerTimeout"
    }
	$headers = @{
        "Authorization" = "Bearer $accessToken";
        "prefer" = $preferString;
        "x-ms-app" = "LogAnalyticsQuery.psm1";
        "x-ms-client-request-id" = [Guid]::NewGuid().ToString();
    }

    $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Body $body -ContentType "application/json" -Headers $headers -Method Post

    if ($response.StatusCode -ne 200 -and $response.StatusCode -ne 204) {
        $statusCode = $response.StatusCode
        $reasonPhrase = $response.StatusDescription
        $message = $response.Content
        throw "Failed to execute query.`nStatus Code: $statusCode`nReason: $reasonPhrase`nMessage: $message"
    }

    $oData = $response.Content | ConvertFrom-Json

    $result = New-Object PSObject
    $result | Add-Member -MemberType NoteProperty -Name Response -Value $response

    # In this case, we only need the response member set and we can bail out
    if ($response.StatusCode -eq 204) {
        $result
        return
    }

    $objectView = CreateObjectView  $oData
    $result | Add-Member -MemberType NoteProperty -Name Results -Value $objectView
    $result
}

function GetAccessToken {
    $azureCmdlet = get-command -Name Get-AzureRMContext -ErrorAction SilentlyContinue
    if ($azureCmdlet -eq $null)
    {
        $null = Import-Module AzureRM -ErrorAction Stop;
    }
    $AzureContext = & "Get-AzureRmContext" -ErrorAction Stop;
    $authenticationFactory = New-Object -TypeName Microsoft.Azure.Commands.Common.Authentication.Factories.AuthenticationFactory
    if ((Get-Variable -Name PSEdition -ErrorAction Ignore) -and ('Core' -eq $PSEdition)) {
        [Action[string]]$stringAction = {param($s)}
        $serviceCredentials = $authenticationFactory.GetServiceClientCredentials($AzureContext, $stringAction)
    } else {
        $serviceCredentials = $authenticationFactory.GetServiceClientCredentials($AzureContext)
    }

    # We can't get a token directly from the service credentials. Instead, we need to make a dummy message which we will ask
    # the serviceCredentials to add an auth token to, then we can take the token from this message.
    $message = New-Object System.Net.Http.HttpRequestMessage -ArgumentList @([System.Net.Http.HttpMethod]::Get, "http://foobar/")
    $cancellationToken = New-Object System.Threading.CancellationToken
    $null = $serviceCredentials.ProcessHttpRequestAsync($message, $cancellationToken).GetAwaiter().GetResult()
    $accessToken = $message.Headers.GetValues("Authorization").Split(" ")[1] # This comes out in the form "Bearer <token>"

    $accessToken
}

function CreateObjectView($oData) {

    # Find the number of entries we'll need in this array
    $count = 0
    foreach ($table in $oData.Tables) {
        $count += $table.Rows.Count
    }

    $objectView = New-Object object[] $count
    $i = 0;
    foreach ($table in $oData.Tables) {
        foreach ($row in $table.Rows) {
            # Create a dictionary of properties
            $properties = @{}
            for ($columnNum=0; $columnNum -lt $table.Columns.Count; $columnNum++) {
                $properties[$table.Columns[$columnNum].name] = $row[$columnNum]
            }
            # Then create a PSObject from it. This seems to be *much* faster than using Add-Member
            $objectView[$i] = (New-Object PSObject -Property $properties)
            $null = $i++
        }
    }
    $objectView
}


if(-not ($ServiceAccountUser -and $ServiceAccountPassword -and $Tenant -and $SubscriptionId -and $ResourceGroup -and $WorkspaceName ) ) {
		$oAPI.LogScriptEvent($ScriptName,$EventID,1,"FATAL ERROR: Script requires all parameters and RunAs Account being associated with the SCOMAnalytics RunAs Profile.")
	EXIT
}


$cred = New-Object System.Management.Automation.PSCredential -Argumentlist @($ServiceAccountUser,(ConvertTo-SecureString -String $ServiceAccountPassword -AsPlainText -Force))

#Connect to azure
Try{
  #$oAPI.LogScriptEvent($ScriptName,$EventID,0,"Connecting to azure ...")
  Connect-AzureRmAccount -Credential $cred -ServicePrincipal -TenantId $tenant
}
Catch{
  $oAPI.LogScriptEvent($ScriptName,$EventID,1, "FATAL ERROR:Unable to connect to Azure.`n $error")
  EXIT
}

#Load Kusto module
#Try{
#  #$oAPI.LogScriptEvent($ScriptName,$EventID,0,"Importing Kusto module ...")
#  $SCOMResources = (get-itemproperty -path 'HKLM:\system\currentcontrolset\services\healthservice\Parameters' -Name 'State Directory').'State Directory' + '\Resources'
#  $KustoModulePath = @(get-childitem -path $SCOMResources -Filter LogAnalyticsQuery.psm1 -Recurse)[0]
#  Import-Module $KustoModulePath.PSPath
#}
#Catch{
#  $oAPI.LogScriptEvent($ScriptName,$EventID,1, "FATAL ERROR:Unable to load kustomodule.`n $error")
#  EXIT
#}

#Search Log Analytics
Try{
  #$oAPI.LogScriptEvent($ScriptName,$EventID,0,"Performing query...")
  $r = Invoke-LogAnalyticsQuery -WorkspaceName $WorkspaceName -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -Query $Query
}
Catch{
  $oAPI.LogScriptEvent($ScriptName,$EventID,1, "FATAL ERROR: Unable to search logAnalytics Workspace.`n  $error")
  EXIT
}


if($r) {
	$r.Results | % { 
		$bag = $oAPI.CreatePropertyBag()
		$_.PSObject.Properties | %{ 
			$bag.AddValue("$($_.Name)",$_.Value)
		}
		$bag
	}
}

$oAPI.LogScriptEvent($ScriptName,$EventID,0,"Script Completed.`n Running as $(whoami).`n WS=$WorkspaceName , AppID=$ServiceAccountUser `n Script Runtime: $($sw.Elapsed.TotalSeconds) seconds.")

