@echo off

setlocal enabledelayedexpansion

set DEPLOY_MODE=%1
set ENVIRONMENT=%2

REM Check if DEPLOY_MODE is either 'local', 'remote', 'alllocal', or 'allremote'
if "%DEPLOY_MODE%" neq "local" if "%DEPLOY_MODE%" neq "remote" if "%DEPLOY_MODE%" neq "alllocal" if "%DEPLOY_MODE%" neq "allremote" (
    echo Error: DEPLOY_MODE must be either 'local', 'remote', 'alllocal', or 'allremote'.
    exit /b 1
)

if "%ENVIRONMENT%"=="" (
    echo Error: no config file specified.
    exit /b 1
)

REM Check if the environment config file exists
if not exist "%USERPROFILE%\bin\.config\%ENVIRONMENT%" (
    echo Error: %ENVIRONMENT% config file not found.
    exit /b 1
)

REM Load configuration variables
call "%USERPROFILE%\bin\.config\%ENVIRONMENT%"

REM Function to check if a file/folder is in the ignore list
set should_ignore=^
(
    setlocal enabledelayedexpansion
    for %%i in (%FILES_TO_IGNORE%) do (
        if "%ITEM%"=="%%i" if "%ITEM:~0,%%i%"=="%%i" (
            endlocal
            exit /b 0
        )
    )
    endlocal
    exit /b 1
)

REM Function to deploy to a local folder
:deploy_local
echo Uploads:
for %%F in (%CHANGED_FILES%) do (
    echo - %%F
    copy "%LOCAL_REPO_PATH%\%%F" "%LOCAL_PATH%\%%F"
)

echo Deletions:
for %%F in (%DELETED_FILES%) do (
    echo - %%F
    del "%LOCAL_PATH%\%%F"
)
goto :EOF

REM Function to deploy to a remote server
:deploy_remote
echo Uploads:
for %%F in (%CHANGED_FILES%) do (
    echo - %%F
    pscp -pw %SSH_PASSWORD% "%LOCAL_REPO_PATH%\%%F" %SSH_USER%@%SSH_HOST%:%REMOTE_PATH%/%%F
    plink -pw %SSH_PASSWORD% %SSH_USER%@%SSH_HOST% "chmod 0644 %REMOTE_PATH%/%%F"
)

echo Deletions:
for %%F in (%DELETED_FILES%) do (
    echo - %%F
    plink -pw %SSH_PASSWORD% %SSH_USER%@%SSH_HOST% "rm -f %REMOTE_PATH%/%%F"
)
goto :EOF

REM Function to deploy all files in a repository to a local folder
:deploy_all_local
for /d %%D in (%LOCAL_REPO_PATH%\*) do (
    set ITEM=%%~nxD
    call :should_ignore
    if errorlevel 1 (
        echo - %%D
        xcopy /E /I "%LOCAL_REPO_PATH%\%%D" "%LOCAL_PATH%\"
    )
)
goto :EOF

REM Function to deploy all files in a repository to a remote server
:deploy_all_remote
for /d %%D in (%LOCAL_REPO_PATH%\*) do (
    set ITEM=%%~nxD
    call :should_ignore
    if errorlevel 1 (
        echo - %%D
        pscp -r -pw %SSH_PASSWORD% "%LOCAL_REPO_PATH%\%%D" %SSH_USER%@%SSH_HOST%:%REMOTE_PATH%
    )
)
goto :EOF

cd %LOCAL_REPO_PATH%

if not "%DEPLOY_MODE%"=="alllocal" if not "%DEPLOY_MODE%"=="allremote" (
    REM Show the last 9 commits
    echo Last 9 commits (most recent first):
    git log -n 9 --pretty=format:"%%h %%s" | nl

    REM Ask the user to choose a commit
    echo.
    echo Enter the number of the commit to deploy (1-9). Press Ctrl+C to cancel.
    set /p COMMIT_NUMBER=

    REM Get the commit hash for the chosen commit
    for /f "tokens=%COMMIT_NUMBER%" %%i in ('git log -n 9 --pretty=format:"%%h"') do set CHOSEN_HASH=%%i

    REM Get the list of changed files in the latest commit (excluding deletions)
    for /f %%i in ('git diff-tree --no-commit-id --name-only -r %CHOSEN_HASH% --diff-filter=ACMRT') do set CHANGED_FILES=!CHANGED_FILES! %%i

    REM Get the list of deleted files in the latest commit
    for /f %%i in ('git diff-tree --no-commit-id --name-only -r %CHOSEN_HASH% --diff-filter=D') do set DELETED_FILES=!DELETED_FILES! %%i
)

echo Deploying to %ENVIRONMENT%...

if "%DEPLOY_MODE%"=="local" (
    call :deploy_local
) else if "%DEPLOY_MODE%"=="remote" (
    call :deploy_remote
) else if "%DEPLOY_MODE%"=="alllocal" (
    call :deploy_all_local
) else (
    call :deploy_all_remote
)

echo Deployment completed.
