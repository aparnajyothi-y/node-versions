Import-Module (Join-Path $PSScriptRoot "../helpers/pester-extensions.psm1")

Describe "Node.js" {

    BeforeAll {

        function Get-UseNodeLogs {

            # Runner.Listener is not always discoverable on GitHub-hosted runners
            $listenerProcess = Get-Process -Name "Runner.Listener" -ErrorAction SilentlyContinue | Select-Object -First 1

            if (-not $listenerProcess) {
                Write-Warning "Runner.Listener process not found. Runner diagnostics may not be accessible on this runner."
                return $null
            }

            $runnerExePath = $listenerProcess.Path
            if (-not $runnerExePath) {
                Write-Warning "Unable to resolve Runner.Listener executable path."
                return $null
            }

            $runnerRoot = Split-Path -Path $runnerExePath -Parent
            $diagPagesPath = Join-Path -Path $runnerRoot -ChildPath "_diag/pages"

            if (-not (Test-Path $diagPagesPath)) {
                Write-Warning "Diagnostics pages directory not found: $diagPagesPath"
                return $null
            }

            $useNodeLogFile = Get-ChildItem -Path $diagPagesPath -File | Where-Object {
                $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                $content -match "setup-node@v"
            } | Select-Object -First 1

            if ($useNodeLogFile) {
                return $useNodeLogFile.FullName
            }

            Write-Warning "No setup-node diagnostics log found."
            return $null
        }
    }

    It "is available" {
        "node --version" | Should -ReturnZeroExitCode
    }

    It "version is correct" {
        $versionOutput = Invoke-Expression "node --version"
        $versionOutput | Should -Match $env:VERSION
    }

    It "is used from tool-cache" {
        $nodePath = (Get-Command "node").Path
        $nodePath | Should -Not -BeNullOrEmpty

        # GitHub Windows images don't have `AGENT_TOOLSDIRECTORY`
        $toolcacheDir = $env:AGENT_TOOLSDIRECTORY ?? $env:RUNNER_TOOL_CACHE
        $expectedPath = Join-Path -Path $toolcacheDir -ChildPath "node"

        $nodePath.StartsWith($expectedPath) | Should -BeTrue `
            -Because "'$nodePath' does not start with expected tool-cache path '$expectedPath'"
    }

    It "cached version is used without downloading" {

        if ($env:RUNNER_TYPE -eq "self-hosted") {

            # Self-hosted runners: validate availability and version only
            $nodeVersion = Invoke-Expression "node --version"
            $nodeVersion | Should -Not -BeNullOrEmpty
            $nodeVersion | Should -Match $env:VERSION

        } else {

            # GitHub-hosted runners: diagnostics-based validation is best-effort
            $useNodeLogFile = Get-UseNodeLogs

            if ($useNodeLogFile) {
                $useNodeLogContent = Get-Content $useNodeLogFile -Raw
                $useNodeLogContent | Should -Match "Found in cache"
            } else {
                Set-ItResult -Skipped -Because "Runner diagnostics are not accessible on this runner"
            }
        }
    }

    It "runs simple code" {
        "node ./simple-test.js" | Should -ReturnZeroExitCode
    }
}
