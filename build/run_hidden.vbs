' run_hidden.vbs
' Runs a batch file completely hidden (no console window).
' Usage: wscript.exe //nologo //B run_hidden.vbs "C:\path\to\temp.bat"
'
' wscript.exe is a GUI app (no console flash).
' sh.Run with style 0 = hidden window.
' True = wait for completion.
' Exit code propagates back to the caller.

If WScript.Arguments.Count < 1 Then
  WScript.Quit 1
End If

Set sh = CreateObject("WScript.Shell")

batFile = WScript.Arguments(0)

exitCode = sh.Run("""" & batFile & """", 0, True)

WScript.Quit exitCode
