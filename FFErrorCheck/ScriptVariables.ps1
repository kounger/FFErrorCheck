###VARIABLES###

#Edit the variables below and run FFErrorCheck.ps1

#Edit this variable to set a directory as the the current working location:
#(E.g $working_location  = "C:\Users\User\MyVideos")
#This is optional but makes it possible to work without full file paths.
#($PSScriptRoot is the directory where this powershell script is located.)
$working_location = $PSScriptRoot

#Choose a test procedure:
# "ffprobe"        Fast media file check with FFprobe. Only reads metadata to find errors.
# "ffmpeg"         Thoroughly checks media files with FFmpeg. Reads through the complete media file to find errors.
$test_procedure = "ffmpeg"

#Choose what kind of errors should be logged:
# "warning"        Log all warnings and errors. Any message related to possibly incorrect or unexpected events will be logged.
# "error"          Log all errors, including ones which can be recovered from.
# "fatal"          Only log fatal errors. These are errors after which the process absolutely cannot continue.
# "panic"          Only log fatal errors which could lead the process to crash. (Not used for anything as of 06/04/23)
$log_level = "error"

#Choose a destination for all log files:
#A log file will be created which lists all damaged media files.
#Additional log files will be created for each damaged media file.
#($PSScriptRoot is the directory where this powershell script is located.)
$log_folder = "$PSScriptRoot\Error_Logs"


#Edit the table below:
# Media_Files:   Path to the file or the folder with media files that should be checked.
#                Each table entry is placed between brackets and divided by a comma: (entry),
#                A single file entry only needs the path to the media file:
#                ("File_Path"),
#                A folder entry needs the path to the directory, the #Recursive setting and the #File_Types entry:
#                ("Directory_Path", Recursive, "File_Types"),
# Recursive:     Enter $false to only check the files in the specified folder.
#                Enter $true to also check all media files in all subdirectories of the folder.
# File_Types:    Limit the media file check to a number of file types. (E.g ".mp4, .avi, .webm")
#                If empty ("") all files supported by FFmpeg will be checked.


#Example Table 1:

                 #Media_Files                   #Recursive     #File_Types
#$files_table = ("C:\Users\User\MyVideos",      $true,         "mp4, mp3, avi, mov, webm")


#Example Table 2:

                 #Media_Files                   #Recursive     #File_Types
#$files_table = ("Video_Folder",                $true,         "mp4, webm"),
#               ("C:\User\Videos\Clips",        $false,        ""         ),
#               ("D:\Media_Files\Foo.mp4"                                 ),
#               ("D:\Media_Files\Bar.webm"                                ),
#               ("Baz.avi"                                                )


#Example Table 3:

                 #Media_Files
#$files_table = ("D:\Media_Files\FooBar.mp4"),
#               ("D:\Media_Files\Baz.webm"  ),
#               ("Baz.avi"                  )


$files_table = ("")