; QIC (Quasi-In-Chat) Search
;
; Written by:
; /u/Eruyome87 
; /u/ProFalseIdol
;
; Latest Version will always be at:
; https://github.com/poeqic/qic
;
; Feel free to make pull-requests.
;

#SingleInstance force ; If it is already Running it will be restarted.
#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
#Persistent ; Stay open in background
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
SetBatchLines, -1
FileEncoding, utf-8

#Include, qic-files/lib/Gdip_All.ahk
; https://www.autohotkey.com/boards/viewtopic.php?t=1879
#Include, qic-files/lib/Gdip_Ext.ahk
; https://github.com/cocobelgica/AutoHotkey-JSON
#Include, qic-files/lib/JSON.ahk

Menu, tray, Tip, Path of Exile - QIC (Quasi-In-Chat) Search
Menu, tray, Icon, resource/qic$.ico

If (A_AhkVersion <= "1.1.22"){
    msgbox, You need AutoHotkey v1.1.22 or later to run this script. `n`nPlease go to http://ahkscript.org/download and download a recent version.
    Exit
}
; Start gdi+
If !pToken := Gdip_Startup()
{
   MsgBox, 48, gdiplus error!, Gdiplus failed to start. Please ensure you have gdiplus on your system
   ExitApp
}
OnExit, Exit

; Set Hotkey for toggling GUI overlay completely OFF, default = ctrl + q
; ^p and ^i conflicts with trackpetes ItemPriceCheck macro
Hotkey, ^q, ToggleGUI
; Set Hotkeys for browsing through search results
Hotkey, PgUp, PreviousPage
Hotkey, PgDn, NextPage

StringReplace, param1, parm1, $LF, `n, All
StringReplace, param2, parm2, $LF, `n, All
global poeWindowName = "Path of Exile ahk_class Direct3DWindowClass"
global poeWinID := WinExist(poeWindowName)
global isFullScreen := isWindowedFullScreen(poeWinID)
global debugActive := 
global PageSize := 5
global PageNumbers := 0
global ResultPages := []
global SearchResults := []
global SearchResultsWTB := []
global LastSelectedPage := 1
global TextToDraw = ""
global experimentalLogFilePath := GetPoELogFileFromRegistry()
global selectedFile := ReadValueFromIni("PoEClientLogFile", experimentalLogFilePath, "System")
global iniFilePath := "../overlay_config.ini"
global Leagues := ReadLeagues("qic-files/terms/leagues.txt")
global searchLeague := 
global PlayerList := [] ; array of strings
global searchTermPrefix := 
global searchTerm := 
global lastSearch := 
global ItemResults =
global useSimpleText := 0
global poeWindowXpos :=
global poeWindowYpos :=
global poeWindowWidth :=
global poeWindowHeight :=
global GuiON := 1
global Font := CheckFont("Arial")
lastTimeStamp := 0

Gosub, ReadIniValues

FileRead, BIGFILE, %selectedFile%
StringGetPos, charCount, BIGFILE,`n, R2 ; Init charCount to the location of the 2nd last location of `n. Note that Client.txt always has a trailing newline

;;; DEBUG
debug := "--------------------------------------------------------------------------------------------------"
WriteDebugLog(debug)
debug := "Started script."
WriteDebugLog(debug)
debug := "Operation System: " GetOS()
WriteDebugLog(debug)
debug := "AHK version: " A_AhkVersion " " (A_PtrSize = 4 ? 32 : 64) "-bit " (A_IsUnicode ? "Unicode" : "ANSI")
WriteDebugLog(debug)
debug := "PoE Client.txt Path (experimental, read from registry; last played installation in case you have the Standalone and Steam version): " experimentalLogFilePath
WriteDebugLog(debug)
debug := isFullScreen ? "Game is in Windowed Fullscreen Mode." : "Game is in Windowed Mode."
WriteDebugLog(debug)
;;;

;;; DEBUG
debug := "Path Of Exile Window: Xpos=" poeWindowXpos ", Ypos=" poeWindowYpos ", Width=" poeWindowWidth ", Height=" poeWindowHeight
WriteDebugLog(debug)
debug := "Poe Window is on Monitor " GetMonitorIndexFromWindow(poeWinID)
WriteDebugLog(debug)
debug := "Overlay DrawingArea: Xpos=" DrawingAreaPosX ", Ypos=" DrawingAreaPosY ", Width=" DrawingAreaWidth ", Height=" DrawingAreaHeight
WriteDebugLog(debug)
;;;

