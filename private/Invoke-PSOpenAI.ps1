function Invoke-PSOpenAI {
    <#
    .SYNOPSIS
        Invokes PSOpenAI module functions for image editing, generation, video, and audio.

    .DESCRIPTION
        PSOpenAI is a PowerShell wrapper module (not a CLI) that provides image editing/generation,
        video generation, and audio generation capabilities through the OpenAI API. This function
        handles the invocation of PSOpenAI cmdlets and manages file output.

    .PARAMETER Prompt
        The text prompt for content generation or editing.

    .PARAMETER Model
        The model to use (e.g., 'gpt-4o', 'gpt-image-1', 'sora-2', 'gpt-4o-mini-tts').

    .PARAMETER InputImage
        Path to an existing image file to edit. If provided, uses Request-ImageEdit instead of Request-ImageGeneration.

    .PARAMETER OutputPath
        Optional path where generated files should be saved. If not specified, generates a descriptive filename.

    .PARAMETER GenerationType
        Type of content to generate: Image, Video, or Audio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$InputImage,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [ValidateSet('Image', 'Video', 'Audio')]
        [string]$GenerationType = 'Image'
    )

    Write-PSFMessage -Level Verbose -Message "Invoking PSOpenAI for $GenerationType generation"

    # Check if PSOpenAI module is available
    if (-not (Get-Module -ListAvailable -Name PSOpenAI)) {
        Stop-PSFFunction -Message "PSOpenAI module is not installed. Run: Install-AITool -Name PSOPenAI" -EnableException $true
        return
    }

    # Import the module if not already loaded
    if (-not (Get-Module -Name PSOpenAI)) {
        Write-PSFMessage -Level Verbose -Message "Importing PSOpenAI module"
        Import-Module PSOpenAI -ErrorAction Stop
    }

    # Check for API key
    $apiKey = $env:OPENAI_API_KEY
    if (-not $apiKey) {
        $apiKey = $global:OPENAI_API_KEY
    }

    if (-not $apiKey) {
        Stop-PSFFunction -Message "OpenAI API key not configured. Set `$env:OPENAI_API_KEY or `$global:OPENAI_API_KEY" -EnableException $true
        return
    }

    Write-PSFMessage -Level Verbose -Message "API key found, proceeding with $GenerationType generation"

    try {
        $startTime = Get-Date

        switch ($GenerationType) {
            'Image' {
                # Set default model for image generation/editing if not specified
                if (-not $Model) {
                    $Model = 'gpt-image-1'
                }

                Write-PSFMessage -Level Verbose -Message "Using model: $Model"

                # Check if this is image editing (input image provided) or generation
                if ($InputImage) {
                    Write-PSFMessage -Level Verbose -Message "Editing image: $InputImage"
                    Write-PSFMessage -Level Verbose -Message "Edit prompt: $Prompt"

                    # Verify input image exists
                    if (-not (Test-Path $InputImage)) {
                        Stop-PSFFunction -Message "Input image not found: $InputImage" -EnableException $true
                        return
                    }

                    # Determine output file path
                    if (-not $OutputPath) {
                        # Generate descriptive filename from prompt (max 50 chars)
                        $safePrompt = $Prompt -replace '[^\w\s-]', '' -replace '\s+', '-'
                        $safePrompt = $safePrompt.Substring(0, [Math]::Min(50, $safePrompt.Length)).TrimEnd('-')
                        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                        $extension = [System.IO.Path]::GetExtension($InputImage)
                        if (-not $extension) { $extension = '.png' }
                        $OutputPath = Join-Path (Get-Location) "$safePrompt-$timestamp$extension"
                    }

                    Write-PSFMessage -Level Verbose -Message "Output path: $OutputPath"

                    # Call PSOpenAI image editing
                    Request-ImageEdit -Model $Model -Prompt $Prompt -Image $InputImage -OutFile $OutputPath -Size 1024x1024

                    $endTime = Get-Date
                    Write-PSFMessage -Level Output -Message "Image edited successfully: $OutputPath"

                    # Return structured result
                    [PSCustomObject]@{
                        FileName     = [System.IO.Path]::GetFileName($OutputPath)
                        FullPath     = $OutputPath
                        Tool         = 'PSOPenAI'
                        Model        = $Model
                        Type         = 'ImageEdit'
                        Result       = "Image saved to: $OutputPath"
                        StartTime    = $startTime
                        EndTime      = $endTime
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = $true
                    }
                } else {
                    Write-PSFMessage -Level Verbose -Message "Generating new image with prompt: $Prompt"

                    # Determine output file path
                    if (-not $OutputPath) {
                        # Generate descriptive filename from prompt (max 50 chars)
                        $safePrompt = $Prompt -replace '[^\w\s-]', '' -replace '\s+', '-'
                        $safePrompt = $safePrompt.Substring(0, [Math]::Min(50, $safePrompt.Length)).TrimEnd('-')
                        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                        $OutputPath = Join-Path (Get-Location) "$safePrompt-$timestamp.png"
                    }

                    Write-PSFMessage -Level Verbose -Message "Output path: $OutputPath"

                    # Call PSOpenAI image generation
                    Request-ImageGeneration -Model $Model -Prompt $Prompt -Size 1024x1024 -OutFile $OutputPath

                    $endTime = Get-Date
                    Write-PSFMessage -Level Output -Message "Image generated successfully: $OutputPath"

                    # Return structured result
                    [PSCustomObject]@{
                        FileName     = [System.IO.Path]::GetFileName($OutputPath)
                        FullPath     = $OutputPath
                        Tool         = 'PSOPenAI'
                        Model        = $Model
                        Type         = 'ImageGeneration'
                        Result       = "Image saved to: $OutputPath"
                        StartTime    = $startTime
                        EndTime      = $endTime
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = $true
                    }
                }
            }

            'Video' {
                Write-PSFMessage -Level Verbose -Message "Generating video with prompt: $Prompt"

                # Set default model for video generation if not specified
                if (-not $Model) {
                    $Model = 'sora-2'
                }

                # Determine output file path
                if (-not $OutputPath) {
                    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                    $OutputPath = Join-Path (Get-Location) "generated_video_$timestamp.mp4"
                }

                Write-PSFMessage -Level Verbose -Message "Using model: $Model"
                Write-PSFMessage -Level Verbose -Message "Output path: $OutputPath"

                # Call PSOpenAI video generation
                $videoJob = New-Video -Model $Model -Prompt $Prompt -Size 1280x720
                $videoJob | Get-VideoContent -OutFile $OutputPath -WaitForCompletion

                $endTime = Get-Date
                Write-PSFMessage -Level Output -Message "Video generated successfully: $OutputPath"

                # Return structured result
                [PSCustomObject]@{
                    FileName     = [System.IO.Path]::GetFileName($OutputPath)
                    FullPath     = $OutputPath
                    Tool         = 'PSOPenAI'
                    Model        = $Model
                    Type         = 'Video'
                    Result       = "Video saved to: $OutputPath"
                    StartTime    = $startTime
                    EndTime      = $endTime
                    Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                    Success      = $true
                }
            }

            'Audio' {
                Write-PSFMessage -Level Verbose -Message "Generating audio with prompt: $Prompt"

                # Set default model for audio generation if not specified
                if (-not $Model) {
                    $Model = 'gpt-4o-mini-tts'
                }

                # Determine output file path
                if (-not $OutputPath) {
                    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                    $OutputPath = Join-Path (Get-Location) "generated_audio_$timestamp.mp3"
                }

                Write-PSFMessage -Level Verbose -Message "Using model: $Model"
                Write-PSFMessage -Level Verbose -Message "Output path: $OutputPath"

                # Call PSOpenAI audio generation
                Request-AudioSpeech -Model $Model -Text $Prompt -OutFile $OutputPath -Voice shimmer

                $endTime = Get-Date
                Write-PSFMessage -Level Output -Message "Audio generated successfully: $OutputPath"

                # Return structured result
                [PSCustomObject]@{
                    FileName     = [System.IO.Path]::GetFileName($OutputPath)
                    FullPath     = $OutputPath
                    Tool         = 'PSOPenAI'
                    Model        = $Model
                    Type         = 'Audio'
                    Result       = "Audio saved to: $OutputPath"
                    StartTime    = $startTime
                    EndTime      = $endTime
                    Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                    Success      = $true
                }
            }
        }
    } catch {
        Write-PSFMessage -Level Error -Message "PSOpenAI invocation failed: $_"
        throw
    }
}
