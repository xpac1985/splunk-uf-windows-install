@ECHO OFF
REM This script installs the Splunk Universal Forwarder on Windows
REM It allows to set a custom admin PW that is not distributed in cleartext, but only as a hash
REM You can also configure a deployment server, a Root CA to validate it, and a pass4SymmKey for communication with it
REM For validation of clients sending to indexers, you can copy a certificate + private key to the forwarder
REM All configs are saved to seperate apps so they can be managed using the deployment server

REM This script has to be run with admin privileges
REM This script requires Splunk >= 7.1 - older versions might work with a non-hashed password in user-seed.conf


REM Set all script parameters here
REM The UF .msi file and the Root CA and forwarder certificate have to be properly formatted in the same directory as the script

SET MSIFILE=splunkforwarder-7.1.6-8f009a3f5353-x64-release.msi
SET INSTALL_DIR=C:\Program Files\SplunkUniversalForwarder

REM Username for admin user
SET USERNAME=admin
REM Hashed password for admin user. Can be copied from etc/passwd on an existing Splunk instance. The splunk.secret file does NOT matter for this
SET HASHED_PASSWORD=$6$QY84KTvRuuPNLx/i$Sf74KiBz/bPFfR49ONg2qOfT9GbYgsFm8dwmScuOqxqFs4Rvrhpx0eBQoGqExmW/XSycu0dVC3y6gYkRg0PjR1

REM Name for app containing deployment client config. App with exact same name can be distributed via the DS to overwrite this config later
SET DS_APPNAME=org_all_dc_deployment-client
REM IP and port for deploymentserver, e.g. 10.0.0.1:8089
SET DEPLOYMENTSERVER=10.0.0.1:8089

REM All TLS config (certificates, pass4symmkey, copying Root CA and cert file...) will only be applied if this is set to true (case sensitive!)
SET CREATE_TLS_SETTINGS=true
REM Name for app containing TLS/pass4symmkey config. App with exact same name can be distributed via the DS to overwrite this config later
SET TLS_APPNAME=org_all_dc_server-conf-for-tls
REM Common name in the certificate used by the deployment server
SET DEPLOYMENTSERVER_CERT_COMMON_NAME=mydeploymentserver
REM pass4symmkey used by DS and DC to verify each other. Can be set in server.conf -> [deployment] on DS
SET DEPLOYMENTSERVER_PASS4SYMMKEY=mypass4symmkey
REM Filename for Root CA file to be copied. Has to be in the same folder as this script. Must contain one or more PEM certificates
SET ROOT_CA_CERT_LOCAL_FILE=splunk_root.pem
REM Filename for forwarder certificate file to be copied. Has to be in the same folder as this script. Must contain forwarder certificate, forwarder private key, and possible intermediate certificates, all in PEM format
SET SERVER_CERT_KEY_CHAIN_LOCAL_FILE=splunk_cert_key_chain.pem

REM Only deploy custom splunk.secret file if set to true (case sensitive!)
SET CREATE_SPLUNK_SECRET=true
REM Deploy custom splunk.secret file to allow shared encrypted passwords etc.
SET SPLUNK_SECRET=zJOfhWlCfpJ1exsfVyBsAdv2LUbz95RcI91xRJ/mjWfsNkO2LY.M6d4O.y4Mny.FjdQ6ud.sL1jZ7Gv9KlSFuugAmG89REFBECsT6n.o8VtN2HSxgs9/Ef1e/MUff1BpdFTQ5OmV0UzVRh/fm5u8WKWiabcAnioKfnyoo.yCqexZdY4GmMOiUbtT.XA78RTZxpTthRgzn/v3QsRI.y7zYYtcqwxor7kjyRn9oenJUFGF2vhOlurdB25320hv5x


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
  EXIT /B 1
)

IF EXIST %MSIFILE% (
  ECHO Splunk Universal Forwarder MSI file exists, starting installation.
) ELSE (
  ECHO Splunk Universal Forwarder MSI file does not exist!
  ECHO Exiting now, make sure %MSIFILE% exists or change variable MSIFILE in script.
  PAUSE
  REM EXIT /B 1
)

REM For parameter explanation, see http://docs.splunk.com/Documentation/Forwarder/latest/Forwarder/InstallaWindowsuniversalforwarderfromthecommandline

msiexec.exe /i %MSIFILE% AGREETOLICENSE="Yes" INSTALLDIR="%INSTALL_DIR%" LAUNCHSPLUNK=0 SERVICESTARTTYPE=auto INSTALL_SHORTCUT=0 /quiet /L*v logfile.txt

