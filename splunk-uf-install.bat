@ECHO OFF
REM This script installs the Splunk Universal Forwarder on Windows
REM It allows to set a custom admin PW that is not distributed in cleartext, but only as a hash
REM You can also configure a deployment server, a Root CA to validate it, and a pass4SymmKey for communication with it
REM For validation of clients sending to indexers, you can copy a certificate + private key to the forwarder
REM All configs are saved to seperate apps so they can be managed using the deployment server

REM This script has to be run with admin privileges
REM This script requires Splunk >= 7.1 - older versions might work with a non-hashed password in user-seed.conf

REM ##############################
REM Set all script parameters here
REM ##############################
REM The UF .msi file and the Root CA and forwarder certificate have to be properly formatted in the same directory as the script

SET MSIFILE=###FILENAME OF SPLUNK UF MSI###
REM Install dir, defaults to C:\Program Files\SplunkUniversalForwarder
SET INSTALL_DIR=C:\Program Files\SplunkUniversalForwarder

REM Try to uninstall existing Universal Forwarder if set to true (case sensitive!)
SET UNINSTALL_EXISTING_UF=true

REM Username for admin user
SET USERNAME=admin
REM Hashed password for admin user. Can be copied from etc/passwd on an existing Splunk instance. The splunk.secret file does NOT matter for this. Requires Splunk >= 7.1
SET HASHED_PASSWORD=###HASHED ADMIN PASSWORD###

REM Name for app containing deployment client config. App with exact same name can be distributed via the DS to overwrite this config later
SET DS_APPNAME=org_zone_dc_deploymentclient
REM FQDN/hostname/IP and port for deploymentserver, e.g. 10.0.0.1:8089
SET DEPLOYMENTSERVER=###DEPLOYMENT SERVER FQDN###:8089

REM All TLS config (certificates, pass4symmkey, copying Root CA and cert file...) will only be applied if this is set to true (case sensitive!)
SET CREATE_TLS_SETTINGS=true
REM Name for app containing TLS/pass4symmkey config. App with exact same name can be distributed via the DS to overwrite this config later
SET TLS_APPNAME=org_zone_dc-windows_tls-base
REM Common name in the certificate used by the deployment server
SET DEPLOYMENTSERVER_CERT_COMMON_NAME=###CN OF DEPLOYMENT SERVER CERTIFICATE###
REM pass4symmkey used by DS and DC to verify each other. Can be set in server.conf -> [deployment] on DS
SET DEPLOYMENTSERVER_PASS4SYMMKEY=###ENCRYPTED PASS4SYMMKEY FOR DEPLOYMENT SERVER AUTHORIZATION###
REM Folder to create in $SPLUNK_HOME\etc\auth to deploy certificates and key in
SET CERT_FOLDER=###CERT FOLDER NAME###
REM Filename for Root CA file to be copied. Has to be in the same folder as this script. Must contain one or more PEM certificates
SET ROOT_CA_CERT_LOCAL_FILE=splunk_root.pem
REM Filename for forwarder certificate file to be copied. Has to be in the same folder as this script. Must contain forwarder certificate, forwarder private key, and possible intermediate certificates, all in PEM format
SET SERVER_CERT_KEY_CHAIN_LOCAL_FILE=splunk_cert_key_chain.pem

REM Only deploy custom splunk.secret file if set to true (case sensitive!)
SET CREATE_SPLUNK_SECRET=true
REM Deploy custom splunk.secret file to allow shared encrypted passwords etc.
SET SPLUNK_SECRET=###SPLUNK SECRET###


REM This detects if the script is being run with admin privileges
REM If it isn't, it will print an error message and quit

cd /D "%~dp0"

NET SESSION >nul 2>&1

IF %ERRORLEVEL% EQU 0 (
  ECHO Administrator privileges detected! 
) ELSE (
  ECHO ######## ########  ########   #######  ########  
  ECHO ##       ##     ## ##     ## ##     ## ##     ## 
  ECHO ##       ##     ## ##     ## ##     ## ##     ## 
  ECHO ######   ########  ########  ##     ## ########  
  ECHO ##       ##   ##   ##   ##   ##     ## ##   ##   
  ECHO ##       ##    ##  ##    ##  ##     ## ##    ##  
  ECHO ######## ##     ## ##     ##  #######  ##     ## 
  ECHO.
  ECHO.
  ECHO ####### ERROR: ADMINISTRATOR PRIVILEGES REQUIRED #########
  ECHO This script must be run as administrator to work properly!  
  ECHO Exiting now.
  ECHO ##########################################################
  ECHO.
  PAUSE
  EXIT /B %ERRORLEVEL%
)