; Extra options:
; ow4         - Sets the outline width to 4
; ocFF000000  - Sets the outline colour to opaque black
; OF1			- If this option is set to 1 the text fill will be drawn using the same path that the outline is drawn.
AHKArchitecture := (A_PtrSize = 4 ? 32 : 64)
AHKEncoding := (A_IsUnicode ? "Unicode" : "ANSI")
If ((AHKEncoding != "Unicode") && (AHKArchitecture = 32) || (AHKArchitecture = 32)) {
	Options = x5 y5 w%tWidth% h%tHeight% Left cffffffff r4 s%FontSize%
	useSimpleText := 1
	;;; DEBUG	
	debug := "Using Text without Outline."
	WriteDebugLog(debug)
	;;;
}
Else {
	Options = x5 y5 w%tWidth% h%tHeight% Left cffffffff ow2 ocFF000000 OF1 r4 s%FontSize%
	useSimpleText := 0
	;;; DEBUG	
	debug := "Using Text with Outline."
	WriteDebugLog(debug)
	;;;
}

Gui, 1:  -Caption +E0x80000 +LastFound +OwnDialogs +Owner +AlwaysOnTop

hwnd1 := WinExist()
hbm := CreateDIBSection(DrawingAreaWidth, DrawingAreaHeight)
hdc := CreateCompatibleDC()
obm := SelectObject(hdc, hbm)
G := Gdip_GraphicsFromHDC(hdc)
Gdip_SetSmoothingMode(G, 4)

Gosub, DrawOverlay

OnMessage(0x201, "WM_LBUTTONDOWN")

Gosub, CheckWinActivePOE
SetTimer, CheckWinActivePOE, 100
Gosub, WatchInput
SetTimer, WatchInput, 100

Return


WM_LBUTTONDOWN() {
   PostMessage, 0xA1, 2
}

; ------------------ GET AND SET (UPDATE) DIMENSIONS AND POSITIONS------------------ 
; https://github.com/tariqporter/Gdip/blob/master/Gdip.Tutorial.8-Write.text.onto.a.gui.ahk
; Set the width and height we want as our drawing area, to draw everything in. This will be the dimensions of our bitmap
GetAndSetDimensions:
	WinGetPos, poeWindowXpos, poeWindowYpos, poeWindowWidth, poeWindowHeight, %poeWindowName%	
	
	If !isFullScreen {
		; windowed mode
		debug := "Detected Dimensions/Positions of " "Path Of Exile Window: Xpos=" poeWindowXpos ", Ypos=" poeWindowYpos ", Width=" poeWindowWidth ", Height=" poeWindowHeight
		WriteDebugLog(debug)
		
		SysGet, windowTitlebarHeight, 31
		windowTitlebarHeight := windowTitlebarHeight + 8
		
		If (poeWindowXpos < 0) 
			poeWindowXpos := 0
		If (poeWindowYpos < 0) 
			poeWindowYpos := 0
	}
	Else {
		; fullscreen borderless
		debug := "Detected Dimensions/Positions of " "Path Of Exile Window: Xpos=" poeWindowXpos ", Ypos=" poeWindowYpos ", Width=" poeWindowWidth ", Height=" poeWindowHeight
		WriteDebugLog(debug)

		windowTitlebarHeight := 0
		If (poeWindowXpos != 0) 
			poeWindowXpos := 0
		If (poeWindowYpos != 0) 
			poeWindowYpos := 0
		If (poeWindowWidth != A_ScreenWidth) 
			poeWindowWidth := A_ScreenWidth
		If (poeWindowHeight != A_ScreenHeight) 
			poeWindowHeight := A_ScreenHeight
	}
	
	DrawingAreaWidth 	:= ReadValueFromIni("Width", 310)
	DrawingAreaPosX 	:= ReadValueFromIni("AbsolutePositionLeft", ceil(poeWindowXpos + poeWindowWidth * 0.33 + DrawingAreaWidth))
	DrawingAreaPosY 	:= ReadValueFromIni("AbsolutePositionTop", poeWindowYpos + windowTitlebarHeight + 5)
	DrawingAreaHeight	:= ReadValueFromIni("Height", (poeWindowHeight - windowTitlebarHeight - 50))
	FontSize 			:= ReadValueFromIni("FontSize", 13)
	PageSize 			:= ReadValueFromIni("PageSize", 5)
	tWidth := DrawingAreaWidth - 8
	tHeight := DrawingAreaHeight - 8	
	
	debug := "Recalculated Dimensions/Positions of " "Path Of Exile Window: Xpos=" poeWindowXpos ", Ypos=" poeWindowYpos ", Width=" poeWindowWidth ", Height=" poeWindowHeight
	WriteDebugLog(debug)
	debug := "Overlay DrawingArea: Xpos=" DrawingAreaPosX ", Ypos=" DrawingAreaPosY ", Width=" DrawingAreaWidth ", Height=" DrawingAreaHeight
	WriteDebugLog(debug)
Return

