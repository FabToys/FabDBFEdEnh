USING System
USING System.IO
USING System.Drawing
USING System.Globalization
USING System.Collections.Generic
USING System.Windows.Forms

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>
/// Options - Set Defaults like in the dBAdministrator: tabs Database and Date,
/// below Set Error Log / Save Options / Confirm on Exit.
/// </summary>
PUBLIC CLASS SetDefaultsDialog INHERIT System.Windows.Forms.Form

    PRIVATE oSettings AS AppSettings
    // Database
    PRIVATE txtPath      AS TextBox
    PRIVATE cmbDriver    AS ComboBox
    PRIVATE cmbLocking   AS ComboBox
    PRIVATE chkCommit    AS CheckBox
    PRIVATE chkRecno     AS CheckBox
    PRIVATE chkDeleted   AS CheckBox
    PRIVATE chkPath      AS CheckBox
    PRIVATE chkShellMax  AS CheckBox
    PRIVATE chkDataMax  AS CheckBox
    PRIVATE chkExcl      AS CheckBox
    PRIVATE chkOnlyRead  AS CheckBox
    // Date
    PRIVATE aRadio       AS List<RadioButton>
    PRIVATE txtFormat    AS TextBox
    PRIVATE rbCentOn     AS RadioButton
    PRIVATE rbCentOff    AS RadioButton
    PRIVATE numEpoch    AS NumericUpDown
    PRIVATE txtExample  AS TextBox
    PRIVATE lFilling     AS LOGIC
    // below
    PRIVATE chkLog       AS CheckBox
    PRIVATE chkSave AS CheckBox
    PRIVATE chkQuit   AS CheckBox

    PRIVATE STATIC aDriverText := <STRING>{ "FoxPro - DBFCDX/FPT", "Clipper - DBFNTX/DBT", "Visual FoxPro - DBFVFP" } AS STRING[]
    PRIVATE STATIC aDriverRdd  := <STRING>{ "DBFCDX", "DBFNTX", "DBFVFP" } AS STRING[]
    // Date templates like in the dBAdministrator (basic form with 2-digit year)
    PRIVATE STATIC aDateName    := <STRING>{ "American", "ANSI", "British", "French", "German", "Italian", "Japanese", "USA" } AS STRING[]
    PRIVATE STATIC aDateFormat  := <STRING>{ "MM/DD/YY", "YY.MM.DD", "DD/MM/YY", "DD/MM/YY", "DD.MM.YY", "DD-MM-YY", "YY/MM/DD", "MM-DD-YY" } AS STRING[]

    PUBLIC CONSTRUCTOR( oE AS AppSettings )
        SELF:oSettings := oE
        SELF:Text            := "Set Defaults"
        SELF:FormBorderStyle := FormBorderStyle.FixedDialog
        SELF:StartPosition   := FormStartPosition.CenterParent
        SELF:MaximizeBox     := FALSE
        SELF:MinimizeBox     := FALSE
        SELF:ShowInTaskbar   := FALSE
        SELF:Font            := Font{ "Microsoft Sans Serif", 8.25 }
        SELF:ClientSize      := Size{ 520, 420 }

        LOCAL oTabs := TabControl{} AS TabControl
        oTabs:Location := Point{ 10, 10 }
        oTabs:Size     := Size{ 500, 330 }
        LOCAL tpDatabase  := TabPage{ "Database" } AS TabPage
        LOCAL tpDate := TabPage{ "Date" } AS TabPage
        oTabs:TabPages:Add( tpDatabase )
        oTabs:TabPages:Add( tpDate )
        SELF:BuildDatabase( tpDatabase )
        SELF:BuildDate( tpDate )

        SELF:chkLog       := SELF:MakeCheckBox( SELF, "Set Error Log", 30, 352, oE:LogErrors )
        SELF:chkSave := SELF:MakeCheckBox( SELF, "Save Options", 190, 352, oE:SaveOptions )
        SELF:chkQuit   := SELF:MakeCheckBox( SELF, "Confirm on Exit", 350, 352, oE:AskQuit )

        LOCAL btnOk := Button{} AS Button
        btnOk:Text := "OK"
        btnOk:Location := Point{ 170, 384 }
        btnOk:Size := Size{ 85, 25 }
        btnOk:Click += EventHandler{ SELF, @Ok_Click() }
        LOCAL btnCancel := Button{} AS Button
        btnCancel:Text := "Cancel"
        btnCancel:Location := Point{ 265, 384 }
        btnCancel:Size := Size{ 85, 25 }
        btnCancel:DialogResult := DialogResult.Cancel
        SELF:AcceptButton := btnOk
        SELF:CancelButton := btnCancel
        SELF:Controls:Add( oTabs )
        SELF:Controls:Add( btnOk )
        SELF:Controls:Add( btnCancel )
        RETURN

    PRIVATE METHOD MakeCheckBox( oParent AS Control, cText AS STRING, nX AS INT, nY AS INT, lValue AS LOGIC ) AS CheckBox
        LOCAL oCheck := CheckBox{} AS CheckBox
        oCheck:Text     := cText
        oCheck:Location := Point{ nX, nY }
        oCheck:AutoSize := TRUE
        oCheck:Checked  := lValue
        oParent:Controls:Add( oCheck )
        RETURN oCheck

    PRIVATE METHOD MakeLabel( oParent AS Control, cText AS STRING, nX AS INT, nY AS INT ) AS VOID
        LOCAL oLabel := Label{} AS Label
        oLabel:Text := cText
        oLabel:Location := Point{ nX, nY }
        oLabel:AutoSize := TRUE
        oParent:Controls:Add( oLabel )
        RETURN

    // ---------------------------------------------------------------------
    // Register Database
    // ---------------------------------------------------------------------
    PRIVATE METHOD BuildDatabase( tp AS TabPage ) AS VOID
        LOCAL oE := SELF:oSettings AS AppSettings
        SELF:MakeLabel( tp, "Default Path:", 12, 12 )
        SELF:txtPath := TextBox{}
        SELF:txtPath:Location := Point{ 12, 30 }
        SELF:txtPath:Size := Size{ 200, 20 }
        SELF:txtPath:Text := oE:DefaultPath
        tp:Controls:Add( SELF:txtPath )
        LOCAL btnPath := Button{} AS Button
        btnPath:Text := "..."
        btnPath:Location := Point{ 216, 29 }
        btnPath:Size := Size{ 30, 22 }
        btnPath:Click += EventHandler{ SELF, @Path_Click() }
        tp:Controls:Add( btnPath )

        SELF:MakeLabel( tp, "Driver:", 12, 66 )
        SELF:cmbDriver := ComboBox{}
        SELF:cmbDriver:DropDownStyle := ComboBoxStyle.DropDownList
        SELF:cmbDriver:Location := Point{ 12, 84 }
        SELF:cmbDriver:Size := Size{ 234, 21 }
        SELF:cmbDriver:Items:AddRange( <OBJECT>{ aDriverText[1], aDriverText[2], aDriverText[3] } )
        SELF:cmbDriver:SelectedIndex := 0
        FOR VAR i := 1 TO aDriverRdd:Length
            IF String.Compare( aDriverRdd[i], oE:Driver, TRUE ) == 0
                SELF:cmbDriver:SelectedIndex := i - 1
            ENDIF
        NEXT
        tp:Controls:Add( SELF:cmbDriver )

        SELF:MakeLabel( tp, "Locking:", 12, 118 )
        SELF:cmbLocking := ComboBox{}
        SELF:cmbLocking:DropDownStyle := ComboBoxStyle.DropDownList
        SELF:cmbLocking:Location := Point{ 12, 136 }
        SELF:cmbLocking:Size := Size{ 234, 21 }
        SELF:cmbLocking:Items:AddRange( <OBJECT>{ "Automatic", "Manual" } )
        SELF:cmbLocking:SelectedIndex := IIF( oE:Locking == 1, 1, 0 )
        tp:Controls:Add( SELF:cmbLocking )

        LOCAL nY := 14 AS INT
        SELF:chkCommit   := SELF:MakeCheckBox( tp, "Auto Commit Browser Updates",     262, nY, oE:AutoCommit )      ; nY += 26
        SELF:chkRecno    := SELF:MakeCheckBox( tp, "Show Record Number Column",       262, nY, oE:ShowRecno )      ; nY += 26
        SELF:chkDeleted  := SELF:MakeCheckBox( tp, "Show Deleted Records Column",     262, nY, oE:ShowDeleted ) ; nY += 26
        SELF:chkPath     := SELF:MakeCheckBox( tp, "Show Full Path in Window Caption", 262, nY, oE:FullPath )     ; nY += 26
        SELF:chkShellMax := SELF:MakeCheckBox( tp, "Open Shell Window Maximised",     262, nY, oE:ShellMaximized )  ; nY += 26
        SELF:chkDataMax := SELF:MakeCheckBox( tp, "Open DataWin Maximised",          262, nY, oE:DataMaximized )  ; nY += 26
        SELF:chkExcl     := SELF:MakeCheckBox( tp, "Open in Exclusive Mode",          262, nY, oE:Exclusive )        ; nY += 26
        SELF:chkOnlyRead := SELF:MakeCheckBox( tp, "Open Read Only",                  262, nY, oE:ReadOnly )
        RETURN

    PRIVATE METHOD Path_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL dlg := FolderBrowserDialog{} AS FolderBrowserDialog
        dlg:Description := "Default folder for Open DBF"
        IF SELF:txtPath:Text:Length > 0 .AND. Directory.Exists( SELF:txtPath:Text )
            dlg:SelectedPath := SELF:txtPath:Text
        ENDIF
        IF dlg:ShowDialog( SELF ) == DialogResult.OK
            SELF:txtPath:Text := dlg:SelectedPath
        ENDIF
        RETURN

    // ---------------------------------------------------------------------
    // Register Date
    // ---------------------------------------------------------------------
    PRIVATE METHOD BuildDate( tp AS TabPage ) AS VOID
        LOCAL oE := SELF:oSettings AS AppSettings
        SELF:lFilling := TRUE

        LOCAL gbFormat := GroupBox{} AS GroupBox
        gbFormat:Text := "Display Format"
        gbFormat:Location := Point{ 10, 8 }
        gbFormat:Size := Size{ 230, 280 }
        tp:Controls:Add( gbFormat )
        SELF:aRadio := List<RadioButton>{}
        FOR VAR i := 1 TO aDateName:Length
            LOCAL rb := RadioButton{} AS RadioButton
            rb:Text := aDateName[i]:PadRight( 10 ) + " -  " + aDateFormat[i]
            rb:Tag := i
            rb:Location := Point{ 14, 22 + ( i - 1 ) * 31 }
            rb:Size := Size{ 205, 22 }
            rb:Checked := String.Compare( oE:DateName, aDateName[i], TRUE ) == 0
            rb:CheckedChanged += EventHandler{ SELF, @Template_Changed() }
            gbFormat:Controls:Add( rb )
            SELF:aRadio:Add( rb )
        NEXT

        LOCAL gbCustom := GroupBox{} AS GroupBox
        gbCustom:Text := "Custom Format"
        gbCustom:Location := Point{ 252, 8 }
        gbCustom:Size := Size{ 230, 56 }
        tp:Controls:Add( gbCustom )
        SELF:txtFormat := TextBox{}
        SELF:txtFormat:Location := Point{ 12, 22 }
        SELF:txtFormat:Size := Size{ 140, 20 }
        SELF:txtFormat:CharacterCasing := CharacterCasing.Upper
        SELF:txtFormat:Text := oE:DateFormat
        gbCustom:Controls:Add( SELF:txtFormat )
        LOCAL btnSet := Button{} AS Button
        btnSet:Text := "Set"
        btnSet:Location := Point{ 158, 20 }
        btnSet:Size := Size{ 60, 23 }
        btnSet:Click += EventHandler{ SELF, @Set_Click() }
        gbCustom:Controls:Add( btnSet )

        LOCAL gbCentury := GroupBox{} AS GroupBox
        gbCentury:Text := "Century"
        gbCentury:Location := Point{ 252, 72 }
        gbCentury:Size := Size{ 230, 74 }
        tp:Controls:Add( gbCentury )
        SELF:rbCentOn := RadioButton{}
        SELF:rbCentOn:Text := "On   -  YYYY"
        SELF:rbCentOn:Location := Point{ 14, 20 }
        SELF:rbCentOn:AutoSize := TRUE
        SELF:rbCentOff := RadioButton{}
        SELF:rbCentOff:Text := "Off  -  YY"
        SELF:rbCentOff:Location := Point{ 14, 46 }
        SELF:rbCentOff:AutoSize := TRUE
        SELF:rbCentOn:Checked  := oE:DateFormat:Contains( "YYYY" )
        SELF:rbCentOff:Checked := ! SELF:rbCentOn:Checked
        SELF:rbCentOn:CheckedChanged += EventHandler{ SELF, @Century_Changed() }
        gbCentury:Controls:Add( SELF:rbCentOn )
        gbCentury:Controls:Add( SELF:rbCentOff )

        LOCAL gbEpoch := GroupBox{} AS GroupBox
        gbEpoch:Text := "Epoch"
        gbEpoch:Location := Point{ 252, 154 }
        gbEpoch:Size := Size{ 230, 52 }
        tp:Controls:Add( gbEpoch )
        SELF:numEpoch := NumericUpDown{}
        SELF:numEpoch:Location := Point{ 12, 20 }
        SELF:numEpoch:Size := Size{ 80, 20 }
        SELF:numEpoch:Minimum := 1000
        SELF:numEpoch:Maximum := 2900
        SELF:numEpoch:Value := oE:Epoch
        gbEpoch:Controls:Add( SELF:numEpoch )

        LOCAL gbExample := GroupBox{} AS GroupBox
        gbExample:Text := "Example"
        gbExample:Location := Point{ 252, 214 }
        gbExample:Size := Size{ 230, 52 }
        tp:Controls:Add( gbExample )
        SELF:txtExample := TextBox{}
        SELF:txtExample:Location := Point{ 12, 20 }
        SELF:txtExample:Size := Size{ 205, 20 }
        SELF:txtExample:ReadOnly := TRUE
        gbExample:Controls:Add( SELF:txtExample )

        SELF:txtFormat:TextChanged += EventHandler{ SELF, @Format_Changed() }
        SELF:lFilling := FALSE
        SELF:ShowExample()
        RETURN

    // Template chosen -> format (with/without century) into the Custom Format field
    PRIVATE METHOD Template_Changed( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL rb := (RadioButton) sender AS RadioButton
        IF SELF:lFilling .OR. ! rb:Checked
            RETURN
        ENDIF
        LOCAL cF := aDateFormat[ (INT) rb:Tag ] AS STRING
        IF SELF:rbCentOn:Checked
            cF := cF:Replace( "YY", "YYYY" )
        ENDIF
        SELF:lFilling := TRUE
        SELF:txtFormat:Text := cF
        SELF:lFilling := FALSE
        SELF:ShowExample()
        RETURN

    // Toggle century: YY <-> YYYY in the current format
    PRIVATE METHOD Century_Changed( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:lFilling
            RETURN
        ENDIF
        LOCAL cF := SELF:txtFormat:Text:Replace( "YYYY", "YY" ) AS STRING
        IF SELF:rbCentOn:Checked
            cF := cF:Replace( "YY", "YYYY" )
        ENDIF
        SELF:lFilling := TRUE
        SELF:txtFormat:Text := cF
        SELF:lFilling := FALSE
        SELF:ShowExample()
        RETURN

    // own format by hand: no template marked any more
    PRIVATE METHOD Format_Changed( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:lFilling
            RETURN
        ENDIF
        SELF:ShowExample()
        RETURN

    PRIVATE METHOD Set_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF ! SELF:IsFormatValid( SELF:txtFormat:Text )
            MessageBox.Show( "The format needs DD, MM and YY or YYYY, e.g. DD.MM.YYYY", "Custom Format", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN
        ENDIF
        SELF:lFilling := TRUE
        FOREACH rb AS RadioButton IN SELF:aRadio
            rb:Checked := FALSE
        NEXT
        SELF:rbCentOn:Checked  := SELF:txtFormat:Text:Contains( "YYYY" )
        SELF:rbCentOff:Checked := ! SELF:rbCentOn:Checked
        SELF:lFilling := FALSE
        SELF:ShowExample()
        RETURN

    PRIVATE METHOD IsFormatValid( cF AS STRING ) AS LOGIC
        cF := cF:ToUpper():Trim()
        RETURN cF:Contains( "DD" ) .AND. cF:Contains( "MM" ) .AND. cF:Contains( "YY" ) .AND. cF:Length <= 12

    PRIVATE METHOD ShowExample() AS VOID
        TRY
            IF SELF:IsFormatValid( SELF:txtFormat:Text )
                SELF:txtExample:Text := DateTime.Today:ToString( AppSettings.NetPattern( SELF:txtFormat:Text ), CultureInfo.InvariantCulture )
            ELSE
                SELF:txtExample:Text := "(invalid format)"
            ENDIF
        CATCH
            SELF:txtExample:Text := "(invalid format)"
        END TRY
        RETURN

    // ---------------------------------------------------------------------
    // OK: take over the values and save
    // ---------------------------------------------------------------------
    PRIVATE METHOD Ok_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL cFormat := SELF:txtFormat:Text:ToUpper():Trim() AS STRING
        IF ! SELF:IsFormatValid( cFormat )
            MessageBox.Show( "The date format needs DD, MM and YY or YYYY, e.g. DD.MM.YYYY", "Set Defaults", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN
        ENDIF
        LOCAL cPath := SELF:txtPath:Text:Trim() AS STRING
        IF cPath:Length > 0 .AND. ! Directory.Exists( cPath )
            MessageBox.Show( "The folder does not exist: " + cPath, "Set Defaults", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN
        ENDIF
        LOCAL oE := SELF:oSettings AS AppSettings
        oE:DefaultPath    := cPath
        oE:Driver          := aDriverRdd[ SELF:cmbDriver:SelectedIndex + 1 ]
        oE:Locking         := SELF:cmbLocking:SelectedIndex
        oE:AutoCommit      := SELF:chkCommit:Checked
        oE:ShowRecno      := SELF:chkRecno:Checked
        oE:ShowDeleted := SELF:chkDeleted:Checked
        oE:FullPath      := SELF:chkPath:Checked
        oE:ShellMaximized  := SELF:chkShellMax:Checked
        oE:DataMaximized  := SELF:chkDataMax:Checked
        oE:Exclusive        := SELF:chkExcl:Checked
        oE:ReadOnly        := SELF:chkOnlyRead:Checked
        oE:DateFormat    := cFormat
        oE:DateName      := ""
        FOREACH rb AS RadioButton IN SELF:aRadio
            IF rb:Checked
                oE:DateName := aDateName[ (INT) rb:Tag ]
            ENDIF
        NEXT
        oE:Century     := cFormat:Contains( "YYYY" )
        oE:Epoch          := (INT) SELF:numEpoch:Value
        oE:LogErrors       := SELF:chkLog:Checked
        oE:SaveOptions := SELF:chkSave:Checked
        oE:AskQuit   := SELF:chkQuit:Checked
        oE:Apply()
        oE:SaveAlways()
        SELF:DialogResult := DialogResult.OK
        SELF:Close()
        RETURN

END CLASS


/// <summary>View - Select Fields: choose the visible columns of the data window</summary>
PUBLIC CLASS FieldsDialog INHERIT System.Windows.Forms.Form

    PRIVATE lst AS CheckedListBox

    PUBLIC CONSTRUCTOR( aNames AS List<STRING>, aVisible AS List<LOGIC> )
        SELF:Text            := "Select Fields"
        SELF:FormBorderStyle := FormBorderStyle.FixedDialog
        SELF:StartPosition   := FormStartPosition.CenterParent
        SELF:MaximizeBox     := FALSE
        SELF:MinimizeBox     := FALSE
        SELF:ShowInTaskbar   := FALSE
        SELF:Font            := Font{ "Microsoft Sans Serif", 8.25 }
        SELF:ClientSize      := Size{ 300, 400 }

        SELF:lst := CheckedListBox{}
        SELF:lst:Location := Point{ 10, 10 }
        SELF:lst:Size := Size{ 190, 380 }
        SELF:lst:CheckOnClick := TRUE
        SELF:lst:IntegralHeight := FALSE
        FOR VAR i := 0 TO aNames:Count - 1
            SELF:lst:Items:Add( aNames[i], aVisible[i] )
        NEXT

        LOCAL btnAll := SELF:MakeButton( "All", 10 ) AS Button
        btnAll:Click += EventHandler{ SELF, @All_Click() }
        LOCAL btnNone := SELF:MakeButton( "None", 40 ) AS Button
        btnNone:Click += EventHandler{ SELF, @None_Click() }
        LOCAL btnOk := SELF:MakeButton( "OK", 330 ) AS Button
        btnOk:Click += EventHandler{ SELF, @Ok_Click() }
        LOCAL btnCancel := SELF:MakeButton( "Cancel", 362 ) AS Button
        btnCancel:DialogResult := DialogResult.Cancel
        SELF:AcceptButton := btnOk
        SELF:CancelButton := btnCancel
        SELF:Controls:Add( SELF:lst )
        RETURN

    PRIVATE METHOD MakeButton( cText AS STRING, nY AS INT ) AS Button
        LOCAL oButton := Button{} AS Button
        oButton:Text := cText
        oButton:Location := Point{ 210, nY }
        oButton:Size := Size{ 80, 25 }
        SELF:Controls:Add( oButton )
        RETURN oButton

    PRIVATE METHOD All_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        FOR VAR i := 0 TO SELF:lst:Items:Count - 1
            SELF:lst:SetItemChecked( i, TRUE )
        NEXT
        RETURN

    PRIVATE METHOD None_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        FOR VAR i := 0 TO SELF:lst:Items:Count - 1
            SELF:lst:SetItemChecked( i, FALSE )
        NEXT
        RETURN

    PRIVATE METHOD Ok_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:lst:CheckedItems:Count == 0
            MessageBox.Show( "At least one field must remain visible.", "Select Fields" )
            RETURN
        ENDIF
        SELF:DialogResult := DialogResult.OK
        SELF:Close()
        RETURN

    PUBLIC METHOD IsFieldVisible( nIdx AS INT ) AS LOGIC
        RETURN SELF:lst:GetItemChecked( nIdx )

END CLASS

END NAMESPACE