IF %ERRORLEVEL% EQU 0 (
  ECHO Splunk Universal Forwarder installation successful.
) ELSE (
  ECHO Splunk Universal Forwarder installation FAILED.
  ECHO Exiting now, check logfile.txt.
  PAUSE
  EXIT /B 1
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
  ECHO FAILED to create  %INSTALL_DIR%\etc\system\local\user-seed.conf
  ECHO Exiting now, check permissions.
  PAUSE
  EXIT /B 1
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
  EXIT /B 1
)

REM Creates deploymentclient.conf and fills in the IP/hostname and port of the deployment server

(
  ECHO [target-broker:deploymentServer]
  ECHO targetUri = %DEPLOYMENTSERVER%
) > "%INSTALL_DIR%\etc\apps\%DS_APPNAME%\default\deploymentclient.conf"

IF %ERRORLEVEL% EQU 0 (
  ECHO Created file %INSTALL_DIR%\etc\apps\%DS_APPNAME%\default\deploymentclient.conf successfully
) ELSE (
  ECHO FAILED to create directory %INSTALL_DIR%\etc\apps\%DS_APPNAME%\default\deploymentclient.conf
  ECHO Exiting now, check permissions.
  PAUSE
  EXIT /B 1
)

REM Creates directory for the TLS config
REM Name is defined at top of script - the same name has be used on the Deployment Server to replace/manage this app and its settings

mkdir "%INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default"

IF %ERRORLEVEL% EQU 0 (
  ECHO Created directory %INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default successfully
) ELSE (
  ECHO FAILED to create directory %INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default
  ECHO Exiting now, check permissions.
  PAUSE
  EXIT /B 1
)

REM Only do the next steps if CREATE_TLS_SETTINGS is set to true

IF "%CREATE_TLS_SETTINGS%" == "true" (

  REM Creates server.conf and fills in the certificate paths, DS Certificate CN and DS Pass4SymmKey

  (
    ECHO [sslConfig]
    ECHO sslRootCAPath = $SPLUNK_HOME\etc\auth\%ROOT_CA_CERT_LOCAL_FILE%
    ECHO serverCert = $SPLUNK_HOME\etc\auth\%SERVER_CERT_KEY_CHAIN_LOCAL_FILE%
    ECHO sslRootCAPathHonoredOnWindows = true
    ECHO sslVerifyServerCert = true
    ECHO sslCommonNameToCheck = %DEPLOYMENTSERVER_CERT_COMMON_NAME%
    ECHO 
    ECHO [deployment]
    ECHO pass4SymmKey = %DEPLOYMENTSERVER_PASS4SYMMKEY%
  ) > "%INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default\server.conf"

  IF %ERRORLEVEL% EQU 0 (
    ECHO Created file %INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default\server.conf successfully
  ) ELSE (
    ECHO FAILED to create directory %INSTALL_DIR%\etc\apps\%TLS_APPNAME%\default\server.conf
    ECHO Exiting now, check permissions.
    PAUSE
    EXIT /B 1
  )

  REM This copies the Root CA Cert(s) file and the Server Cert+Key+Chain file to the right location

  copy %ROOT_CA_CERT_LOCAL_FILE% "%INSTALL_DIR%\etc\auth\%ROOT_CA_CERT_LOCAL_FILE%" && copy %SERVER_CERT_KEY_CHAIN_LOCAL_FILE% "%INSTALL_DIR%\etc\auth\%SERVER_CERT_KEY_CHAIN_LOCAL_FILE%"

  IF %ERRORLEVEL% EQU 0 (
    ECHO Copied %ROOT_CA_CERT_LOCAL_FILE% and %SERVER_CERT_KEY_CHAIN_LOCAL_FILE% to %INSTALL_DIR%\etc\auth successfully
  ) ELSE (
    ECHO FAILED to copy certificale files to directory %INSTALL_DIR%\etc\auth
    ECHO Exiting now, check permissions.
    PAUSE
    EXIT /B 1
  )

)

REM Only do the next steps if CREATE_SPLUNK_SECRET is set to true

IF "%CREATE_SPLUNK_SECRET%" == "true" (

  (
    ECHO %SPLUNK_SECRET%
  ) > "%INSTALL_DIR%\etc\auth\splunk.secret"

  IF %ERRORLEVEL% EQU 0 (
    ECHO Created file %INSTALL_DIR%\etc\auth\splunk.secret successfully
  ) ELSE (
    ECHO FAILED to create directory %INSTALL_DIR%\etc\auth\splunk.secret
    ECHO Exiting now, check permissions.
    PAUSE
    EXIT /B 1
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
  EXIT /B 1
)
