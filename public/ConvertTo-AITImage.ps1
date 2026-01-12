function ConvertTo-AITImage {
    <#
    .SYNOPSIS
        Converts PDF files to PNG images optimized for AI vision models.

    .DESCRIPTION
        Converts PDF documents to high-quality PNG images suitable for AI model consumption.
        Uses pdf2img (auto-installed on first use) which embeds PDFium via WebAssembly for
        reliable cross-platform PDF rendering with no external dependencies.

        PNG format is chosen as the default because:
        - Lossless compression preserves text clarity for OCR/vision models
        - Universal support across all AI vision APIs
        - Excellent balance of quality and file size for document images

        Each page of the PDF becomes a separate PNG file with the naming convention:
        <original-name>_page_<number>.png

    .PARAMETER InputObject
        FileInfo objects from Get-ChildItem. Accepts pipeline input.
        Only .pdf files are processed; other files are passed through unchanged.

    .PARAMETER Path
        Path to a PDF file or directory containing PDF files.

    .PARAMETER OutputDirectory
        Directory where converted images will be saved.
        Defaults to the same directory as the source PDF.

    .PARAMETER DPI
        Resolution for the output images. Higher DPI = better quality but larger files.
        Default: 150 (good balance for AI vision models)
        Recommended: 150-300 for text documents, 72-150 for images/graphics

    .PARAMETER PassThru
        When specified with non-PDF files, passes them through to output unchanged.
        PDF files are always converted and their output images returned.

    .EXAMPLE
        Get-ChildItem *.pdf | ConvertTo-AITImage
        Converts all PDFs in current directory to PNG images.

    .EXAMPLE
        Get-ChildItem -Recurse -Filter *.pdf | ConvertTo-AITImage -DPI 300
        Recursively converts all PDFs with higher quality output.

    .EXAMPLE
        ConvertTo-AITImage -Path "document.pdf" -OutputDirectory "./images"
        Converts a single PDF to images in a specific directory.

    .EXAMPLE
        Get-ChildItem ./docs | ConvertTo-AITImage -PassThru | Invoke-AITool -Tool Claude
        Converts PDFs and passes all files (images + non-PDFs) to Claude for analysis.

    .OUTPUTS
        System.IO.FileInfo
        FileInfo objects for the generated PNG images (and passed-through files if -PassThru).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(ParameterSetName = 'Pipeline', ValueFromPipeline, Position = 0)]
        [System.IO.FileInfo[]]$InputObject,

        [Parameter(ParameterSetName = 'Path', Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$OutputDirectory,

        [Parameter()]
        [ValidateRange(72, 600)]
        [int]$DPI = 150,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        # Check if pdf2img is installed, install if not
        if (-not (Test-Command -Command 'pdf2img')) {
            Write-PSFMessage -Level Host -Message "pdf2img not found. Installing..."

            $installResult = Install-Pdf2Img
            if (-not $installResult) {
                Stop-PSFFunction -Message "Failed to install pdf2img. Cannot convert PDFs." -EnableException $true
                return
            }

            # Verify it's now available
            if (-not (Test-Command -Command 'pdf2img')) {
                Stop-PSFFunction -Message "pdf2img installed but not found in PATH. Please restart your shell and try again." -EnableException $true
                return
            }
        }

        # Collect files to process
        $filesToProcess = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    }

    process {
        # Handle Path parameter
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (Test-Path $Path -PathType Container) {
                # Directory - get all PDFs
                $files = Get-ChildItem -Path $Path -Filter '*.pdf' -File
                foreach ($file in $files) {
                    $filesToProcess.Add($file)
                }
            } elseif (Test-Path $Path -PathType Leaf) {
                # Single file
                $filesToProcess.Add((Get-Item $Path))
            } else {
                Write-PSFMessage -Level Warning -Message "Path not found: $Path"
            }
        }

        # Handle pipeline input
        if ($InputObject) {
            foreach ($file in $InputObject) {
                $filesToProcess.Add($file)
            }
        }
    }

    end {
        foreach ($file in $filesToProcess) {
            # Check if it's a PDF
            if ($file.Extension -ne '.pdf') {
                if ($PassThru) {
                    # Pass through non-PDF files
                    $file
                } else {
                    Write-PSFMessage -Level Verbose -Message "Skipping non-PDF file: $($file.Name)"
                }
                continue
            }

            Write-PSFMessage -Level Verbose -Message "Converting: $($file.FullName)"

            # Determine output directory
            $outDir = if ($OutputDirectory) {
                $OutputDirectory
            } else {
                $file.DirectoryName
            }

            # Ensure output directory exists
            if (-not (Test-Path $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            }

            # pdf2img outputs: <basename>_page_001.png, <basename>_page_002.png, etc.
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

            # Remove any existing output files to avoid confusion
            $existingFiles = Get-ChildItem -Path $outDir -Filter "${baseName}_page_*.png" -ErrorAction SilentlyContinue
            if ($existingFiles) {
                Write-PSFMessage -Level Verbose -Message "Removing $($existingFiles.Count) existing output file(s)"
                $existingFiles | Remove-Item -Force
            }

            # Run pdf2img
            # Usage: pdf2img <input.pdf> [options]
            # -o, --output string   Output directory (default: same as input file)
            $arguments = @(
                "`"$($file.FullName)`"",
                '--dpi', $DPI,
                '--format', 'png',
                '-o', "`"$outDir`""
            )

            Write-PSFMessage -Level Verbose -Message "Running: pdf2img $($arguments -join ' ')"

            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = 'pdf2img'
                $psi.Arguments = $arguments -join ' '
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true

                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $psi
                $process.Start() | Out-Null

                $stdout = $process.StandardOutput.ReadToEnd()
                $stderr = $process.StandardError.ReadToEnd()
                $process.WaitForExit()

                if ($stdout) {
                    $stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
                        Write-PSFMessage -Level Verbose -Message $_
                    }
                }

                if ($process.ExitCode -ne 0) {
                    Write-PSFMessage -Level Warning -Message "pdf2img failed for $($file.Name): $stderr"
                    continue
                }

                # Get the generated files
                # pdf2img creates files like: basename_page_1.png, basename_page_2.png
                $generatedFiles = Get-ChildItem -Path $outDir -Filter "$baseName`_page_*.png" -File |
                    Sort-Object { [int]($_.BaseName -replace '.*_page_(\d+)$', '$1') }

                if (-not $generatedFiles) {
                    # Try alternate pattern in case naming changed
                    $generatedFiles = Get-ChildItem -Path $outDir -Filter "$baseName*.png" -File |
                        Where-Object { $_.Name -ne "$baseName.png" -or $_.LastWriteTime -gt $file.LastWriteTime } |
                        Sort-Object Name
                }

                if ($generatedFiles) {
                    Write-PSFMessage -Level Verbose -Message "Generated $($generatedFiles.Count) image(s) from $($file.Name)"
                    # Output the FileInfo objects
                    $generatedFiles
                } else {
                    Write-PSFMessage -Level Warning -Message "No output files generated for $($file.Name)"
                }

            } catch {
                Write-PSFMessage -Level Warning -Message "Error converting $($file.Name): $_"
            }
        }
    }
}
