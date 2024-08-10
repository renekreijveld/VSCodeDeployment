param (
    [string]$DEPLOY_MODE,
    [string]$ENVIRONMENT
)

if ($DEPLOY_MODE -notin @('local', 'remote', 'alllocal', 'allremote')) {
    Write-Host "Error: DEPLOY_MODE must be either 'local', 'remote', 'alllocal', or 'allremote'."
    exit 1
}

if (-not $ENVIRONMENT) {
    Write-Host "Error: no config file specified."
    exit 1
}

$configPath = "$HOME\bin\.config\$ENVIRONMENT"
if (-not (Test-Path $configPath)) {
    Write-Host "Error: $ENVIRONMENT config file not found."
    exit 1
}

. $configPath

function Should-Ignore($item) {
    foreach ($ignore in $FILES_TO_IGNORE) {
        if ($item -eq $ignore -or $item -like "$ignore\*") {
            return $true
        }
    }
    return $false
}

function Deploy-Local {
    Write-Host "Uploads:"
    foreach ($file in $CHANGED_FILES) {
        Write-Host "- $file"
        Copy-Item "$LOCAL_REPO_PATH\$file" "$LOCAL_PATH\$file"
    }

    Write-Host "Deletions:"
    foreach ($file in $DELETED_FILES) {
        Write-Host "- $file"
        Remove-Item "$LOCAL_PATH\$file" -Force
    }
}

function Deploy-Remote {
    Write-Host "Uploads:"
    foreach ($file in $CHANGED_FILES) {
        Write-Host "- $file"
        & scp "$LOCAL_REPO_PATH\$file" "$SSH_CONFIG:$REMOTE_PATH/$file"
        & ssh "$SSH_CONFIG" "chmod 0644 $REMOTE_PATH/$file"
    }

    Write-Host "Deletions:"
    foreach ($file in $DELETED_FILES) {
        Write-Host "- $file"
        & ssh "$SSH_CONFIG" "rm -f $REMOTE_PATH/$file"
    }
}

function Deploy-All-Local {
    Get-ChildItem -Path $LOCAL_REPO_PATH -Exclude $FILES_TO_IGNORE | ForEach-Object {
        $item = $_.Name
        if (-not (Should-Ignore $item)) {
            Write-Host "- $item"
            Copy-Item "$LOCAL_REPO_PATH\$item" "$LOCAL_PATH" -Recurse
        }
    }
}

function Deploy-All-Remote {
    Get-ChildItem -Path $LOCAL_REPO_PATH -Exclude $FILES_TO_IGNORE | ForEach-Object {
        $item = $_.Name
        if (-not (Should-Ignore $item)) {
            Write-Host "- $item"
            & scp -r "$LOCAL_REPO_PATH\$item" "$SSH_CONFIG:$REMOTE_PATH"
        }
    }
}

Set-Location $LOCAL_REPO_PATH

if ($DEPLOY_MODE -notin @('alllocal', 'allremote')) {
    Write-Host "Last 9 commits (most recent first):"
    git log -n 9 --pretty=format:"%h %s" | Format-Table -AutoSize

    Write-Host "`nEnter the number of the commit to deploy (1-9). Press Ctrl+C to cancel."
    $commitNumber = Read-Host
    $chosenHash = (git log -n 9 --pretty=format:"%h" | Select-Object -Index ($commitNumber - 1))

    $CHANGED_FILES = git diff-tree --no-commit-id --name-only -r $chosenHash --diff-filter=ACMRT
    $DELETED_FILES = git diff-tree --no-commit-id --name-only -r $chosenHash --diff-filter=D
}

Write-Host "Deploying to $ENVIRONMENT..."

switch ($DEPLOY_MODE) {
    'local' { Deploy-Local }
    'remote' { Deploy-Remote }
    'alllocal' { Deploy-All-Local }
    'allremote' { Deploy-All-Remote }
}

Write-Host "Deployment completed."
