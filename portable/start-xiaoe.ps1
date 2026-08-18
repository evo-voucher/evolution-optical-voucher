param(
  [switch]$SkipAuth
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateDir = Join-Path $scriptRoot 'state'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

function Fail-Closed([string]$Message) {
  Write-Host "[STOP] $Message" -ForegroundColor Red
  Write-Host "No repository write was performed."
  exit 1
}

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Fail-Closed "$Name is required for this MVP. Install GitHub CLI (gh) and try again."
  }
}

function Invoke-GhJson([string[]]$Args) {
  $raw = & gh @Args 2>$null
  if ($LASTEXITCODE -ne 0) { throw "gh command failed: gh $($Args -join ' ')" }
  if (-not $raw) { return $null }
  return ($raw | ConvertFrom-Json)
}

Clear-Host
Write-Host 'XiaoE Portable v1' -ForegroundColor Cyan
Write-Host 'Root Before Flower — ACTIVE'
Write-Host 'Mode: Discovery only (read-only)'
Write-Host ''

Require-Command 'gh'

if (-not $SkipAuth) {
  & gh auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Host '[auth] GitHub authorization is required.' -ForegroundColor Yellow
    Write-Host '[security] XiaoE will not request or store your GitHub password.'
    & gh auth login --web --git-protocol https
    if ($LASTEXITCODE -ne 0) { Fail-Closed 'GitHub authorization failed.' }
  }
}

& gh auth status
if ($LASTEXITCODE -ne 0) { Fail-Closed 'GitHub authorization is unavailable or expired.' }

Write-Host ''
Write-Host '[discovery] Loading accessible repositories...' -ForegroundColor Cyan
$repos = Invoke-GhJson @('repo','list','--limit','100','--json','nameWithOwner,isPrivate,url,defaultBranchRef')
if (-not $repos -or $repos.Count -eq 0) { Fail-Closed 'No accessible repositories were returned.' }

for ($i = 0; $i -lt $repos.Count; $i++) {
  $defaultBranch = if ($repos[$i].defaultBranchRef) { $repos[$i].defaultBranchRef.name } else { '?' }
  $visibility = if ($repos[$i].isPrivate) { 'private' } else { 'public' }
  Write-Host ("[{0}] {1} ({2}, default={3})" -f ($i+1), $repos[$i].nameWithOwner, $visibility, $defaultBranch)
}

$selectionRaw = Read-Host 'Select repository number'
[int]$selection = 0
if (-not [int]::TryParse($selectionRaw, [ref]$selection)) { Fail-Closed 'Repository selection was not a number.' }
if ($selection -lt 1 -or $selection -gt $repos.Count) { Fail-Closed 'Repository selection is out of range.' }
$repo = $repos[$selection-1]
$repoName = $repo.nameWithOwner

Write-Host ''
Write-Host "[selected] $repoName" -ForegroundColor Green
Write-Host '[guard] Starting bounded read-only discovery.'

$repoMeta = Invoke-GhJson @('repo','view',$repoName,'--json','nameWithOwner,description,url,isPrivate,defaultBranchRef,languages,viewerPermission')
$branches = Invoke-GhJson @('api',"repos/$repoName/branches?per_page=100")
$prs = Invoke-GhJson @('pr','list','--repo',$repoName,'--state','open','--limit','50','--json','number,title,headRefName,baseRefName,updatedAt')
$issues = Invoke-GhJson @('issue','list','--repo',$repoName,'--state','open','--limit','50','--json','number,title,updatedAt')
$commits = Invoke-GhJson @('api',"repos/$repoName/commits?per_page=20")

$defaultBranch = $repoMeta.defaultBranchRef.name
$tree = $null
try {
  $tree = Invoke-GhJson @('api',"repos/$repoName/git/trees/$defaultBranch`?recursive=1")
} catch {
  Write-Host '[warn] Recursive tree discovery was unavailable; continuing with bounded metadata.' -ForegroundColor Yellow
}

$interesting = @()
if ($tree -and $tree.tree) {
  $patterns = @(
    '^README', '^package\.json$', '^pyproject\.toml$', '^requirements.*\.txt$', '^go\.mod$', '^Cargo\.toml$', '^Gemfile$',
    '^Dockerfile$', '^docker-compose', '^\.github/workflows/', '^supabase/', '^migrations/', '^infra/', '^terraform/', '^vercel\.json$', '^netlify\.toml$', '^XIAOE_PROJECT\.md$'
  )
  foreach ($entry in $tree.tree) {
    if ($entry.type -ne 'blob') { continue }
    foreach ($pattern in $patterns) {
      if ($entry.path -match $pattern) { $interesting += $entry.path; break }
    }
  }
}

$checkpoint = [ordered]@{
  schema = 'xiaoe-portable-checkpoint-v1'
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = 'discovery-read-only'
  root_before_flower = $true
  repository = [ordered]@{
    name = $repoMeta.nameWithOwner
    url = $repoMeta.url
    private = $repoMeta.isPrivate
    default_branch = $defaultBranch
    viewer_permission = $repoMeta.viewerPermission
    description = $repoMeta.description
  }
  discovery = [ordered]@{
    branches = @($branches | ForEach-Object { $_.name })
    open_pull_requests = @($prs)
    open_issues = @($issues)
    recent_commit_shas = @($commits | ForEach-Object { $_.sha })
    interesting_paths = @($interesting | Sort-Object -Unique)
    production_boundary = 'unknown-until-evidence'
  }
  security = [ordered]@{
    plaintext_secrets_stored = $false
    repository_write_performed = $false
  }
}

$safeName = ($repoName -replace '[^A-Za-z0-9._-]','__')
$checkpointPath = Join-Path $stateDir "$safeName.checkpoint.json"
$checkpoint | ConvertTo-Json -Depth 8 | Set-Content -Path $checkpointPath -Encoding UTF8

Write-Host ''
Write-Host '[PASS] Read-only discovery complete.' -ForegroundColor Green
Write-Host "[checkpoint] $checkpointPath"
Write-Host '[risk] Production boundary remains UNKNOWN until repository evidence establishes it.' -ForegroundColor Yellow
Write-Host '[ready] Project facts captured. 小E can now load this checkpoint before engineering work.'
Write-Host ''
Write-Host 'No branch, file, deployment, database, or auth-setting write was performed by this launcher.'
