USING System
USING System.IO
USING System.Drawing
USING System.Globalization
USING System.Collections.Generic

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>Program settings, stored in %APPDATA%\FabDBFEdEnh\FabDBFEdEnh.ini</summary>
PUBLIC CLASS AppSettings
    PUBLIC Driver          := "DBFCDX" AS STRING
    PUBLIC Exclusive        := FALSE    AS LOGIC
    PUBLIC ReadOnly        := FALSE    AS LOGIC
    PUBLIC ShowRecno      := TRUE     AS LOGIC
    PUBLIC ShowDeleted := TRUE     AS LOGIC
    PUBLIC AutoCommit      := TRUE     AS LOGIC
    PUBLIC FullPath      := FALSE    AS LOGIC
    // Display font for the browse window
    PUBLIC FontName     := "Microsoft Sans Serif" AS STRING
    PUBLIC FontSize  := 8.25     AS REAL4
    PUBLIC FontStyleName     := 0        AS INT
    // Set Defaults (stage 4)
    PUBLIC DefaultPath    := ""       AS STRING
    PUBLIC Locking         := 0        AS INT      // 0 = Automatic, 1 = Manual
    PUBLIC ShellMaximized  := FALSE    AS LOGIC
    PUBLIC DataMaximized  := FALSE    AS LOGIC
    PUBLIC DateName      := "German" AS STRING   // chosen template, "" = own format
    PUBLIC DateFormat    := "DD.MM.YYYY" AS STRING  // VO notation
    PUBLIC Century     := TRUE     AS LOGIC
    PUBLIC Epoch          := 1900     AS INT
    PUBLIC LogErrors       := TRUE     AS LOGIC
    PUBLIC SaveOptions := TRUE   AS LOGIC
    PUBLIC AskQuit   := FALSE    AS LOGIC

    /// <summary>The loaded settings of the running app (for date display, error log)</summary>
    PUBLIC STATIC Active AS AppSettings
    // recently opened files, format "MODE|DRIVER|Path"
    PUBLIC Recent         := List<STRING>{} AS List<STRING>

    PRIVATE STATIC METHOD IniFile() AS STRING
        LOCAL cFolder := Path.Combine( Environment.GetFolderPath( Environment.SpecialFolder.ApplicationData ), "FabDBFEdEnh" ) AS STRING
        IF ! Directory.Exists( cFolder )
            Directory.CreateDirectory( cFolder )
        ENDIF
        RETURN Path.Combine( cFolder, "FabDBFEdEnh.ini" )

    /// <summary>Old (German) INI key -> current key, so existing settings files keep working</summary>
    PRIVATE STATIC METHOD MigrateKey( cKey AS STRING ) AS STRING
        SWITCH cKey
        CASE "EXKLUSIV"          ; RETURN "EXCLUSIVE"
        CASE "NURLESEN"          ; RETURN "READONLY"
        CASE "ZEIGERECNO"        ; RETURN "SHOWRECNO"
        CASE "ZEIGEGELOESCHTE"   ; RETURN "SHOWDELETED"
        CASE "VOLLERPFAD"        ; RETURN "FULLPATH"
        CASE "SCHRIFTNAME"       ; RETURN "FONTNAME"
        CASE "SCHRIFTGROESSE"    ; RETURN "FONTSIZE"
        CASE "SCHRIFTSTIL"       ; RETURN "FONTSTYLE"
        CASE "STANDARDPFAD"      ; RETURN "DEFAULTPATH"
        CASE "SHELLMAXIMIERT"    ; RETURN "SHELLMAXIMIZED"
        CASE "DATENMAXIMIERT"    ; RETURN "DATAMAXIMIZED"
        CASE "DATUMSNAME"        ; RETURN "DATENAME"
        CASE "DATUMSFORMAT"      ; RETURN "DATEFORMAT"
        CASE "JAHRHUNDERT"       ; RETURN "CENTURY"
        CASE "EPOCHE"            ; RETURN "EPOCH"
        CASE "FEHLERLOG"         ; RETURN "ERRORLOG"
        CASE "OPTIONENSPEICHERN" ; RETURN "SAVEOPTIONS"
        CASE "BEENDENFRAGEN"     ; RETURN "ASKQUIT"
        END SWITCH
        // ZULETZT1, ZULETZT2 ... (recently opened files)
        IF cKey:StartsWith( "ZULETZT" )
            RETURN "RECENT" + cKey:Substring( 7 )
        ENDIF
        RETURN cKey

    PUBLIC STATIC METHOD LoadSettings() AS AppSettings
        LOCAL oE := AppSettings{} AS AppSettings
        TRY
            LOCAL cIni := IniFile() AS STRING
            IF File.Exists( cIni )
                FOREACH cRow AS STRING IN File.ReadAllLines( cIni )
                    LOCAL nPos := cRow:IndexOf( "=" ) AS INT
                    IF nPos > 0
                        LOCAL cKey := cRow:Substring( 0, nPos ):Trim():ToUpper() AS STRING
                        LOCAL cVal := cRow:Substring( nPos + 1 ):Trim() AS STRING
                        // settings files written by the German version use German key names
                        cKey := AppSettings.MigrateKey( cKey )
                        SWITCH cKey
                        CASE "DRIVER"          ; oE:Driver          := cVal
                        CASE "EXCLUSIVE"        ; oE:Exclusive        := cVal == "1"
                        CASE "READONLY"        ; oE:ReadOnly        := cVal == "1"
                        CASE "SHOWRECNO"      ; oE:ShowRecno      := cVal == "1"
                        CASE "SHOWDELETED" ; oE:ShowDeleted := cVal == "1"
                        CASE "AUTOCOMMIT"      ; oE:AutoCommit      := cVal == "1"
                        CASE "FULLPATH"      ; oE:FullPath      := cVal == "1"
                        CASE "FONTNAME"     ; oE:FontName     := cVal
                        CASE "DEFAULTPATH"    ; oE:DefaultPath    := cVal
                        CASE "LOCKING"         ; oE:Locking         := IIF( cVal == "1", 1, 0 )
                        CASE "SHELLMAXIMIZED"  ; oE:ShellMaximized  := cVal == "1"
                        CASE "DATAMAXIMIZED"  ; oE:DataMaximized  := cVal == "1"
                        CASE "DATENAME"      ; oE:DateName      := cVal
                        CASE "DATEFORMAT"
                            IF cVal:Length > 0
                                oE:DateFormat := cVal:ToUpper()
                            ENDIF
                        CASE "CENTURY"     ; oE:Century     := cVal == "1"
                        CASE "EPOCH"
                            LOCAL nEpochVal := 0 AS INT
                            IF Int32.TryParse( cVal, OUT nEpochVal ) .AND. nEpochVal >= 1000 .AND. nEpochVal <= 2900
                                oE:Epoch := nEpochVal
                            ENDIF
                        CASE "ERRORLOG"       ; oE:LogErrors       := cVal == "1"
                        CASE "SAVEOPTIONS" ; oE:SaveOptions := cVal == "1"
                        CASE "ASKQUIT"   ; oE:AskQuit   := cVal == "1"
                        CASE "FONTSIZE"
                            LOCAL nCenturyOff := 0 AS REAL4
                            IF Single.TryParse( cVal, NumberStyles.Float, CultureInfo.InvariantCulture, OUT nCenturyOff ) .AND. nCenturyOff >= 4 .AND. nCenturyOff <= 72
                                oE:FontSize := nCenturyOff
                            ENDIF
                        CASE "FONTSTYLE"
                            LOCAL nS := 0 AS INT
                            IF Int32.TryParse( cVal, OUT nS )
                                oE:FontStyleName := nS
                            ENDIF
                        OTHERWISE
                            IF cKey:StartsWith( "RECENT" ) .AND. cVal:Length > 0
                                oE:Recent:Add( cVal )
                            ENDIF
                        END SWITCH
                    ENDIF
                NEXT
            ENDIF
        CATCH
            NOP
        END TRY
        AppSettings.Active := oE
        oE:Apply()
        RETURN oE

    /// <summary>Save, if "Save Options" is switched on</summary>
    PUBLIC METHOD Save() AS VOID
        IF SELF:SaveOptions
            SELF:SaveAlways()
        ENDIF
        RETURN

    /// <summary>Always save (OK in the Set Defaults dialog)</summary>
    PUBLIC METHOD SaveAlways() AS VOID
        TRY
            LOCAL aRows := List<STRING>{} AS List<STRING>
            aRows:Add( "Driver=" + SELF:Driver )
            aRows:Add( "Exclusive=" + B( SELF:Exclusive ) )
            aRows:Add( "ReadOnly=" + B( SELF:ReadOnly ) )
            aRows:Add( "ShowRecno=" + B( SELF:ShowRecno ) )
            aRows:Add( "ShowDeleted=" + B( SELF:ShowDeleted ) )
            aRows:Add( "AutoCommit=" + B( SELF:AutoCommit ) )
            aRows:Add( "FullPath=" + B( SELF:FullPath ) )
            aRows:Add( "FontName=" + SELF:FontName )
            aRows:Add( "FontSize=" + SELF:FontSize:ToString( CultureInfo.InvariantCulture ) )
            aRows:Add( "FontStyle=" + SELF:FontStyleName:ToString() )
            aRows:Add( "DefaultPath=" + SELF:DefaultPath )
            aRows:Add( "Locking=" + SELF:Locking:ToString() )
            aRows:Add( "ShellMaximized=" + B( SELF:ShellMaximized ) )
            aRows:Add( "DataMaximized=" + B( SELF:DataMaximized ) )
            aRows:Add( "DateName=" + SELF:DateName )
            aRows:Add( "DateFormat=" + SELF:DateFormat )
            aRows:Add( "Century=" + B( SELF:Century ) )
            aRows:Add( "Epoch=" + SELF:Epoch:ToString() )
            aRows:Add( "ErrorLog=" + B( SELF:LogErrors ) )
            aRows:Add( "SaveOptions=" + B( SELF:SaveOptions ) )
            aRows:Add( "AskQuit=" + B( SELF:AskQuit ) )
            FOR VAR i := 0 TO SELF:Recent:Count - 1
                aRows:Add( "Recent" + Convert.ToString( i + 1 ) + "=" + SELF:Recent[i] )
            NEXT
            File.WriteAllLines( IniFile(), aRows:ToArray() )
        CATCH
            NOP
        END TRY
        RETURN

    /// <summary>Display font as Font object (the default font on error)</summary>
    PUBLIC METHOD GetFont() AS Font
        TRY
            RETURN Font{ SELF:FontName, SELF:FontSize, (FontStyle) SELF:FontStyleName }
        CATCH
            RETURN Font{ "Microsoft Sans Serif", 8.25 }
        END TRY

    // =====================================================================
    // Date (Set Defaults - Date)
    // =====================================================================
    /// <summary>Set the date format for the X# runtime too (filter expressions with CTOD/DTOC)</summary>
    PUBLIC METHOD Apply() AS VOID
        TRY
            SetDateFormat( SELF:DateFormat )
            SetEpoch( (DWORD) SELF:Epoch )
            SetCentury( SELF:DateFormat:Contains( "YYYY" ) )
        CATCH
            NOP
        END TRY
        RETURN

    /// <summary>Convert a VO format (DD.MM.YYYY) to a .NET pattern (dd.MM.yyyy)</summary>
    PUBLIC STATIC METHOD NetPattern( cVoFormat AS STRING ) AS STRING
        LOCAL c := cVoFormat:ToUpper() AS STRING
        c := c:Replace( "YYYY", "yyyy" ):Replace( "YY", "yy" ):Replace( "DD", "dd" )
        // '/' is a placeholder for the separator in .NET -> take it literally
        RETURN c:Replace( "/", "'/'" )

    PRIVATE STATIC METHOD Pattern() AS STRING
        IF AppSettings.Active == NULL
            RETURN "dd.MM.yyyy"
        ENDIF
        RETURN NetPattern( AppSettings.Active:DateFormat )

    /// <summary>Date for display in the configured format</summary>
    PUBLIC STATIC METHOD DateText( d AS DateTime ) AS STRING
        IF d == DateTime.MinValue
            RETURN ""
        ENDIF
        TRY
            RETURN d:ToString( Pattern(), CultureInfo.InvariantCulture )
        CATCH
            RETURN d:ToString( "dd.MM.yyyy", CultureInfo.InvariantCulture )
        END TRY

    /// <summary>Read input: configured format (2 or 4 digit year), plus DD.MM.YYYY and YYYYMMDD</summary>
    PUBLIC STATIC METHOD ParseDate( cText AS STRING ) AS DateTime
        LOCAL oCulture := (CultureInfo) CultureInfo.InvariantCulture:Clone() AS CultureInfo
        LOCAL nEpoch := IIF( AppSettings.Active == NULL, 1900, AppSettings.Active:Epoch ) AS INT
        TRY
            oCulture:DateTimeFormat:Calendar:TwoDigitYearMax := nEpoch + 99
        CATCH
            NOP
        END TRY
        LOCAL cM  := Pattern() AS STRING
        LOCAL cPattern2 := IIF( cM:Contains( "yyyy" ), cM:Replace( "yyyy", "yy" ), cM:Replace( "yy", "yyyy" ) ) AS STRING
        LOCAL cPattern3 := cM:Replace( "dd", "d" ):Replace( "MM", "M" ) AS STRING
        LOCAL cPattern4 := cPattern2:Replace( "dd", "d" ):Replace( "MM", "M" ) AS STRING
        RETURN DateTime.ParseExact( cText:Trim(), <STRING>{ cM, cPattern2, cPattern3, cPattern4, "dd.MM.yyyy", "d.M.yyyy", "dd.MM.yy", "d.M.yy", "yyyyMMdd" }, ;
            oCulture, DateTimeStyles.None )

    PUBLIC METHOD RememberFont( oFont AS Font ) AS VOID
        SELF:FontName    := oFont:Name
        SELF:FontSize := oFont:Size
        SELF:FontStyleName    := (INT) oFont:Style
        SELF:Save()
        RETURN

    PRIVATE STATIC METHOD B( l AS LOGIC ) AS STRING
        RETURN IIF( l, "1", "0" )

    /// <summary>Put the file at the top of the list of recently opened files (max. 10)</summary>
    PUBLIC METHOD RememberFile( cFile AS STRING, cMode AS STRING, cDriver AS STRING ) AS VOID
        FOR VAR i := SELF:Recent:Count - 1 DOWNTO 0
            LOCAL cEntry := SELF:Recent[i] AS STRING
            LOCAL nPos := cEntry:LastIndexOf( "|" ) AS INT
            IF nPos >= 0 .AND. String.Compare( cEntry:Substring( nPos + 1 ), cFile, TRUE ) == 0
                SELF:Recent:RemoveAt( i )
            ENDIF
        NEXT
        SELF:Recent:Insert( 0, cMode + "|" + cDriver + "|" + cFile )
        DO WHILE SELF:Recent:Count > 10
            SELF:Recent:RemoveAt( SELF:Recent:Count - 1 )
        ENDDO
        SELF:Save()
        RETURN

END CLASS


/// <summary>Clipboard for data records (Copy Record / Paste Append), based on field names</summary>
PUBLIC STATIC CLASS DbClip
    PUBLIC STATIC Records := List<Dictionary<STRING, OBJECT>>{} AS List<Dictionary<STRING, OBJECT>>
END CLASS

END NAMESPACE
