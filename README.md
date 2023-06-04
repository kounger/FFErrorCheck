# FFErrorCheck
This script uses FFmpeg to search for errors in media files.
#
The script will first collect all supported media files from a given list of files and folders. It then uses FFmpeg or FFprope to check these media files for errors. 
A log file will be created that lists all media files that were found to contain an error.
## Instructions
Edit the [ScriptVariables.ps1](FFErrorCheck/ScriptVariables.ps1) file and execute [FFErrorCheck.ps1](FFErrorCheck/FFErrorCheck.ps1).
#
FFmpeg has to be installed for this script to function.
