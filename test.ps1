$ModuleName = [Guid]::NewGuid().ToString()
$AppDomain = [Reflection.Assembly].Assembly.GetType('System.AppDomain').GetProperty('CurrentDomain').GetValue($null, @())
$DynAssembly = New-Object Reflection.AssemblyName($ModuleName)
$AssemblyBuilder = $AppDomain.DefineDynamicAssembly($DynAssembly, 'Run')
$Mod = $AssemblyBuilder.DefineDynamicModule($ModuleName, $False)
$TypeHash = @{}
$DllName = "netapi32"
$FunctionName = "NetWkstaUserEnum"
$ReturnType = [int]
$ParameterTypes = @([String], [Int], [IntPtr].MakeByRefType(), [Int], [Int32].MakeByRefType(), [Int32].MakeByRefType(), [Int32].MakeByRefType())
$NativeCallingConvention = [Runtime.InteropServices.CallingConvention]::StdCall
$Charset = [Runtime.InteropServices.CharSet]::Auto
$Module = $Mod
$Namespace = "Win32"
$TypeHash[$DllName] = $Module.DefineType("$Namespace.$DllName", 'Public,BeforeFieldInit')
$Method = $TypeHash[$DllName].DefineMethod($FunctionName, 'Public,Static,PinvokeImpl', $ReturnType, $ParameterTypes)
$i = 1
foreach($Parameter in $ParameterTypes)
{
    if ($Parameter.IsByRef)
    {
        [void] $Method.DefineParameter($i, 'Out', $null)
    }

    $i++
}
$DllImport = [Runtime.InteropServices.DllImportAttribute]
$SetLastErrorField = $DllImport.GetField('SetLastError')
$CallingConventionField = $DllImport.GetField('CallingConvention')
$CharsetField = $DllImport.GetField('CharSet')
$EntryPointField = $DllImport.GetField('EntryPoint')
if ($SetLastError) { $SLEValue = $True } else { $SLEValue = $False }
if ($PSBoundParameters['EntryPoint']) { $ExportedFuncName = $EntryPoint } else { $ExportedFuncName = $FunctionName }
$Constructor = [Runtime.InteropServices.DllImportAttribute].GetConstructor([String])
$DllImportAttribute = New-Object Reflection.Emit.CustomAttributeBuilder($Constructor, $DllName, [Reflection.PropertyInfo[]] @(), [Object[]] @(), [Reflection.FieldInfo[]] @($SetLastErrorField, $CallingConventionField, $CharsetField, $EntryPointField), [Object[]] @($SLEValue, ([Runtime.InteropServices.CallingConvention] $NativeCallingConvention), ([Runtime.InteropServices.CharSet] $Charset), $ExportedFuncName))
$Method.SetCustomAttribute($DllImportAttribute)
$Types = @{}
foreach ($Key in $TypeHash.Keys)
{
    $Type = $TypeHash[$Key].CreateType()

    $Types[$Key] = $Type
}
function field {
    Param (
        [Parameter(Position = 0, Mandatory=$True)]
        [UInt16]
        $Position,

        [Parameter(Position = 1, Mandatory=$True)]
        [Type]
        $Type,

        [Parameter(Position = 2)]
        [UInt16]
        $Offset,

        [Object[]]
        $MarshalAs
    )

    @{
        Position = $Position
        Type = $Type -as [Type]
        Offset = $Offset
        MarshalAs = $MarshalAs
    }
}
function struct
{
    [OutputType([Type])]
    Param (
        [Parameter(Position = 1, Mandatory=$True)]
        [ValidateScript({($_ -is [Reflection.Emit.ModuleBuilder]) -or ($_ -is [Reflection.Assembly])})]
        $Module,

        [Parameter(Position = 2, Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FullName,

        [Parameter(Position = 3, Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $StructFields
    )
    $PackingSize = [Reflection.Emit.PackingSize]::Unspecified
    [Reflection.TypeAttributes] $StructAttributes = 'AnsiClass,
        Class,
        Public,
        Sealed,
        BeforeFieldInit'

    $StructAttributes = $StructAttributes -bor [Reflection.TypeAttributes]::SequentialLayout
    $StructBuilder = $Module.DefineType($FullName, $StructAttributes, [ValueType], $PackingSize)
    $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]
    $Fields = New-Object Hashtable[]($StructFields.Count)
    foreach ($Field in $StructFields.Keys)
    {
        $Index = $StructFields[$Field]['Position']
        $Fields[$Index] = @{FieldName = $Field; Properties = $StructFields[$Field]}
    }
    foreach ($Field in $Fields)
    {
        $FieldName = $Field['FieldName']
        $FieldProp = $Field['Properties']
        $Type = $FieldProp['Type']
        $MarshalAs = $FieldProp['MarshalAs']
        $NewField = $StructBuilder.DefineField($FieldName, $Type, 'Public')
        if ($MarshalAs)
        {
            $UnmanagedType = $MarshalAs[0] -as ([Runtime.InteropServices.UnmanagedType])
            $AttribBuilder = New-Object Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, [Object[]] @($UnmanagedType))
            $NewField.SetCustomAttribute($AttribBuilder)
        }
    }
    $SizeMethod = $StructBuilder.DefineMethod('GetSize',
        'Public, Static',
        [Int],
        [Type[]] @())
    $ILGenerator = $SizeMethod.GetILGenerator()
    $ILGenerator.Emit([Reflection.Emit.OpCodes]::Ldtoken, $StructBuilder)
    $ILGenerator.Emit([Reflection.Emit.OpCodes]::Call,
        [Type].GetMethod('GetTypeFromHandle'))
    $ILGenerator.Emit([Reflection.Emit.OpCodes]::Call,
        [Runtime.InteropServices.Marshal].GetMethod('SizeOf', [Type[]] @([Type])))
    $ILGenerator.Emit([Reflection.Emit.OpCodes]::Ret)
    $ImplicitConverter = $StructBuilder.DefineMethod('op_Implicit',
        'PrivateScope, Public, Static, HideBySig, SpecialName',
        $StructBuilder,
        [Type[]] @([IntPtr]))
    $ILGenerator2 = $ImplicitConverter.GetILGenerator()
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Nop)
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Ldtoken, $StructBuilder)
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Call,
        [Type].GetMethod('GetTypeFromHandle'))
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Call,
        [Runtime.InteropServices.Marshal].GetMethod('PtrToStructure', [Type[]] @([IntPtr], [Type])))
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Unbox_Any, $StructBuilder)
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Ret)
    $StructBuilder.CreateType()
}
$DllName = "netapi32"
$Namespace = "Win32"
$WKSTA_USER_INFO_1 = struct $Mod WKSTA_USER_INFO_1 @{
    UserName = field 0 String -MarshalAs @('LPWStr')
    LogonDomain = field 1 String -MarshalAs @('LPWStr')
    AuthDomains = field 2 String -MarshalAs @('LPWStr')
    LogonServer = field 3 String -MarshalAs @('LPWStr')
}
$Netapi32 = $Types["netapi32"]
$ComputerName = 'localhost'
ForEach ($Computer in $ComputerName) {
    $QueryLevel = 1
    $PtrInfo = [IntPtr]::Zero
    $EntriesRead = 0
    $TotalRead = 0
    $ResumeHandle = 0
    $Result = $Netapi32::NetWkstaUserEnum($Computer, $QueryLevel, [ref]$PtrInfo, -1, [ref]$EntriesRead, [ref]$TotalRead, [ref]$ResumeHandle)
    $Offset = $PtrInfo.ToInt64()
    if (($Result -eq 0) -and ($Offset -gt 0)) {
        $Increment = $WKSTA_USER_INFO_1::GetSize()
        for ($i = 0; ($i -lt $EntriesRead); $i++) {
            $NewIntPtr = New-Object System.Intptr -ArgumentList $Offset
            $Info = $NewIntPtr -as $WKSTA_USER_INFO_1
            $LoggedOn = $Info | Select-Object *
            $LoggedOn | Add-Member Noteproperty 'ComputerName' $Computer
            $Offset = $NewIntPtr.ToInt64()
            $Offset += $Increment
            $LoggedOn
        }
    }
}
