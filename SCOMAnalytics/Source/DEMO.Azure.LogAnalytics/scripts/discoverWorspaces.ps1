param($Configuration)

$oAPI = New-Object -ComObject 'MOM.ScriptAPI'
$oDiscoveryData = $oAPI.CreateDiscoveryData(0, '$MPElement$', '$Target/Id$')

function ConvertFrom-Json20([object] $item){ 
    add-type -assembly system.web.extensions
    $ps_js=new-object system.web.script.serialization.javascriptSerializer
    return ,$ps_js.DeserializeObject($item)
}

$Config = ConvertFrom-Json20 $Configuration

$Config | %{ 
	$instance = $oDiscoveryData.CreateClassInstance("$MPElement[Name='DEMO.Azure.LogAnalytics.Workspace']$")
	$instance.AddProperty("$MPElement[Name='DEMO.Azure.LogAnalytics.Workspace']/Tenant$", $_.Tenant)
	$instance.AddProperty("$MPElement[Name='DEMO.Azure.LogAnalytics.Workspace']/SubscriptionId$", $_.SubscriptionId)
	$instance.AddProperty("$MPElement[Name='DEMO.Azure.LogAnalytics.Workspace']/ResourceGroup$", $_.ResourceGroup)
	$instance.AddProperty("$MPElement[Name='DEMO.Azure.LogAnalytics.Workspace']/WorkspaceName$", $_.WorkspaceName)
	$instance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", "Azure Log Analytics $($_.WorkspaceName)")
	$oDiscoveryData.AddInstance($instance)

}

$oDiscoveryData