; ------------------ READ ALL OTHER INI VALUES ------------------ 
ReadIniValues:
	Gosub, GetAndSetDimensions
	debugActive := ReadValueFromIni("DebugMode", 0 , "System")
	selectedFile := ReadValueFromIni("PoEClientLogFile", experimentalLogFilePath, "System")
	searchLeague := ReadValueFromIni("SearchLeague", , "Search")
	searchTermPrefix := ReadValueFromIni("SearchTermPrefix", , "Search") " " searchLeague " " 	
return

; ------------------ TOGGLE GUI ------------------
#IfWinActive, Path of Exile ahk_class Direct3DWindowClass 
ToggleGUI:
	ToggleGUI()
Return

ToggleGUI(){
	If (GuiON = 0) {
		Gosub, CheckWinActivePOE
		SetTimer, CheckWinActivePOE, 100
		GuiON = 1
	}
	Else {
		SetTimer, CheckWinActivePOE, Off      
		Gui, 1: Hide	
		GuiON = 0
	}
}

; ------------------ SHOW NEXT PAGE ------------------
#IfWinActive, Path of Exile ahk_class Direct3DWindowClass 
NextPage:	
	If LastSelectedPage < %PageNumbers%
		LastSelectedPage += 1
	Else
		Return
	
	Draw(ResultPages[LastSelectedPage])
Return

; ------------------ SHOW PREVIOUS PAGE ------------------
#IfWinActive, Path of Exile ahk_class Direct3DWindowClass 
PreviousPage:
	If LastSelectedPage > 1
		LastSelectedPage -= 1
	Else
		Return
	
	Draw(ResultPages[LastSelectedPage])	
Return

; ------------------ Draw TEXT TO OVERLAY ------------------ 
DrawText:
	Gui, 1: Show, NA
	If (useSimpleText = 0) {
		Gdip_TextToGraphicsOutline(G, TextToDraw, Options, Font, DrawingAreaWidth, DrawingAreaHeight)
	}
	Else {
		Gdip_TextToGraphics(G, TextToDraw, Options, Font, DrawingAreaWidth, DrawingAreaHeight)
	}
	UpdateLayeredWindow(hwnd1, hdc, DrawingAreaPosX, DrawingAreaPosY, DrawingAreaWidth, DrawingAreaHeight)
	;;; DEBUG	
	debug := "Text drawn to overlay."
	WriteDebugLog(debug)
	;;;
Return

; ------------------ DRAW (REDRAW) OVERLAY ------------------ 
; https://github.com/tariqporter/Gdip/blob/master/Gdip.Tutorial.8-Write.text.onto.a.gui.ahk
; Set the width and height we want as our drawing area, to draw everything in. This will be the dimensions of our bitmap
DrawOverlay:
	Gdip_GraphicsClear(G)
	pBrush := Gdip_BrushCreateSolid(0xffb4804b)
	; left border
	Gdip_FillRectangle(G, pBrush, 0, 0, 1, DrawingAreaHeight)
	; right border
	Gdip_FillRectangle(G, pBrush, DrawingAreaWidth - 2, 0, 1, DrawingAreaHeight)
	; top border
	Gdip_FillRectangle(G, pBrush, 0, 1, DrawingAreaWidth, 1)
	; bottom border
	Gdip_FillRectangle(G, pBrush, 0, DrawingAreaHeight - 2, DrawingAreaWidth, 1)
	; background
	pBrush := Gdip_BrushCreateSolid(0x47000000)
	Gdip_FillRectangle(G, pBrush, 0, 0, DrawingAreaWidth, DrawingAreaHeight)
Return

; ------------------ CALL DRAW SUBROUTINES ------------------ 
Draw(text=""){
	;If !isFullScreen {
		Gosub, GetAndSetDimensions
	;}
	Gosub, DrawOverlay	
	TextToDraw := text
	Gosub, DrawText	
}

; ------------------ READ INI AND CHECK IF VARIABLES ARE SET ------------------ 
ReadValueFromIni(IniKey, DefaultValue = "", Section = "Overlay"){
	IniRead, OutputVar, %iniFilePath%, %Section%, %IniKey%
	If !OutputVar
		OutputVar := DefaultValue
	Return OutputVar
}

; ------------------ WRITE TO INI ------------------
WriteValueToIni(IniKey,NewValue,IniSection){
	IniWrite, %NewValue%, %iniFilePath%, %IniSection%, %IniKey%
	Gosub, ReadIniValues
}

; ------------------ READ FONT FROM INI AND CHECK IF INSTALLED ------------------
CheckFont(DefaultFont){
	; Next we can check that the user actually has the font that we wish them to use
	; If they do not then we can do something about it. I choose to default to Arial.
	IniRead, InputFont, %iniFilePath%, Overlay, FontFamily
	If !hFamily := Gdip_FontFamilyCreate(InputFont)	{
	   OutputFont := DefaultFont
	}
	Else {
		Gdip_DeleteFontFamily(hFamily)
		OutputFont := InputFont
	}
	;;; DEBUG	
	debug := "Using font: " OutputFont
	WriteDebugLog(debug)
	;;;
	Return OutputFont
}

