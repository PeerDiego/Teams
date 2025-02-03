#!/bin/bash

# This script is in currently untested. Please test in your environment before deploying.

# This script adds the URLs required for eCDN to the WebRtcLocalIpsAllowedUrls policy in Microsoft Edge for Mac.

# Define the URLs to be added
URL1="*.ecdn.teams.microsoft.com"
URL2="https://teams.microsoft.com"

# Path to the policy file
POLICY_FILE="/Library/Preferences/com.microsoft.edge.plist"

# Add the URLs to the WebRtcLocalIpsAllowedUrls policy
/usr/libexec/PlistBuddy -c "Add :WebRtcLocalIpsAllowedUrls array" $POLICY_FILE
/usr/libexec/PlistBuddy -c "Add :WebRtcLocalIpsAllowedUrls: string $URL1" $POLICY_FILE
/usr/libexec/PlistBuddy -c "Add :WebRtcLocalIpsAllowedUrls: string $URL2" $POLICY_FILE

echo "URLs added to WebRtcLocalIpsAllowedUrls policy successfully."