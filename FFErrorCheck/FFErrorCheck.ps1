###IMPORT VARIABLES###


Import-Module $PSScriptRoot\ScriptVariables.ps1 -Force


###VERIFY VARIABLES###


#Set the current working location:
if (Test-Path -Path $working_location -PathType Container)
{
    #Change the current location for this PowerShell runspace:
    Set-Location $working_location

    #Change the current working directory for .NET:
    [System.IO.Directory]::SetCurrentDirectory($working_location)
} 
else 
{
    throw [IO.FileNotFoundException] ("Specified working location is not a directory or does not exist:" `
                                     +"`n" + $working_location) 
}


#Check if FFmpeg is installed on this system:
try
{
    ffmpeg -version | Out-Null
}
catch [System.Management.Automation.CommandNotFoundException]
{
    throw [System.Management.Automation.CommandNotFoundException] `
          ("FFmpeg is not installed on this system!" `
          +"`nInstall FFmpeg for this script to function!")
}


#Show the user that the $files_table variable is necessary:
if ([string]::IsNullOrEmpty($files_table))
{
    throw [ArgumentException] ("`$files_table doesn't exist or has no entry.")
}


#Parse the simple $files_table format into a proper array of arrays that can be worked with:
$single_file_table    = $files_table -isnot [array]
$single_folder_table  = ($files_table.Count -eq 3) -and ($files_table[1] -is [bool]) 
$multi_elements_table = (-not $single_file_table)  -and (-not $single_folder_table)

#Nest single file entries into an array of arrays:
if($single_file_table)
{
    $files_table = ,(,$files_table)
}

#Avoid single folder entries to be treated like an array with three elements:
if($single_folder_table)
{
    $files_table = ,($files_table)
}

#Avoid file entries to be treated like strings instead of array elements:
if($multi_elements_table)
{
    for ($i = 0; $i -lt $files_table.Length; $i++)
    {
        $files_table[$i] = @($files_table[$i])
    }
}


#Verify the test procedure option:
if (-not($test_procedure -eq "ffprobe" -or $test_procedure -eq "ffmpeg"))
{
    throw [ArgumentException] ("`"ffprobe`" and `"ffmpeg`" are the only allowed options for `$test_procedure:" `
                              +"`n" + $test_procedure)
}


#Format the test procedure string into "FFmpeg" or "FFprobe":
$test_procedure = $test_procedure.Substring(0,2).ToUpper() + $test_procedure.Substring(2).ToLower()


#Verify the log level option:
$options = @("warning", "error", "fatal", "panic")

if (-not $options.Contains($log_level))
{
    throw [ArgumentException] ("`"warning`", `"error`", `"fatal`" and `"panic`" are the only allowed options for `$log_level:" `
                              +"`n" + $log_level)
}


#Check if the parent directory of the log folder exists:
$log_folder_parent = Split-Path $log_folder -Parent