; ------------------ PAGE SEARCH RESULTS ------------------
PageSearchResults:
	LastSelectedPage := 1
	Temp := ItemObjectsToString(ItemResults)
	SearchResults := Temp[1]
	SearchResultsWTB := Temp[2]
	PageNumbers := ceil(SearchResults.MaxIndex() / PageSize)
	ResultPages := []
	
	If PageNumbers = 0
		PageNumbers := 1

	LastIndex = 0
	Loop %PageNumbers%
	{	
		If !searchLeague
			league := "League Placeholder"
		Page := searchLeague " | Page " A_Index "/" PageNumbers " " "`r`n"
		Loop %PageSize%
		{
			Page .= SearchResults[A_Index+LastIndex]
		}
		If !SearchResults[1] {
			Page .= "_______________________________________________" "`r`n" "`r`n"
			Page .= "0 search results."
		}
		LastIndex := PageSize * A_Index
		ResultPages.Insert(Page)
	}
	
	;;; DEBUG	
	debug := "Search results paged."
	WriteDebugLog(debug)
	;;;
	Draw(ResultPages[LastSelectedPage])
Return

; ------------------ RETURN PRINTABLE ITEMS ------------------ 
ItemObjectsToString(ObjectArray){
	oa := ObjectArray
	o := []
	d := []
	s := 	
	smallSeperator := "-----------"
	bigSeperator := "_______________________________________________"
	; !!!!!!!!!!!!!!!! Gem/Map Level, Quantity Stack !!!!!!!!!!!!!!!!
	
	for i, e in oa {
		su =
		wtb = 
		; Add item index, name, sockets and quality			
		su .= bigSeperator "`r`n"
		su .= "[" e.id "] " e.name
		wtb .= "@" e.ign " Hi, I would like to buy your " e.name " listed for """ StringToUpper(e.buyout) """ in " e.league " with the following Stats:"
		If e.socketsRaw {
			su .= " " e.socketsRaw 
			wtb .= " Sockets " e.socketsRaw
		}
		If e.quality {			
			su .= " Q" cFloor(e.quality) "%"
			wtb .= " Q" cFloor(e.quality) "%"
		}		
		If e.mapQuantity {
			su .= "`r`n" "Quantity: " cFloor(e.mapQuantity) "%"
			wtb .= " Quant. " cFloor(e.mapQuantity) "%"
		}
		If e.mapRarity {
			su .= "`r`n" "Rarity: " cFloor(e.mapRarity) "%"
			wtb .= " Qual. " cFloor(e.mapRarity) "%"
		}
		
		; Add implicit mod
		If e.implicitMod {
			su .= "`r`n"
			temp := RegExReplace(e.implicitMod.name, "#|\$",,,1)
			temp := StrReplace(temp, "#", cFloor(e.implicitMod.value))
			su .= temp
			wtb .= " --- " temp
		}
		
		; Add explicit mods
		If (e.explicitMods.MaxIndex() > 0 || e.identified = 0) {
			su .=  "`r`n" smallSeperator
		}
		If e.explicitMods.MaxIndex() > 0 {
			
			for j, f in e.explicitMods {
				temp := StrReplace(f.name, "#",,,1)
				; Handle div cards
				temp2 := 
				While RegExMatch(temp, "(\{.*?\})", match) {
					temp := RegExReplace(temp, "(\{.*?\})",,,1)
					temp2 .= RegExReplace(match, "\{|\}") " "
				}
				If temp2 {
					temp := temp2
				}
				; Insert value into name
				If (f.value > 0){
					temp := StrReplace(temp, "#", cFloor(f.value))
				}				
				su .= "`r`n" temp
				wtb .= " --- " temp
			}
		}	
		; Unidentified Tag
		If e.identified = 0 {
			su .= "`r`n" "Unidentified"
		}
		su .= "`r`n" smallSeperator "`r`n"
				
		; Corrupted Tag
		If e.corrupted = 1 {
			su .= "Corrupted" "`r`n"
			wtb .= " --- Corrupted" 
		}
		
		; Add defenses
		If e.armourAtMaxQuality || e.energyShieldAtMaxQuality || e.evasionAtMaxQuality || e.block {
			defenseFound := 1
			If e.armourAtMaxQuality && e.energyShieldAtMaxQuality { 
				temp := "AR: " cFloor(e.armourAtMaxQuality) " " "ES: " cFloor(e.energyShieldAtMaxQuality)				
			}
			Else If e.armourAtMaxQuality && e.evasionAtMaxQuality {
				temp := "AR: " cFloor(e.armourAtMaxQuality) " " "EV: " cFloor(e.evasionAtMaxQuality)
			}
			Else If e.evasionAtMaxQuality && e.energyShieldAtMaxQuality {
				temp := "EV: " cFloor(e.evasionAtMaxQuality) " " "ES: " cFloor(e.energyShieldAtMaxQuality)
			}
			Else If e.armourAtMaxQuality  {
				temp := "AR: " cFloor(e.armourAtMaxQuality)
			}
			Else If e.evasionAtMaxQuality  {
				temp := "EV: " cFloor(e.evasionAtMaxQuality)
			}
			Else If e.energyShieldAtMaxQuality  {
				temp := "ES: " cFloor(e.energyShieldAtMaxQuality)
			}
			Else If e.armourAtMaxQuality && e.evasionAtMaxQuality && e.energyShieldAtMaxQuality {
				temp := "AR: " cFloor(e.armourAtMaxQuality) " " "EV: " cFloor(e.evasionAtMaxQuality) " " "ES: " cFloor(e.energyShieldAtMaxQuality)
			}
			su .= temp
			wtb .= " --- @MaxQuality " temp 
			If e.block {
				su .= " Block: " cFloor(e.block)
				wtb .= " Block: " cFloor(e.block)
			}
		}
		
		; Add pdps, edps, aps and critchance
		; Don't add critchance if it's a skillgem/map (e.level set)
		If e.physDmgAtMaxQuality || e.eleDmg || e.attackSpeed || (e.crit && !varExist(e.level)){
			damageFound := 1
			temp := 
			If e.physDmgAtMaxQuality {
				temp .= "pDPS " Floor(e.physDmgAtMaxQuality) " "
			}
			If e.eleDmg {
				temp .= "eDPS " Floor(e.eleDmg) " "
			}
			If e.attackSpeed {
				temp .= "APS " cFloor(e.attackSpeed) " "
			}
			If e.crit {
				temp .= "CC " cFloor(e.crit)
			}
			su .= temp
			wtb .= " --- @MaxQuality " temp
		}
		
		If e.level || e.stackSize {
			stuffFound := 1
			If e.level {
				If varExist(e.mapQuantity) {
					su .= "Tier: " cFloor(e.level)
					wtb .= "--- Tier " cFloor(e.level)
				}
				Else {
					su .= "Level: " cFloor(e.level)
					wtb .= "--- Level " cFloor(e.level)
				}				
			}
			If e.stackSize {
				su .= "Quantity: " cFloor(e.stackSize)
			}
			su .= "`r`n"
		}
		
		; Add requirements
		If e.reqLvl || e.reqStr || e.reqInt || e.reqDex {
			requirementsFound := 1
			If defenseFound || damageFound {
				su .= " | "
			}
			If e.reqLvl {
				su .= "reqLvl " cFloor(e.reqLvl) " "
			}
			If e.reqStr {
				su .= "Str " cFloor(e.reqStr) " "
			}
			If e.reqInt {
				su .= "Int " cFloor(e.reqInt) " "
			}
			If e.reqDex {
				su .= "Dex " cFloor(e.reqDex)
			}
		}
		If (defenseFound || damageFound || requirementsFound) {
			su .= "`r`n"
		}		
		
		; Add price, ign
		su .= e.buyout " " "IGN: " e.ign "`r`n"
		o[i] := su
		d[i] := wtb
	}

	temp := [o, d]
	;;; DEBUG	
	debug := "Item print view created."
	WriteDebugLog(debug)
	;;;
	return temp
}

; ---------- CHECK IF VARIABLE EXISTS -----------------
varExist(ByRef v) {
   return &v = &n ? 0 : v = "" ? 2 : 1
}

; ---------- CUT OFF DECIMALS ONLY IF VALUE AFTER DECIMAL POINT IS 0 -----------------
cFloor(v) {
	If (mod(v,1)=0) {
		v := Floor(v)
	}
	Else {
		v := v
	}
	
	Return v
}

; ---------- STRING TO UPPER AS FUNCTION -----------------
StringToUpper(s){
	StringUpper, s, s
	Return s
}

; ---------- VIEW SINGLE ITEM -----------------
ShowDetailedItem(index){
	If !searchLeague
		league := "League Placeholder"
	View := searchLeague " | Detailed Item View" "`r`n" SearchResults[index+1]
	LastSelectedPage := Floor((index+1) / PageSize)
	
	Draw(View)
}

; ------------------ HIDE/SHOW OVERLAY IF GAME IS NOT ACTIVE/ACTIVE ------------------
CheckWinActivePOE:
	GuiControlGet, focused_control, focus
	If(WinActive(poeWindowName))
		If (GuiON = 0) {
			Gui, 1: Show, NA
			GuiON := 1
		}
	If(!WinActive(poeWindowName))
		;If !focused_control
		If (GuiON = 1)
		{
			Gui, 1: Hide
			GuiON := 0
		}
Return

; ------------------ WATCH CLIENT.TXT ------------------ 
WatchInput:
	;StartTime := A_TickCount
	FileRead, BIGFILE, %selectedFile%
	StringGetPos, lastNewLineLocation, BIGFILE,`n, R2 ; Client.txt always has a trailing newline
	StringTrimLeft, SmallFile, BIGFILE, %lastNewLineLocation%	
	;ElapsedTime := A_TickCount - StartTime
	
	;MsgBox,  %ElapsedTime% milliseconds have elapsed. Output is: `r`n %SmallFile% `r`n `r`n Characters: %lastNewLineLocation%	
	; Do nothing if character count unchanged	
	If (lastNewLineLocation > charCount) {
		parsedLines := ParseLines(SmallFile)
		s := parsedLines[parsedLines.MaxIndex()].message
		charCount := lastNewLineLocation
		ProcessLine(s)
	}
Return

; ------------------ PARSE CLIENT.TXT LINES ------------------ 
ParseLines(s){
	o := []
	Loop, Parse, s, `n
	{		
		If A_LoopField {
			line := {}
			RegExMatch(s, "(\d{4}/\d{1,2}/\d{1,2} \d{1,2}:\d{1,2}:\d{1,2})", timestamp)
			; Prepare timestamp for easier comparing
			line.timestamp := RegExReplace(timestamp, "[: \/]")			
			
			StringGetPos, pos1, A_LoopField, ]
			StringTrimLeft, message, A_LoopField, pos1 + 1			
			
			StringGetPos, pos1, message, :		
			If !ErrorLevel {
				StringLeft, messagePrefix, message, pos1
				; Exclude Global, Trade and Whisper messages
				RegExMatch(messagePrefix, "[#$@]", excludedChannels)
				
				Loop % PlayerList.Length() {				
					validPlayer := InStr(messagePrefix, PlayerList[A_Index])
					If validPlayer > 0
						Break
					Else 
						validPlayer :=
				}
				
				validPlayer := 1 ; placeholder variable, remove later when playernames can be validated
				If !excludedChannels && validPlayer {
					StringTrimLeft, message, message, pos1 + 2
					StringReplace,message,message,`n,,A
					StringReplace,message,message,`r,,A
					line.message := message
					o.Insert(line)
				}				
			}			
		}		
	}		
	Return o
}

; ------------------ SEND SEARCH REQUEST, PARSE JSON ------------------ 
GetResults(term, addition = ""){
	escapedTerm := StrReplace(term, """","""""",,-1) ; for search terms like 'name="brightbeak"', we need to escape those double quotes
	searchTerm := """" . searchTermPrefix escapedTerm " " addition . """"
	lastSearch := term
	RunWait, java -Dfile.encoding=UTF-8 -jar qic.jar %searchTerm%, , Hide ; after this line finishes, results.json should appear
	FileRead, JSONFile, results.json	
	parsedJSON 	:= JSON.Load(JSONFile)	
	ItemResults 	:= parsedJSON.itemResults
	searchLeague 	:= parsedJSON.league
	;;; DEBUG	
	debug := "JSON parsed."
	WriteDebugLog(debug)
	;;;
	Gosub, PageSearchResults		
}

; ------------------ GET AND PASTE WTB-MESSAGE (OR SAVE IT TO FILE) ------------------ 
GetWTBMessage(index, prepareSending){
	index := index + 1
	
	If prepareSending {
		clipboard := SearchResultsWTB[index]
		SendEvent {Enter}
		SendInput ^a
		SendInput ^v
		SendEvent {Home}
	}
	Else {
		message := SearchResultsWTB[index] 
		FormatTime, TimeString, T12, Time
		wtb := "----------------------------------------------------------------------------------" "`r`n"
		;wtb .= [%A_YYYY%/%A_MM%/%A_DD% %TimeString%]
		wtb .= "[" A_YYYY "/" A_MM "/" A_DD " " TimeString "]"
		wtb .= "`r`n" message "`r`n`r`n"
		FileAppend, %wtb%, savedWTB_messages.txt
	}	
}

; ------------------ WHO IS SELLER ------------------ 
WhoIsSeller(index){
	index := index + 1
	s := "/whois " ItemResults[index].ign
	SendEvent {Enter}
	SendInput ^a
	SendInput %s%
	SendInput {Enter}
}

; ------------------ LIST LEAGUES ------------------ 
ListLeagues(){
	temp := "Options`r`n"
	temp .= "Type: setleague# to select a League." "`r`n"
	temp .= "_______________________________________________" "`r`n`r`n"
	for i, e in Leagues {
		temp .= i ". " e[2] "`r`n"
	}
	
	Draw(temp)
}

; ------------------ READ LEAGUES ------------------ 
ReadLeagues(file){
	FileRead, fileName, %file%
	o := []
	Loop, Parse, fileName, `n
	{		
		If !RegExMatch(A_LoopField, ";") {
			v := A_LoopField
			StringReplace, v, v, ?,, All
			StringTrimLeft, l, v, InStr(v, "=",, 0)
			If RegExMatch(v,"tempstandard") {
				o.Insert(e:=["tempstandard",l])
			}
			Else If RegExMatch(v,"temphardcore") {
				o.Insert(e:=["temphardcore",l])
			}
			Else If RegExMatch(v,"standard") {
				o.Insert(e:=["standard",l])
			}
			Else If RegExMatch(v,"hardcore") {
				o.Insert(e:=["hardcore",l])
			}
		}
	}
	Return o
}

; ------------------ OPEN HELP ------------------ 
OpenExternalHelpFile(){
	Run, help\help.htm
}

; ------------------ PROCESS PARSED CLIENT.TXT LINE ------------------ 
ProcessLine(input){
	Length := StrLen(input)
	
	If StartsWith(input, "^s ") {
		term := StrReplace(input, "s ",,,1)
		GetResults(term)
	}
	Else If StartsWith(input, "^search ") {
		term := StrReplace(input, "search ",,,1)
		GetResults(term)
	}	
	Else If StartsWith(input, "^searchexit$") || StartsWith(input, "^sexit$") {
		Gosub, Exit
	}
	Else If (GuiOn = 1) {
		; match "sort{sortby} (optional:asc or desc)" without tailing string, example: "sortlife" and "sortlife asc" but not "sortlife d" 
		If StartsWith(input, "^sort[a-zA-Z]+\s?(asc|desc)?$") {
			GetResults(lastSearch, input)			
		}
		; Match digits without characters after (generate and paste WTB message for item #0-98)
		Else If StartsWith(input, "^\d{1,2}$") {
			GetWTBMessage(input, 1)
		}
		; view item details
		Else If StartsWith(input, "^view\d{1,2}$") {
			Item := RegExReplace(input, "view")	
			ShowDetailedItem(Item)
		}
		; jump to page#
		Else If StartsWith(input, "^page\d{1,2}$") {
			Page := RegExReplace(input, "page")			
			If (Page > PageNumbers) {
				LastSelectedPage := PageNumbers
			}
			Else {
				LastSelectedPage := Page
			}
			Draw(ResultPages[LastSelectedPage])
		}
		; exit search
		Else If StartsWith(input, "^se$") || StartsWith(input, "^searchend$") {
			ToggleGUI()			
		}
		; sends /whois seller message
		Else If StartsWith(input, "^who\d{1,2}$") {
			Who := RegExReplace(input, "who")	
			WhoIsSeller(Who)
		}
		; write pagesize to ini
		Else If StartsWith(input, "^setps\d{1}$") {
			option := RegExReplace(input, "setps")	
			WriteValueToIni("PageSize",option,"Overlay")
		}
		; reload overlay_config.ini
		Else If StartsWith(input, "^reload$") {
			Gosub, ReadIniValues			
			Gosub, PageSearchResults
		}
		Else If StartsWith(input, "^listleagues") {
			ListLeagues()
		}	
		Else If StartsWith(input, "^setleague[1-4]$") {
			option := RegExReplace(input, "setleague")
			option := """" Leagues[option][1] """"
			WriteValueToIni("SearchLeague",option,"Search")
			Gosub, ReadIniValues
		}
		Else If StartsWith(input, "^shelp") {
			OpenExternalHelpFile()
		}
		Else If StartsWith(input, "^swtb\d{1,2}") {
			Item := RegExReplace(input, "swtb")
			GetWTBMessage(Item, 0)
		}
	}
}

; ------------------  ------------------ 
StartsWith(s, regex){
	pos := RegExMatch(s, regex)
	If pos = 1
		Return true
	Else 
		Return false
}

; ------------------ WRITE TO DEBUG LOG ------------------ 
WriteDebugLog(debugText){
	If !debugActive {
		Return
	}
	
	FormatTime, TimeString, T12, Time
	stamp = [%A_YYYY%/%A_MM%/%A_DD% %TimeString%]
	stamp .= " " debugText "`r`n"
	FileAppend, %stamp%, debug_log.txt
}

; ------------------ CHECK IF WINDOW IS IN WINDOWED FULLSCREEN OR WINDOWED MODE ------------------ 
isWindowedFullScreen(winID) {
	;checks if the specified window is full screen
	If ( !winID )
		Return false

	WinGet style, Style, ahk_id %WinID%
	WinGetPos ,,,winW,winH, %winTitle%
	; 0x800000 is WS_BORDER.
	; 0x20000000 is WS_MINIMIZE.
	; no border and not minimized
	Return ((style & 0x20800000) or winH < A_ScreenHeight or winW < A_ScreenWidth) ? false : true
}

; ------------------ FIND ALL PATH OF EXILE INSTALLATIONS AND GET THE PATH TO THE LAST CHANGED CLIENT.TXT ------------------ 
GetPoELogFileFromRegistry(){
	logFile := "logs\client.txt"
	standalone :=
	Loop, Reg, HKEY_CURRENT_USER\Software\GrindingGearGames\Path of Exile, KVR
	{
		if a_LoopRegType = key
			value =
		else {
			RegRead, value
			if ErrorLevel
				value = *error*
		}
		
		If (a_LoopRegName = "InstallLocation") {
			standalone := value logFile
			Break
		}
	}

	steam :=
	Loop, Reg, HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 238960, KVR
	{
		if a_LoopRegType = key
			value =
		else {
			RegRead, value
			if ErrorLevel
				value = *error*
		}
			
		If (a_LoopRegName = "InstallLocation") {
			steam := value "\" logFile
			Break
		}
	}
	
	logPath := "h"
	If (standalone && steam) {
		FileGetTime, one, %standalone%
		FileGetTime, two, %steam%
		
		If (one > two) {
			logPath := standalone
		}
		Else {
			logPath := steam
		}
	}
	Else If standalone {
		logPath := standalone
	}
	Else If steam {
		logPath := steam
	}

	return logPath	
}


; ------------------ GET MONITOR INFO ------------------ 
GetMonitorIndexFromWindow(windowHandle)
{
	; Starts with 1.
	monitorIndex := 1

	VarSetCapacity(monitorInfo, 40)
	NumPut(40, monitorInfo)
	
	if (monitorHandle := DllCall("MonitorFromWindow", "uint", windowHandle, "uint", 0x2)) 
		&& DllCall("GetMonitorInfo", "uint", monitorHandle, "uint", &monitorInfo) 
	{
		monitorLeft   := NumGet(monitorInfo,  4, "Int")
		monitorTop    := NumGet(monitorInfo,  8, "Int")
		monitorRight  := NumGet(monitorInfo, 12, "Int")
		monitorBottom := NumGet(monitorInfo, 16, "Int")
		workLeft      := NumGet(monitorInfo, 20, "Int")
		workTop       := NumGet(monitorInfo, 24, "Int")
		workRight     := NumGet(monitorInfo, 28, "Int")
		workBottom    := NumGet(monitorInfo, 32, "Int")
		isPrimary     := NumGet(monitorInfo, 36, "Int") & 1

		SysGet, monitorCount, MonitorCount

		Loop, %monitorCount%
		{
			SysGet, tempMon, Monitor, %A_Index%

			; Compare location to determine the monitor index.
			if ((monitorLeft = tempMonLeft) and (monitorTop = tempMonTop)
				and (monitorRight = tempMonRight) and (monitorBottom = tempMonBottom))
			{
				monitorIndex := A_Index
				break
			}
		}
	}
	
	Height := monitorBottom - monitorTop
	Width  := monitorRight  - monitorLeft
	r := "#" monitorIndex " max Resolution: " Width "x" Height
	
	return r
}

; ------------------ GET OS INFO ------------------ 
GetOS(){
	objWMIService := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\" . A_ComputerName . "\root\cimv2")
	colOS := objWMIService.ExecQuery("Select * from Win32_OperatingSystem")._NewEnum
	Versions := []
	Versions.Insert(e:=["5.1.2600","Windows XP, Service Pack 3"])
	Versions.Insert(e:=["6.0.6000","Windows Vista"])
	Versions.Insert(e:=["6.0.6002","Windows Vista, Service Pack 2"])
	Versions.Insert(e:=["6.0.6001","Server 2008"])
	Versions.Insert(e:=["6.1.7601","Windows 7"])
	Versions.Insert(e:=["6.1.8400","Windows Home Server 2011"])
	Versions.Insert(e:=["6.2.9200","Windows 8"])
	Versions.Insert(e:=["6.3.9200","Windows 8.1"])
	Versions.Insert(e:=["6.3.9600","Windows 8.1, Update 1"])
	
	While colOS[objOS] { 	
	;	MsgBox % "OS version: " . objOS.Version . " Service Pack " . objOS.ServicePackMajorVersion . " Build number " . objOS.BuildNumber
	}
	
	For i, e in Versions {		
		If (e[1] = objOS.Version) {
			r := e[2] " (" A_OSVersion ")"
		}
		Else r := "Windows Version Number " objOS.Version " (" A_OSVersion ")"
	}	
	If ((FileExist("C:\Program Files (x86)")) ? 1 : 0) 
		r .= ", 64bit."
	
	Return r
}

; ------------------ EXIT ------------------ 
Exit:
	Gdip_DeleteBrush(pBrush)
	SelectObject(hdc, obm)
	DeleteObject(hbm)
	DeleteDC(hdc)
	Gdip_DeleteGraphics(G)
	Gdip_Shutdown(pToken)
	ExitApp
Return