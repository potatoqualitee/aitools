BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..' 'aitools.psd1'
    Import-Module $modulePath -Force

    # Ensure CLAUDE_CODE_OAUTH_TOKEN is available
    if ([string]::IsNullOrEmpty($env:CLAUDE_CODE_OAUTH_TOKEN)) {
        throw "CLAUDE_CODE_OAUTH_TOKEN environment variable is not set. Please set it before running tests."
    }
}

Describe 'AITools Module Integration Tests' {
    Context 'Module Import' {
        It 'Should import the aitools module successfully' {
            $module = Get-Module -Name aitools
            $module | Should -Not -BeNullOrEmpty
            $module.Name | Should -Be 'aitools'
        }

        It 'Should have all required commands' {
            $commands = @(
                'Install-AITool',
                'Set-AIToolDefault',
                'Invoke-AITool',
                'Initialize-AITool',
                'Get-AIToolConfig',
                'Set-AIToolConfig',
                'Clear-AIToolConfig',
                'Update-AITool',
                'Uninstall-AITool',
                'Update-PesterTest',
                'Get-AITPrompt'
            )

            foreach ($command in $commands) {
                Get-Command $command -Module aitools -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Install-AITool' {
        It 'Should have Claude installed' {
            # Verify Claude is installed (required for tests)
            $claude = Get-Command claude -ErrorAction SilentlyContinue
            $claude | Should -Not -BeNullOrEmpty
            Write-Host "Claude installed at: $($claude.Source)"
        }

        It 'Should return proper installation result object when already installed' {
            # Re-run install to check the output format (should detect already installed)
            $result = Install-AITool -Name Claude -SkipInitialization
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames | Should -Contain 'AITools.InstallResult'
            $result.Tool | Should -Be 'Claude'
            $result.Result | Should -Be 'Success'
            $result.Version | Should -Not -BeNullOrEmpty
            $result.Path | Should -Not -BeNullOrEmpty
            $result.Installer | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Set-AIToolDefault' {
        It 'Should set Claude as default tool' {
            $result = Set-AIToolDefault -Tool Claude
            $result | Should -Not -BeNullOrEmpty
            $result.FullName | Should -Be 'AITools.DefaultTool'
            $result.Value | Should -Be 'Claude'
        }

        It 'Should retrieve default tool configuration using Get-PSFConfigValue' {
            $defaultTool = Get-PSFConfigValue -FullName 'AITools.DefaultTool'
            $defaultTool | Should -Be 'Claude'
        }
    }

    Context 'Invoke-AITool Quick Chat' {
        It 'Should successfully run a quick chat with "Hello"' {
            $result = Invoke-AITool -Prompt "Hello" -Tool Claude
            $result | Should -Not -BeNullOrEmpty
            $result.Tool | Should -Be 'Claude'
            $result.Success | Should -Be $true
            $result.Result | Should -Not -BeNullOrEmpty
        }

        It 'Should return proper result object structure' {
            $result = Invoke-AITool -Prompt "Say hi" -Tool Claude
            $result | Should -Not -BeNullOrEmpty
            $result.FileName | Should -Be 'N/A (Chat Mode)'
            $result.FullPath | Should -Be 'N/A (Chat Mode)'
            $result.Tool | Should -Be 'Claude'
            $result.Model | Should -Not -BeNullOrEmpty
            $result.StartTime | Should -Not -BeNullOrEmpty
            $result.EndTime | Should -Not -BeNullOrEmpty
            $result.Duration | Should -Not -BeNullOrEmpty
        }

        It 'Should handle chat with CLAUDE_CODE_OAUTH_TOKEN environment variable' {
            $env:CLAUDE_CODE_OAUTH_TOKEN | Should -Not -BeNullOrEmpty
            $result = Invoke-AITool -Prompt "Quick test" -Tool Claude
            $result.Success | Should -Be $true
        }
    }

    Context 'File Processing with Invoke-AITool' {
        BeforeAll {
            # Create a temporary test file
            $script:tempFile = Join-Path $TestDrive 'test-script.ps1'
            $testContent = @'
function Get-TestData {
    param($Name)
    return "Test: $Name"
}
'@
            Set-Content -Path $script:tempFile -Value $testContent
        }

        It 'Should process a file with a prompt' {
            $result = Invoke-AITool -Path $script:tempFile -Prompt "Add comment-based help to this function" -Tool Claude
            $result | Should -Not -BeNullOrEmpty
            $result.FileName | Should -Be 'test-script.ps1'
            $result.FullPath | Should -Match 'test-script\.ps1$'
            $result.Tool | Should -Be 'Claude'
        }

        It 'Should return success status for file processing' {
            $result = Invoke-AITool -Path $script:tempFile -Prompt "Add a return type hint" -Tool Claude
            $result.Success | Should -Be $true
        }
    }

    Context 'DbaTools Repository Operations' {
        BeforeAll {
            # Clone dbatools if not already cloned
            $script:dbaToolsPath = Join-PSFPath -Path $PSScriptRoot -ChildPath '..', 'dbatools'
            if (-not (Test-Path -Path $script:dbaToolsPath)) {
                Push-Location -Path (Join-PSFPath -Path $PSScriptRoot -ChildPath '..')
                git clone --depth 1 https://github.com/dataplat/dbatools.git
                Pop-Location
            }

            $script:testFilePath = Join-PSFPath -Path $script:dbaToolsPath -ChildPath 'tests', 'Invoke-DbaDbShrink.Tests.ps1'
        }

        It 'Should have cloned dbatools repository' {
            Test-Path $script:dbaToolsPath | Should -Be $true
        }

        It 'Should find the test file Invoke-DbaDbShrink.Tests.ps1' {
            Test-Path $script:testFilePath | Should -Be $true
        }

        It 'Should refactor the test file without errors' {
            if (Test-Path $script:testFilePath) {
                $result = Get-ChildItem $script:testFilePath | Update-PesterTest
                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $true
            }
        }

        It 'Should show differences after refactoring' {
            if (Test-Path $script:dbaToolsPath) {
                Push-Location $script:dbaToolsPath
                $diff = git diff tests/Invoke-DbaDbShrink.Tests.ps1
                Pop-Location

                # Diff might be empty if no changes were made, or contain changes
                # We just verify the command runs without error
                $LASTEXITCODE | Should -Be 0
                Write-Host "Git diff output length: $($diff.Length)"
            }
        }
    }

    Context 'Get-AIToolConfig' {
        It 'Should retrieve tool configuration' {
            # Get-AIToolConfig returns PSFConfig objects
            $config = Get-AIToolConfig -Tool Claude
            # Config might be empty if no settings were applied, so just check it doesn't error
            # If there are configs, they should have FullName property
            if ($config) {
                $config[0].PSObject.Properties['FullName'] | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should retrieve all configurations when no tool specified' {
            $config = Get-AIToolConfig
            # This returns all AITools.* configs, should not error
            # May be empty or populated depending on what's been configured
            $config | Should -Not -BeNull
        }
    }

    Context 'Command Availability' {
        It 'Should have claude command available' {
            $claude = Get-Command claude -ErrorAction SilentlyContinue
            $claude | Should -Not -BeNullOrEmpty
        }

        It 'Should be able to get claude version' {
            $version = & claude --version 2>&1 | Select-Object -First 1
            $version | Should -Not -BeNullOrEmpty
            Write-Host "Claude version: $version"
        }
    }

    Context 'ContextFilter Parameter' {
        BeforeAll {
            $script:recipesPath = Join-Path $PSScriptRoot 'recipes'
            # Set PSFramework message level to capture debug messages
            Set-PSFConfig -FullName 'PSFramework.Message.Info.Maximum' -Value 9
        }

        It 'Should have test recipe files available' {
            Test-Path (Join-Path $script:recipesPath 'alligator-eggs.md') | Should -Be $true
            Test-Path (Join-Path $script:recipesPath 'alligator-eggs.fr.md') | Should -Be $true
            Test-Path (Join-Path $script:recipesPath 'alligator-eggs.fr-ca.md') | Should -Be $true
        }

        It 'Should resolve context file from ContextFilter (deterministic)' {
            $frFile = Join-Path $script:recipesPath 'alligator-eggs.fr.md'
            # Clear previous messages and run with -WhatIf to avoid API call
            Get-PSFMessage | Out-Null
            $null = Invoke-AITool -Path $frFile -Prompt "test" -Tool Claude -ContextFilter { $_ -replace '\.fr\.md$', '.md' } -WhatIf

            # Check debug messages to verify context file was found
            $messages = Get-PSFMessage -Last 50 | Where-Object Message -Match 'ContextFilter'
            $foundMessage = $messages | Where-Object Message -Match 'Found at:.*alligator-eggs\.md'
            $foundMessage | Should -Not -BeNullOrEmpty -Because "ContextFilter should find alligator-eggs.md"
        }

        It 'Should resolve context file using ContextFilterBase (deterministic)' {
            $frCaFile = Join-Path $script:recipesPath 'alligator-eggs.fr-ca.md'
            Get-PSFMessage | Out-Null
            $null = Invoke-AITool -Path $frCaFile -Prompt "test" -Tool Claude `
                -ContextFilter { [System.IO.Path]::GetFileName($_) -replace '\.fr-ca\.md$', '.md' } `
                -ContextFilterBase $script:recipesPath -WhatIf

            # Verify it searched in ContextFilterBase and found the file
            $messages = Get-PSFMessage -Last 50 | Where-Object Message -Match 'ContextFilter'
            $foundMessage = $messages | Where-Object Message -Match 'Found at:.*alligator-eggs\.md'
            $foundMessage | Should -Not -BeNullOrEmpty -Because "ContextFilter should find alligator-eggs.md via ContextFilterBase"
        }

        It 'Should deduplicate context files in batch mode (deterministic)' {
            # Both .fr.md and .fr-ca.md derive the same .md file
            $frFiles = Get-ChildItem -Path $script:recipesPath -Filter '*.fr*.md'
            Get-PSFMessage | Out-Null
            $null = $frFiles | Invoke-AITool -Prompt "test" -Tool Claude `
                -ContextFilter { $_ -replace '\.fr(-ca)?\.md$', '.md' } -BatchSize 3 -WhatIf

            # Check that deduplication message appears (second file should be skipped)
            $messages = Get-PSFMessage -Last 50 | Where-Object Message -Match 'ContextFilter'
            $skipMessage = $messages | Where-Object Message -Match 'Skipping duplicate:.*alligator-eggs\.md'
            $skipMessage | Should -Not -BeNullOrEmpty -Because "Second derived file should be skipped as duplicate"
        }

        It 'Should warn when ContextFilter derived file does not exist' {
            $frFile = Join-Path $script:recipesPath 'alligator-eggs.fr.md'
            Get-PSFMessage | Out-Null
            $null = Invoke-AITool -Path $frFile -Prompt "test" -Tool Claude `
                -ContextFilter { $_ -replace '\.fr\.md$', '.nonexistent.md' } -WhatIf -WarningVariable warnings

            # Should have warned about missing file
            $messages = Get-PSFMessage -Last 50 | Where-Object Level -eq 'Warning'
            $warningMessage = $messages | Where-Object Message -Match 'ContextFilter derived file not found.*nonexistent'
            $warningMessage | Should -Not -BeNullOrEmpty -Because "Should warn about missing derived file"
        }

        It 'Should work end-to-end with ContextFilter (integration)' {
            $frFile = Join-Path $script:recipesPath 'alligator-eggs.fr.md'
            # One real API call to verify the whole flow works
            $result = Invoke-AITool -Path $frFile -Prompt "List ALL the filenames visible in this prompt. Output ONLY the filenames, one per line, nothing else." -Tool Claude -ContextFilter { $_ -replace '\.fr\.md$', '.md' }

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.Tool | Should -Be 'Claude'
            # Claude should see and mention both files
            $result.Result | Should -Match 'alligator-eggs'
        }

        It 'Should work with null ContextFilter (no-op)' {
            $frFile = Join-Path $script:recipesPath 'alligator-eggs.fr.md'
            $result = Invoke-AITool -Path $frFile -Prompt "Say hello" -Tool Claude

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
        }
    }
}

AfterAll {
    # Clean up if needed
    Write-Host "Tests completed"
}
