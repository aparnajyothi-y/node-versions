Import-Module (Join-Path $PSScriptRoot "../helpers/pester-extensions.psm1")

Describe "Node.js" {

    BeforeAll {

        function Get-UseNodeLogs {

            # Locate the active Runner.Listener process
            $listenerProcess = Get-Process -Name "Runner.Listener" -ErrorAction SilentlyContinue | Select-Object -First 1

            if (-not $listenerProcess) {
                Write-Error "Runner.Listener process not found. Unable to locate runner diagnostics."
                return
            }

            # Resolve the runner executable path
            $runnerExePath = $listenerProcess.Path
            if (-not $runnerExePath) {
                Write-Error "Unable to resolve Runner.Listener executable path."
                return
            }

            # Runner root directory (varies based on selected runner version)
            $runnerRoot = Split-Path -Path $runnerExePath -Parent

            # Diagnostics pages directory relative to active runner
            $diagPagesPath = Join-Path -Path $runnerRoot -ChildPath "_diag/pages"

            if (-not (Test-Path $diagPagesPath)) {
                Write-Error "Diagnostics pages directory not found at expected location: $diagPagesPath"
                return
            }

            # Find the setup-node log file
            $useNodeLogFile = Get-ChildItem -Path $diagPagesPath -File | Where-Object {
                $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                $content -match "setup-node@v"
            } | Select-Object -First 1

            if ($useNodeLogFile) {
                return $useNodeLogFile.FullName
            }

            Write-Error "No setup-node log file found under diagnostics path: $diagPagesPath"
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

            # On self-hosted runners, validate availability and version only
            $nodeVersion = Invoke-Expression "node --version"
            $nodeVersion | Should -Not -BeNullOrEmpty
            $nodeVersion | Should -Match $env:VERSION

        } else {

            # On GitHub-hosted runners, verify cache usage via diagnostics
            $useNodeLogFile = Get-UseNodeLogs
            $useNodeLogFile | Should -Exist

            $useNodeLogContent = Get-Content $useNodeLogFile -Raw
            $useNodeLogContent | Should -Match "Found in cache"
        }
    }

    It "runs simple code" {
        "node ./simple-test.js" | Should -ReturnZeroExitCode
    }
}
