$RegKeyFields = "KeyName","ValueName","Value";
[System.Collections.ArrayList]$RegKeysArray  = $RegKeyFields;
$Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $env:computername);
# Set the desired Key
$RegPath = "SOFTWARE";
$RegKey= $Reg.OpenSubKey($RegPath);
Function DigThroughKeys()
{
param (
    [Parameter(Mandatory=$true)]
    [AllowNull()]
    [AllowEmptyString()]
    [Microsoft.Win32.RegistryKey]$Key
    )
    if($Key.ValueCount -gt 0)
    {
        Foreach($value in $Key.GetValueNames())
        {
            if(($Key.GetValue($value) -match "password") -or ($Key.Name -match "password"))
            {
                $item = New-Object PSObject;
                $item | Add-Member -NotePropertyName "KeyName" -NotePropertyValue $Key.Name;
                $item | Add-Member -NotePropertyName "ValueName" -NotePropertyValue $value.ToString();
                $item | Add-Member -NotePropertyName "Value" -NotePropertyValue $Key.GetValue($value);
                [void]$RegKeysArray.Add($item);
            }
        }
    }
if($Key.SubKeyCount -gt 0)
{
    ForEach($subKey in $Key.GetSubKeyNames())
    {
        try {
        DigThroughKeys -Key $Key.OpenSubKey($subKey);
        }
        catch { continue }
    }
}
};
 DigThroughKeys -Key $RegKey
 $RegKeysArray | Select-Object Value, KeyName, ValueName
 $Reg.Close();
