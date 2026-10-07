@{
    RootModule           = 'SyncCheck.psm1'
    ModuleVersion        = '1.3.0'
    GUID                 = '0d768e75-66f1-41ec-ba80-2c2438f6cdf5'
    Author               = 'Wilson Neves de Almeida Junior'
    CompanyName          = 'Community'
    Copyright            = '(c) 2026 Wilson Neves de Almeida Junior. MIT License.'
    Description          = 'Read-only Active Directory readiness check for Microsoft Entra Connect / Cloud Sync (IdFix-style checks): UPN suffix and characters, mail, proxyAddresses, duplicates, length limits. Generates CSV and HTML reports. Relatorio em portugues (pt-BR).'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Invoke-SyncCheck')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('ActiveDirectory', 'EntraID', 'EntraConnect', 'AzureADConnect', 'CloudSync', 'IdFix', 'Microsoft365', 'Hybrid', 'Identity', 'Windows')
            LicenseUri   = 'https://github.com/wjralmeida/SyncCheck/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/wjralmeida/SyncCheck'
            ReleaseNotes = 'https://github.com/wjralmeida/SyncCheck/blob/main/CHANGELOG.md'
        }
    }
}
