function Write-VerboseEvent ($Message) {
    $timeStamp = Get-Date -Format "yyyy/MM/dd HH:mm:ss"
    $verboseOutput = $timeStamp, "Verbose", $Message -join " | "
    Write-Verbose $verboseOutput
}
