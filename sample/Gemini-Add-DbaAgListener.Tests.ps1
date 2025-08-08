#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaAgListener",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "AvailabilityGroup",
                "Name",
                "IPAddress",
                "SubnetIP",
                "SubnetMask",
                "Port",
                "Dhcp",
                "Passthru",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $script:agname = "dbatoolsci_ag_newlistener"
        $script:listenerName = "dbatoolsci_listener"

        $splatAg = @{
            Primary      = $TestConfig.instance3
            Name         = $script:agname
            ClusterType  = "None"
            FailoverMode = "Manual"
            Confirm      = $false
            Certificate  = "dbatoolsci_AGCert"
        }
        $script:ag = New-DbaAvailabilityGroup @splatAg

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $splatRemoveListener = @{
            SqlInstance       = $TestConfig.instance3
            Listener          = $script:listenerName
            AvailabilityGroup = $script:agname
            Confirm           = $false
            ErrorAction       = "SilentlyContinue"
        }
        $null = Remove-DbaAgListener @splatRemoveListener
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $splatRemoveAg = @{
            SqlInstance       = $TestConfig.instance3
            AvailabilityGroup = $script:agname
            Confirm           = $false
        }
        $null = Remove-DbaAvailabilityGroup @splatRemoveAg
    }

    Context "creates a listener" {
        It "returns results with proper data" {
            $splatAddListener = @{
                Name      = $script:listenerName
                IPAddress = "127.0.20.1"
                Confirm   = $false
            }
            $results = $script:ag | Add-DbaAgListener @splatAddListener
            $results.PortNumber | Should -Be 1433
        }
    }
} #$script:instance2 for appveyor
