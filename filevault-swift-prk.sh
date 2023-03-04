#!/bin/sh

# Credit to @dan-snelson for using his script as reference https://github.com/dan-snelson/dialog-scripts/blob/main/Display%20Message/Display-Message-via-Dialog.bash
# Credit to @bartreardon for https://github.com/bartreardon/swiftDialog
# Credit to @wylan_swets on the jamf forum for the key rotation script https://community.jamf.com/t5/jamf-pro/self-service-script-to-disable-filevault/m-p/180341/highlight/true#M169171
# Credit to @acodega for the swiftdialog check / install

# Script Version 0.1

####################################################################################################
#
# Variables
#
####################################################################################################

scriptLog="/var/tmp/logfilename.log"
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
logoLight=""
logoDark=""
fontRegular=""
fontBold=""
passPromptFr=""
passPromptEn=""
successPromptFr=""
successPromptEn=""
errorPromptFr=""
errorPromptEn=""



####################################################################################################
#
# Preferences check
#
####################################################################################################

# Check if device is using dark or light theme and change used logo
os_color_mode=$(if defaults read -g AppleInterfaceStyleSwitchesAutomatically > /dev/null && \
   		defaults read -g AppleInterfaceStyle -string | grep -q "^Dark"; then

    	echo "Dark"
		
	elif defaults read -g AppleInterfaceStyle -string | grep -q "^Dark"; then
		
    	echo "Dark"
		
	else
		
    	echo "Light"
		
	fi
)

if [ "$os_color_mode" = "Dark" ]; then
	
	icon_path=$logoDark
	
else
	
	icon_path=$logoLight
	
fi


# Check system language. Set message to use either Fr or En prompts
sysLanguage=(`defaults read NSGlobalDomain AppleLanguages`)
if [[ "${sysLanguage[2]/,/}" = *"fr"* ]]; then
	
	passPrompt=${passPromptFr}
	successPrompt=${successPromptFr}
	errorPrompt=${errorPromptFr}
	
else
	
	passPrompt=${passPromptEn}
	successPrompt=${successPromptEn}
	errorPrompt=${errorPromptEn}
	
fi

####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Script Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    echo -e "$( date +%Y-%m-%d\ %H:%M:%S )  ${1}" | tee -a "${scriptLog}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check for / install swiftDialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogCheck() {

    # Get the URL of the latest PKG From the Dialog GitHub repo
    dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    # Check for Dialog and install if not found
    if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then

        updateScriptLog "Dialog not found. Installing..."

        # Create temporary working directory
        workDirectory=$( /usr/bin/basename "$0" )
        tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )

        # Download the installer package
        /usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"

        # Verify the download
        teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')

        # Install the package if Team ID validates
        if [[ "$expectedDialogTeamID" == "$teamID" ]]; then

            /usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
            sleep 2
            updateScriptLog "swiftDialog version $(dialog --version) installed; proceeding..."

        else

            # Display a so-called "simple" dialog if Team ID fails to validate
            runAsUser osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "Display Message: Error" buttons {"Close"} with icon caution'
            quitScript "1"

        fi

        # Remove the temporary working directory when done
        /bin/rm -Rf "$tempDirectory"  

    else

        updateScriptLog "swiftDialog version $(dialog --version) found; proceeding..."

    fi

}

dialogCheck



####################################################################################################
#
# Prompt user for password and rotate FileVault Key
#
####################################################################################################

# Check if FileVault is already off - no need to run script if so
# Will update to turn on FileVault at some point
if fdesetup status | grep -q Off; then
	
	updateScriptLog "FileVault is Off."
	exit
	
fi


# Prompt user for password
passWord=$(/usr/local/bin/dialog --title FileVault --titlefont name=${fontBold} --message "${passPrompt}" --messagefont name=${fontRegular} --icon ${icon_path} --button1text "OK" --button2 --textfield " ",secure -s -o | grep " " | awk -F " : " '{print $NF}')

# end script if no password is entered or cancel is pressed
if [ -z "$passWord" ]; then
	
	updateScriptLog "User did not type anything"
	exit
	
fi


# Use fdesetup to rotate the personal recovery key
# Grab result in to vaultKey to check later.
vaultKey=$(/usr/bin/expect <<EOT
spawn fdesetup changerecovery -personal
expect ":"
sleep 1
send -- {$loggedInUser}
send -- "
"
expect ":"
sleep 1
send -- {$passWord}
send -- "
"
expect "New*"
puts $expect_out(0,string)
return $expect_out
EOT
)


# If the output has key = in it, then the key has been rotated
if [ `echo ${vaultKey} | grep -c "key =" ` -gt 0 ]; then
	
	/usr/local/bin/dialog --title FileVault --titlefont name=${fontBold} --message "${successPrompt}" --messagefont name=${fontRegular} --icon ${icon_path} --button1text "OK" -s -o

else
	
	# Most likely the password was wrong, but we can't be fully certain
	/usr/local/bin/dialog --title FileVault --titlefont name=${fontBold} --message "${errorPrompt}" --messagefont name=${fontRegular} --icon ${icon_path} --button1text "OK" -s -o

fi