IF EXIST %MSIFILE% (
  ECHO Splunk Universal Forwarder MSI file exists, starting installation.
) ELSE (
  ECHO Splunk Universal Forwarder MSI file does not exist!
  ECHO Exiting now, make sure %MSIFILE% exists or change variable MSIFILE in script.
  PAUSE
  EXIT /B %ERRORLEVEL%
)

IF "%UNINSTALL_EXISTING_UF%" == "true" (
  REM Trying to stop and uninstall existing Universal Forwarder

  ECHO Trying to stop an existing Universal Forwarder service
  net stop "SplunkForwarder Service"

  IF %ERRORLEVEL% EQU 0 (
    ECHO Stopped Splunk Universal Forwarder service.
  ) ELSE (
    ECHO Failed to stop Splunk Universal Forwarder service.
  )

  ECHO Trying to uninstall an existing Universal Forwarder service
  wmic product where name="UniversalForwarder" call uninstall
)

REM For parameter explanation, see http://docs.splunk.com/Documentation/Forwarder/latest/Forwarder/InstallaWindowsuniversalforwarderfromthecommandline

ECHO Installing Splunk Universal Forwarder
msiexec.exe /i %MSIFILE% AGREETOLICENSE="Yes" INSTALLDIR="%INSTALL_DIR%" LAUNCHSPLUNK=0 SERVICESTARTTYPE=auto INSTALL_SHORTCUT=0 /quiet /L*v logfile.txt

IF %ERRORLEVEL% EQU 0 (
  ECHO Splunk Universal Forwarder installation successful.
) ELSE (
  ECHO Splunk Universal Forwarder installation FAILED.
  ECHO Exiting now, check logfile.txt.
  PAUSE
  EXIT /B %ERRORLEVEL%
)

REM Creates user-seed.conf which Splunk uses on first startup to set the password for the admin user
REM Password hash is defined at top of script
REM Splunk deletes this file after the first start

( 
  ECHO [user_info]
  ECHO USERNAME = %USERNAME%
  ECHO HASHED_PASSWORD = %HASHED_PASSWORD%
) > "%INSTALL_DIR%\etc\system\local\user-seed.conf"

IF %ERRORLEVEL% EQU 0 (
  ECHO Created file %INSTALL_DIR%\etc\system\local\user-seed.conf successfully
) ELSE (
  ECHO FAILED to create %INSTALL_DIR%\etc\system\local\user-seed.conf
  ECHO Exiting now, check permissions.
  PAUSE
  EXIT /B %ERRORLEVEL%
)

REM Creates directory for the deploymentclient.conf
REM Name is defined at top of script - the same name has be used on the Deployment Server to replace/manage these app and it's settings

mkdir "%INSTALL_DIR%\etc\apps\%DS_APPNAME%\default"

IF %ERRORLEVEL% EQU 0 (
  ECHO Created directory %INSTALL_DIR%\etc\apps\%DS_APPNAME%\default successfully
) ELSE (
  ECHO FAILED to create directory %INSTALL_DIR%\etc\apps\%DS_APPNAME%\default
  ECHO Exiting now, check permissions.
  PAUSE
  EXIT /B %ERRORLEVEL%
)

REM Creates deploymentclient.conf and fills in the IP/hostname and port of the deployment server

(
  ECHO [target-broker:deploymentServer]
  ECHO targetUri = %DEPLOYMENTSERVER%
) > "%INSTALL_DIR%\etc\apps\%DS_APPNAME%\default\deploymentclient.conf"

IF %ERRORLEVEL% EQU 0 (
  ECHO Created file %INSTALL_DIR%\etc\apps\%DS_APPNAME%\default\deploymentclient.conf successfully
) ELSE (
  ECHO FAILED to create %INSTALL_DIR%\etc\apps\%DS_APPNAME%\default\deploymentclient.conf
  ECHO Exiting now, check permissions.
  PAUSE
  EXIT /B %ERRORLEVEL%
)

REM Creates server.conf and fills in the pass4SymmKey used to authenticate against the deployment server

(
  ECHO [deployment]
  ECHO pass4SymmKey = %DEPLOYMENTSERVER_PASS4SYMMKEY%
) > "%INSTALL_DIR%\etc\apps\%DS_APPNAME%\default\server.conf"

IF %ERRORLEVEL% EQU 0 (
  ECHO Created file %INSTALL_DIR%\etc\apps\%DS_APPNAME%\default\server.conf successfully
) ELSE (
  ECHO FAILED to create %INSTALL_DIR%\etc\apps\%DS_APPNAME%\default\server.conf
  ECHO Exiting now, check permissions.
  PAUSE
  EXIT /B %ERRORLEVEL%
)

REM Only do the next steps if CREATE_TLS_SETTINGS is set to true