if (-not(Test-Path -Path $log_folder_parent -PathType Container)) 
{
    throw [IO.FileNotFoundException] ("The parent directory of the specified `$log_folder path does not exist:" `
                                         +"`n" + $log_folder_parent) 
}


#Create the log folder if it doesn't exist already:
if (-not(Test-Path -Path $log_folder -PathType Container)) 
{
    New-Item -ItemType Directory -Force -Path $log_folder
}


###INITIALIZE###


if ($test_procedure -eq "ffprobe")
{
    Write-Output( "`n" + "#############################" `
                + "`n" + "MEDIA FILE CHECK WITH FFPROBE" `
                + "`n" + "#############################")

}
else
{
    Write-Output( "`n" + "############################" `
                + "`n" + "MEDIA FILE CHECK WITH FFMPEG" `
                + "`n" + "############################")
}


Write-Output("`n")
Write-Output("Entry Table:")
Write-Output("------------")

$line_num = 1
$files_table | ForEach-Object {New-Object PSObject -Property @{‘#’ = $line_num; ’Entry’ = $_}; $line_num++} `
             | Format-Table


###EXTRACT ALL FFMPEG FORMATS###


#This function extracts all muxer or demuxer formats that are supported by ffmpeg:
function ExtractFormats{
    param (
        [Parameter(Mandatory)]
        [ValidateSet("muxer", "demuxer")]
        [string]$de_muxer,

        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$start_percentage,

        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$target_percentage
    )    
    
    $all_de_muxer_formats = @()
    
    $de_muxers_arg = '-' + $de_muxer + 's'
    $de_muxer_list = ffmpeg $de_muxers_arg 2>$null | Select -Skip 4 | ForEach {($_.Trim() -replace '\s+', ' ' -split ‘\s’)[1]} 

    for ($i=0; $i -lt $de_muxer_list.Length; $i++)
    {        
        $de_muxer_elem    = $de_muxer_list[$i]
        $de_muxer_arg     = $de_muxer + '=' + $de_muxer_elem
        $de_muxer_formats = ffmpeg -h $de_muxer_arg 2>$null | Select-String -Pattern 'Common extensions:' | Select -ExpandProperty Line 
    
        if (-not [string]::IsNullOrEmpty($de_muxer_formats))
        {
            $de_muxer_formats      = $de_muxer_formats.Split(':')[1]
            $de_muxer_formats      = $de_muxer_formats.Split(',')
            $de_muxer_formats      = $de_muxer_formats | ForEach {'.' + ($_.Trim() -replace '\.','')}
            $all_de_muxer_formats += $de_muxer_formats
        }
        
        Write-Progress -Activity "Update the list of media file formats:" `
                       -Status ("Extract formats from $de_muxer" + ":" + " $de_muxer_elem") `
                       -PercentComplete ($start_percentage + ($i / $de_muxer_list.Count * ($target_percentage - $start_percentage)))
    }
    
    return $all_de_muxer_formats
}


#Get the current version of the installed FFmpeg build:
$current_ffmpeg_version = ffmpeg -version | Select-String -Pattern '(?<=\bversion\s)(\S+)' -AllMatches | % { $_.Matches } | % { $_.Value }


#Read the version of the FFmpeg build that has been used to extract all formats: 
if ([System.IO.File]::Exists("$PSScriptRoot\ffmpeg_version.json"))
{
    $saved_ffmpeg_version = Get-Content "$PSScriptRoot\ffmpeg_version.json" | ConvertFrom-Json
}


#Update all formats that are supported by FFmpeg and save them into a JSON file:
if ($current_ffmpeg_version -ne $saved_ffmpeg_version)
{
    Write-Output("Update supported FFmpeg formats:")
    Write-Output("--------------------------------") 
        
    Write-Progress -Activity "Update the list of media file formats:" -PercentComplete 0
    
    #Collect all muxer formats:    
    $all_muxer_formats   = ExtractFormats -de_muxer muxer   -start_percentage 0  -target_percentage 50

    #Collect all demuxer formats:
    $all_demuxer_formats = ExtractFormats -de_muxer demuxer -start_percentage 50 -target_percentage 100

    Write-Progress -Activity "Update the list of media file formats:" -Status "Collection completed" -PercentComplete 100 -Completed

    #Save all collected media file formats into a JSON file:
    $ffmpeg_formats = $all_muxer_formats + $all_demuxer_formats | Sort -Unique
    $ffmpeg_formats | ConvertTo-Json | Out-File "$PSScriptRoot\ffmpeg_formats.json"

    Write-Output("Update Complete: " + $ffmpeg_formats.Count + " formats found.")
    Write-Output("`n") 
}
#Get all media file formats from a JSON file inside the script folder: 
else
{
    $ffmpeg_formats = Get-Content "$PSScriptRoot\ffmpeg_formats.json" | ConvertFrom-Json
}


#Save the version of the installed FFmpeg build if it has changed:
if ($current_ffmpeg_version -ne $saved_ffmpeg_version)
{
    $current_ffmpeg_version | ConvertTo-Json | Out-File "$PSScriptRoot\ffmpeg_version.json"
}


###VERIFY ALL FOLDER ENTRIES###


#Parse directory entries from $files_table into a List of PSCustomObjects:
$folders = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $files_table.Length; $i++)
{
    if ($files_table[$i].Length -eq 3)
    {        
        $folder_properties = [ordered]@{                                        
                                        Number      = $folders.Count + 1
                                        Table_Pos   = $i + 1
                                        Folder_Path = $files_table[$i][0]
                                        Recursive   = $files_table[$i][1]
                                        File_Types  = $files_table[$i][2]
        }
                                             
        $folders.Add((New-Object PSCustomObject -Property $folder_properties))
    }  
}


#Get full path for all Folder_Path entries:
$folders | ForEach {$_.Folder_Path = [IO.Path]::GetFullPath($_.Folder_Path)}


#Check if all Folder_Path entries exist:
ForEach($folder in $folders)
{
    if (-not(Test-Path -Path $folder.Folder_Path -PathType Container)) 
    {
        throw [IO.FileNotFoundException] ("The " + $folder.Table_Pos + ". table entry contains a path to a non-existing directory:" `
                                         +"`n" + $folder.Folder_Path)
    }
}


#Change File_Types entries into the correct format:
ForEach($folder in $folders)
{
    if (-not([String]::IsNullOrEmpty($folder.File_Types)))
    {
        [String[]]$folder.File_Types = $folder.File_Types -split ',' | ForEach {"." + ($_.Trim() -replace '\.', '')}
    }
}


#Check if all specified File_Types are supported by FFmpeg:
ForEach($folder in $folders)
{
    if ([String]::IsNullOrEmpty($folder.File_Types)){continue} #No need to check empty File_Types arrays.
    
    $unsupported = @()    
    $folder.File_Types | ForEach {if(-not($ffmpeg_formats.Contains($_))){$unsupported += $_}}

    if ($unsupported.Count -gt 0)
    {
        throw [ArgumentException] ("The " + $folder.Table_Pos + ". table entry contains one or more file types that are not supported by FFmpeg:" `
                                  +"`n" + $unsupported)
    }
}


#Fill blank #File_Types entries with every filetype that is supported by FFmpeg:
$folders | Where {[String]::IsNullOrEmpty($_.File_Types)} | ForEach {$_.File_Types = $ffmpeg_formats}


#Check if the #Recursive values are booleans:
$folders | ForEach {if($_.Recursive -isnot [bool]) {throw [ArgumentException] ("The #Recursive value for the " + $_.Table_Pos + ". table entry has to be a boolean.")}}


###VERIFY ALL FILE ENTRIES###


#Parse single file entries from $files_table into a List of PSCustomObjects:
$single_files = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $files_table.Length; $i++)
{
    if ($files_table[$i].Length -eq 1)
    {
        $files_properties = [ordered]@{
                                       Table_Pos = $i + 1
                                       File_Path = $files_table[$i][0]
                                       File_Ext  = ""
        }
                                             
        $single_files.Add((New-Object PSCustomObject -Property $files_properties))
    }  
}


#Get full path for all File_Path entries:
$single_files | ForEach {$_.File_Path = [IO.Path]::GetFullPath($_.File_Path)}


#Check if all File_Path entries exist:
ForEach($file in $single_files)
{
    if (-not(Test-Path -Path $file.File_Path -PathType Leaf)) 
    {
        throw [IO.FileNotFoundException] ("The " + $file.Table_Pos + ". table entry contains a path to a non-existing file:" `
                                         +"`n" + $file.File_Path)
    }
}


#Get the file extension of each single file entry:
$single_files | ForEach {$_.File_Ext = [System.IO.Path]::GetExtension($_.File_Path)}


#Check if all single file entries are supported by FFmpeg:
ForEach($file in $single_files)
{
    if (-not($ffmpeg_formats.Contains($file.File_Ext)))
    {
        throw [ArgumentException] ("The " + $file.Table_Pos + ". table entry has a file extension that is not supported by FFmpeg:" `
                                  +"`n" + $file.File_Ext)
    }
}


###COLLECT MEDIA FILES IN DICTIONARY###


#Initialize a Dictionary to store all media files with their filepaths and sizes:
$media_files = New-Object System.Collections.Generic.Dictionary"[String,Double]"


#Search for media files in all specified folders and add them to the dictionary:
ForEach($folder in $folders)
{    
    Write-Progress -Activity "Search For Media Files" -Status $folder.Folder_Path -PercentComplete (($folder.Number - 1) / $folders.Count * 100)
        
    if ($folder.Recursive)
    {        
        $found_files = Get-ChildItem $folder.Folder_Path -Force -Recurse | Where {$_.Extension -in $folder.File_Types} | Select FullName, Length
    }
    else
    {
        $found_files = Get-ChildItem $folder.Folder_Path -Force          | Where {$_.Extension -in $folder.File_Types} | Select FullName, Length
    }

    ForEach($file in $found_files)
    {        
        $file_path = $file.FullName
        $size      = $file.Length        
        
        if (-not($media_files.ContainsKey($file_path)))
        {
            $media_files.Add($file_path, $size)
        }        
    }
}

Write-Progress -Activity "Search For Media Files" -Status "Ready" -PercentComplete 100 -Completed


#Add all specified single files to the dictionary:
ForEach($file in $single_files)
{
    $file_path = $file.File_Path
    $size      = Get-Item $file.File_Path | Select -ExpandProperty Length

    if (-not($media_files.ContainsKey($file_path)))
    {
        $media_files.Add($file_path, $size)
    }  
}


#Count all media files and calculate the sum of all file sizes:
$num_of_files = $media_files.Count
$full_size    = $media_files.Values | Measure-Object -Sum | Select -ExpandProperty Sum
    

###DISPLAY MEDIA FILES###


#This function formats Bytes into the proper unit for display:
function ConvertStorageSizeUnit{
    param (
        [Double]$ByteSize 
    )

    if ($ByteSize -lt 1024)
    {
        "{0:N0} Bytes" -f ($ByteSize)
    }
    elseif ($ByteSize -lt [Math]::Pow(1024,2))
    {
        "{0:N2} KB" -f ($ByteSize / 1KB)
    }
    elseif ($ByteSize -lt [Math]::Pow(1024,3))
    {
        "{0:N2} MB" -f ($ByteSize / 1MB)
    }
    elseif ($ByteSize -lt [Math]::Pow(1024,4))
    {
        "{0:N2} GB" -f ($ByteSize / 1GB)
    }
    elseif ($ByteSize -lt [Math]::Pow(1024,5))
    {
        "{0:N2} TB" -f ($ByteSize / 1TB)
    }
    else
    {
        ">1024 TB"
    }
}


#Format and display the contents of the media file hashtable:
Write-Output("Collected Media Files:")
Write-Output("----------------------")

$media_files | Format-Table @{Label = ’Media File’; Expression = {[System.IO.Path]::GetFileName($_.key)}}, `
                            @{Label = ’Size’;       Expression = {ConvertStorageSizeUnit($_.value)}; Align = 'Right'}


#Display the number and the size of all files:
$full_stats = [PSCustomObject]@{
    Num_Of_Files = $num_of_files
    Full_Size    = ConvertStorageSizeUnit($full_size)
}

$full_stats  | Format-Table @{Label = ’Number of Files’; Expression = {$_.Num_Of_Files}; Align = 'Center'}, `
                            @{Label = ’Full Size’;       Expression = {$_.Full_Size};    Align = 'Center'}


#Ask the user to continue with the operation:
$confirm = Read-Host -Prompt "`nPress Enter to continue"

if ($confirm -eq "")
{
    Write-Output("`n")
}
else
{
    Write-Output("`nExit Operation")  
    exit
}


###CHECK MEDIA FILES AND LOG ERRORS###


Write-Output("################")
Write-Output("BEGIN FILE CHECK")
Write-Output("################")
Write-Output("`n")


#This function creates a folder for all log files:
$Script:log_folder_created = $false
 
function InitializeLogFolder{   
    
    $log_folder_name = $test_procedure + '-' + (Get-Date -Format yyyy_MM_dd-HH_mm_ss)
    $log_folder_path = Join-Path -Path $log_folder -ChildPath $log_folder_name
    $log_folder_path = New-Item  -Path $log_folder -Name $log_folder_name -ItemType "directory"

    $Script:log_folder_created = $true

    return $log_folder_path    
}


#This function creates a log file which will list all damaged files: 
function InitializeLogList{
    param (
        [string]$Log_Folder_Path
    )

    $error_list_path =  Join-Path $log_folder_path -ChildPath ("#" + $test_procedure + "_ERROR_LIST.log")           
    "List of damaged media files:" + "`n" > $error_list_path
  
    return $error_list_path
}


#This function logs an error that was detected in a media file:
$Script:error_counter = 0
$Script:damaged_files = @() 

function LogMediaFileError{
    param (
        [string[]]$Error_Message,
        [string]  $File_Path,
        [string]  $Log_Folder_Path,
        [string]  $Error_List_Path
    )    

    $Script:error_counter++    
    $Script:damaged_files+= [PSCustomObject]@{Number    = $Script:error_counter 
                                              File_Path = $File_Path}            
    #Append file path to the error-list-log-file:
    $File_Path >> $Error_List_Path
                
    #Log error in single file:
    $log_file_name = -Join($error_counter, "_",
                           [IO.Path]::GetFileNameWithoutExtension($File_Path), 
                           [IO.Path]::GetExtension($File_Path).replace('.','_'),                           
                           ".log")

    $log_file_path = Join-Path $Log_Folder_Path -ChildPath $log_file_name
    $File_Path + ":" + "`n" >  $log_file_path            
    $Error_Message          >> $log_file_path
}


#Use FFprobe to search for errors in all media files:
if ($test_procedure -eq "ffprobe")
{    
    $num_processed = 0

    ForEach($file in $media_files.GetEnumerator())
    {
        $file_path = $file.Key              

        Write-Progress -Activity "Check media files with FFprobe" -Status $file_path -PercentComplete ($num_processed / $num_of_files * 100)
                
        Write-Output($file_path + ":" + "`n")        
                
        #FFprobe check happens here:
        [string[]]$ffprobe_test_output = ffprobe -loglevel $log_level -i $file_path 2>&1
        
        #If an error has been found:
        if ($ffprobe_test_output.Count -gt 0)
        {                      
            #Write error message into console:
            [string]$error_output = $ffprobe_test_output | Out-String            
            Write-Error -Message $error_output
        
            #Initialize the log folder and the log file which lists all damaged files:
            if (-not $log_folder_created)
            {           
                $log_folder_path = InitializeLogFolder                   
                $error_list_path = InitializeLogList $log_folder_path
            }
        
            #Log the detected Error:
            LogMediaFileError $ffprobe_test_output $file_path $log_folder_path $error_list_path    
        }
        else
        {                                 
            Write-Host "No Errors Detected! `n" -ForegroundColor Green
        }
        
        $num_processed++                       
    }

    Write-Progress -Activity "Check media files with FFprobe" -Status "Ready" -PercentComplete 100 -Completed
}


#Use FFmpeg to search for errors in all media files:
if ($test_procedure -eq "ffmpeg")
{ 
    $size_processed = 0

    ForEach($file in $media_files.GetEnumerator())
    {
        $file_path = $file.Key
        $file_size = $file.Value              

        Write-Progress -Activity "Check media files with FFmpeg" -Status $file_path -PercentComplete ($size_processed / $full_size * 100)
                
        Write-Output($file_path + ":" + "`n")        
                
        #FFmpeg check happens here:
        [string[]]$ffmpeg_test_output = ffmpeg -loglevel $log_level -i $file_path -f null - 2>&1
        
        #If an error has been found:
        if ($ffmpeg_test_output.Count -gt 0)
        {                      
            #Write error message into console:
            [string]$error_output = $ffmpeg_test_output | Out-String            
            Write-Error -Message $error_output
        
            #Initialize the log folder and the log file which lists all damaged files:
            if (-not $log_folder_created)
            {           
                $log_folder_path = InitializeLogFolder                   
                $error_list_path = InitializeLogList $log_folder_path
            }
        
            #Log the detected Error:
            LogMediaFileError $ffmpeg_test_output $file_path $log_folder_path $error_list_path   
        }
        else
        {            
            Write-Host "No Errors Detected! `n" -ForegroundColor Green
        }
        
        $size_processed += $file_size                        
    }

    Write-Progress -Activity "Check media files with FFmpeg" -Status "Ready" -PercentComplete 100 -Completed
}


###PRINT DAMAGED FILES###


Write-Output("`n")
Write-Output("###################")
Write-Output("FILE CHECK COMPLETE")
Write-Output("###################")

if ($damaged_files.Count -eq 0)
{
     Write-Host "`nNo Errors Were Detected! `n" -ForegroundColor Green
}
else
{
     Write-Host ("`nThe script found {0} damaged media files:" -f $damaged_files.Count) -ForegroundColor red
     
     $damaged_files | Format-Table @{Label = '#';         Expression = {$_.Number};    Align = 'Left'}, `
                                   @{Label = 'File Path'; Expression = {$_.File_Path}; Align = 'Left'}

     Write-Host "The error logs have been saved at:" 
     Write-Host $log_folder_path
}


Read-Host -Prompt "`nPress Enter to exit"