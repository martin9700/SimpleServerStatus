Ever wanted a simple HTML report showing you the UP/DOWN status of your servers? And for a little extra flavor how long that server has been up for? Some basic disk information?
1. Download the script to your favorite location and name it Out-SimpleServerStatus.ps1 
2. Open a Powershell prompt and type: Get-Help pathtoscript\Out-SimpleServerStatus.ps1 -Full 
3. Edit PARAM section so that variables match your environment. 
4. Edit $Key variable with random numbers, this is your encryption key. 
5. Run it manually once, if you are using alternative credentials script will prompt you for password and save those credentials to a file.

To run as a scheduled task: 
1. Create the scheduled task and set your trigger (hourly?) 
2. For action the Executable should be Powershell.exe 
3. For Arguments use: -ExecutionPolicy Bypass -File pathtoscript\Out-SimpleServerStatus.ps1

Inspired by this thread: 
http://community.spiceworks.com/topic/264653-server-uptime-display

Read more about this script on my Blog: 
http://thesurlyadmin.com/2012/10/11/simple-server-status/

And you can read more about the latest version here: 
http://thesurlyadmin.com/2013/05/07/new-version-simple-server-status/