IF "%CREATE_TLS_SETTINGS%" == "true" (

  REM Creates directory for the TLS config
  REM Name is defined at top of script - the same name has be used on the Deployment Server to replace/manage this app and its settings

  mkdir "%INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default"

  IF %ERRORLEVEL% EQU 0 (
    ECHO Created directory %INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default successfully
  ) ELSE (
    ECHO FAILED to create directory %INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default
    ECHO Exiting now, check permissions.
    PAUSE
    EXIT /B %ERRORLEVEL%
  )

  REM Creates server.conf and fills in the certificate paths, DS Certificate CN and DS Pass4SymmKey

  (
    ECHO [sslConfig]
    ECHO sslRootCAPath = $SPLUNK_HOME\etc\auth\%CERT_FOLDER%\%ROOT_CA_CERT_LOCAL_FILE%
    ECHO serverCert = $SPLUNK_HOME\etc\auth\%CERT_FOLDER%\%SERVER_CERT_KEY_CHAIN_LOCAL_FILE%
    ECHO sslRootCAPathHonoredOnWindows = true
    ECHO sslVerifyServerCert = true
    ECHO sslCommonNameToCheck = %DEPLOYMENTSERVER_CERT_COMMON_NAME%
  ) > "%INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default\server.conf"

  IF %ERRORLEVEL% EQU 0 (
    ECHO Created file %INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default\server.conf successfully
  ) ELSE (
    ECHO FAILED to create %INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default\server.conf
    ECHO Exiting now, check permissions.
    PAUSE
    EXIT /B %ERRORLEVEL%
  )

  REM Creates folder to put certificate files and private key into

  mkdir "%INSTALL_DIR%\etc\auth\%CERT_FOLDER%"

  IF %ERRORLEVEL% EQU 0 (
    ECHO Created directory %INSTALL_DIR%\etc\auth\%CERT_FOLDER% successfully
  ) ELSE (
    ECHO FAILED to create directory %INSTALL_DIR%\etc\auth\%CERT_FOLDER%
    ECHO Exiting now, check permissions.
    PAUSE
    EXIT /B %ERRORLEVEL%
  )

  REM This copies the Root CA Cert(s) file and the Server Cert+Key+Chain file to the right location

  copy %ROOT_CA_CERT_LOCAL_FILE% "%INSTALL_DIR%\etc\auth\%CERT_FOLDER%\%ROOT_CA_CERT_LOCAL_FILE%" && copy %SERVER_CERT_KEY_CHAIN_LOCAL_FILE% "%INSTALL_DIR%\etc\auth\%CERT_FOLDER%\%SERVER_CERT_KEY_CHAIN_LOCAL_FILE%"

  IF %ERRORLEVEL% EQU 0 (
    ECHO Copied %ROOT_CA_CERT_LOCAL_FILE% and %SERVER_CERT_KEY_CHAIN_LOCAL_FILE% to %INSTALL_DIR%\etc\auth\%CERT_FOLDER% successfully
  ) ELSE (
    ECHO FAILED to copy certificale files to directory %INSTALL_DIR%\etc\auth\%CERT_FOLDER%
    ECHO Exiting now, check permissions.
    PAUSE
    EXIT /B %ERRORLEVEL%
  )

)

REM Only do the next steps if CREATE_SPLUNK_SECRET is set to true

IF "%CREATE_SPLUNK_SECRET%" == "true" (

  REM The msiexec encrypts sslPassword to local\server.conf with a random splunk.secret before the first start.
  REM When we replace the splunk.secret content with ours, Splunk will error on start because it can't decrypt the sslPassword
  REM Therefore, we are going to filter this line out.

  ECHO Removing useless encrypted sslPassword in etc\system\local\server.conf
  FINDSTR /V sslPassword "%INSTALL_DIR%\etc\system\local\server.conf" > "%INSTALL_DIR%\etc\system\local\server.conf.tmp" && move /Y "%INSTALL_DIR%\etc\system\local\server.conf.tmp" "%INSTALL_DIR%\etc\system\local\server.conf"

  (
    ECHO %SPLUNK_SECRET%
  ) > "%INSTALL_DIR%\etc\auth\splunk.secret"

  IF %ERRORLEVEL% EQU 0 (
    ECHO Created file %INSTALL_DIR%\etc\auth\splunk.secret successfully
  ) ELSE (
    ECHO FAILED to create %INSTALL_DIR%\etc\auth\splunk.secret
    ECHO Exiting now, check permissions.
    PAUSE
    EXIT /B %ERRORLEVEL%
  )

)

REM This starts the Splunk UF service

net start "SplunkForwarder Service"

IF %ERRORLEVEL% EQU 0 (
  ECHO Successfully started Splunk Universal Forwarder service.
) ELSE (
  ECHO FAILED to start Splunk Universal Forwarder service
  ECHO Exiting now, please set Windows on fire.
  PAUSE
  EXIT /B %ERRORLEVEL%
)