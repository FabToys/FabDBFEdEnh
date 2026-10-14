USING System
USING System.IO
USING System.Drawing
USING System.Drawing.Drawing2D
USING System.Collections.Generic
USING System.Windows.Forms

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>MDI main window in the style of the dBAdministrator</summary>
PUBLIC CLASS MainForm INHERIT System.Windows.Forms.Form

    PRIVATE oSettings     AS AppSettings
    PRIVATE oMenu      AS MenuStrip
    PRIVATE mDatabase  AS ToolStripMenuItem
    PRIVATE mWindow    AS ToolStripMenuItem
    PRIVATE mShowRecno AS ToolStripMenuItem
    PRIVATE mShowDeleted   AS ToolStripMenuItem
    PRIVATE mOnlyDeleted    AS ToolStripMenuItem
    PRIVATE mAutoCommit AS ToolStripMenuItem
    PRIVATE mFullPath AS ToolStripMenuItem
    PRIVATE oMdiClient AS MdiClient

    PUBLIC CONSTRUCTOR()
        SELF:oSettings := AppSettings.LoadSettings()

        SELF:Text           := "FabDBFEdEnh - dbManager"
        SELF:IsMdiContainer := TRUE
        SELF:Size           := Size{ 1100, 750 }
        SELF:StartPosition  := FormStartPosition.CenterScreen
        SELF:Font           := Font{ "Microsoft Sans Serif", 8.25 }

        // first the toolbar, then the menu: the dock element added last lies on top
        SELF:BuildToolbar()
        SELF:BuildMenu()

        // MDI background with a colour gradient (like dBAdministrator)
        FOREACH oCtl AS Control IN SELF:Controls
            IF oCtl IS MdiClient
                SELF:oMdiClient := (MdiClient) oCtl
                SELF:oMdiClient:Paint  += PaintEventHandler{ SELF, @Mdi_Paint() }
                SELF:oMdiClient:Resize += EventHandler{ SELF, @Mdi_Resize() }
            ENDIF
        NEXT

        IF SELF:oSettings:ShellMaximized
            SELF:WindowState := FormWindowState.Maximized
        ENDIF
        SELF:Shown            += EventHandler{ SELF, @Window_Shown() }
        SELF:MdiChildActivate += EventHandler{ SELF, @Child_Activated() }
        SELF:FormClosing      += FormClosingEventHandler{ SELF, @Window_Closing() }
        RETURN

    // =====================================================================
    // Menu
    // =====================================================================
    PRIVATE STATIC METHOD KeyOf( k AS Keys, lCtrl AS LOGIC, lOld AS LOGIC, lShift AS LOGIC ) AS Keys
        LOCAL n := (INT) k AS INT
        IF lCtrl
            n += (INT) Keys.Control
        ENDIF
        IF lOld
            n += (INT) Keys.Alt
        ENDIF
        IF lShift
            n += (INT) Keys.Shift
        ENDIF
        RETURN (Keys) n

    PRIVATE METHOD Entry( oMenu AS ToolStripMenuItem, cText AS STRING, nKey AS Keys, oHandler AS EventHandler ) AS ToolStripMenuItem
        LOCAL oItem := ToolStripMenuItem{ cText } AS ToolStripMenuItem
        IF nKey != Keys.None
            TRY
                oItem:ShortcutKeys := nKey
            CATCH
                NOP     // invalid combination -> without keyboard shortcut
            END TRY
        ENDIF
        IF oHandler == NULL
            oItem:Enabled := FALSE      // follows in a later stage
        ELSE
            oItem:Click += oHandler
        ENDIF
        oMenu:DropDownItems:Add( oItem )
        RETURN oItem

    PRIVATE METHOD AddSeparator( oMenu AS ToolStripMenuItem ) AS VOID
        oMenu:DropDownItems:Add( ToolStripSeparator{} )
        RETURN

    PRIVATE METHOD BuildMenu() AS VOID
        LOCAL m AS ToolStripMenuItem
        SELF:oMenu := MenuStrip{}

        // --- Database ---
        SELF:mDatabase := ToolStripMenuItem{ "&Database" }
        SELF:oMenu:Items:Add( SELF:mDatabase )
        SELF:BuildDatabaseMenu()

        // --- Index ---
        m := ToolStripMenuItem{ "&Index" }
        SELF:oMenu:Items:Add( m )
        SELF:Entry( m, "Open Index File",        Keys.None, EventHandler{ SELF, @M_OpenIndex() } )
        SELF:Entry( m, "Index Manager",          Keys.None, EventHandler{ SELF, @M_IndexManager() } )
        SELF:Entry( m, "Close All Index Orders", Keys.None, EventHandler{ SELF, @M_CloseIndex() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "New Order...",           Keys.None, EventHandler{ SELF, @M_IndexManager() } )
        SELF:Entry( m, "Delete Order",           Keys.None, EventHandler{ SELF, @M_IndexManager() } )
        SELF:Entry( m, "Set Active Order",       Keys.None, EventHandler{ SELF, @M_SelectOrder() } )
        SELF:Entry( m, "ReIndex",                Keys.None, EventHandler{ SELF, @M_ReIndex() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Seek Index Value",       KeyOf( Keys.S, TRUE, FALSE, FALSE ), EventHandler{ SELF, @M_Search() } )

        // --- Record ---
        m := ToolStripMenuItem{ "&Record" }
        SELF:oMenu:Items:Add( m )
        SELF:Entry( m, "Append Record",              Keys.Insert,                            EventHandler{ SELF, @M_Append() } )
        SELF:Entry( m, "Delete Record",              KeyOf( Keys.D, TRUE, FALSE, FALSE ),    EventHandler{ SELF, @M_Delete() } )
        SELF:Entry( m, "Scoped Delete",              Keys.None,                              EventHandler{ SELF, @M_DeleteScoped() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Recall Deleted Record",      KeyOf( Keys.R, TRUE, FALSE, FALSE ),    EventHandler{ SELF, @M_Recall() } )
        SELF:Entry( m, "Recall All Deleted Records", KeyOf( Keys.R, TRUE, TRUE, FALSE ),     EventHandler{ SELF, @M_RecallAll() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Go To Top",                  KeyOf( Keys.Home, TRUE, FALSE, FALSE ), EventHandler{ SELF, @M_Top() } )
        SELF:Entry( m, "Previous",                   Keys.None,                              EventHandler{ SELF, @M_Prev() } )
        SELF:Entry( m, "Next",                       Keys.None,                              EventHandler{ SELF, @M_Next() } )
        SELF:Entry( m, "Go To Bottom",               KeyOf( Keys.End, TRUE, FALSE, FALSE ),  EventHandler{ SELF, @M_Bottom() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Goto RecNo",                 KeyOf( Keys.G, TRUE, FALSE, FALSE ),    EventHandler{ SELF, @M_Goto() } )
        SELF:Entry( m, "Find Record",                KeyOf( Keys.F, TRUE, FALSE, FALSE ),    EventHandler{ SELF, @M_Search() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Refresh",                    Keys.F5,                                EventHandler{ SELF, @M_Refresh() } )
        SELF:Entry( m, "Undo Changes",               KeyOf( Keys.Z, TRUE, FALSE, FALSE ),    EventHandler{ SELF, @M_Undo() } )
        SELF:Entry( m, "Commit Changes",             Keys.F12,                               EventHandler{ SELF, @M_Commit() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Hex View",                   Keys.None,                              EventHandler{ SELF, @M_Hex() } )

        // --- View ---
        m := ToolStripMenuItem{ "&View" }
        SELF:oMenu:Items:Add( m )
        SELF:Entry( m, "Form",   KeyOf( Keys.F2, FALSE, FALSE, TRUE ), EventHandler{ SELF, @M_Form() } )
        SELF:Entry( m, "Browse", Keys.F2,                              EventHandler{ SELF, @M_Browse() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Set Filter",      Keys.None, EventHandler{ SELF, @M_Filter() } )
        SELF:Entry( m, "Set Order Scope", Keys.None, EventHandler{ SELF, @M_Scope() } )
        SELF:mOnlyDeleted := SELF:Entry( m, "View Deleted Records Only", Keys.None, EventHandler{ SELF, @M_OnlyDeleted() } )
        SELF:Entry( m, "View All Records", Keys.None, EventHandler{ SELF, @M_AllRecords() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Select Fields...", Keys.None, EventHandler{ SELF, @M_Fields() } )

        // --- DBClipboard ---
        m := ToolStripMenuItem{ "DB&Clipboard" }
        SELF:oMenu:Items:Add( m )
        SELF:Entry( m, "Copy Record",          KeyOf( Keys.C, TRUE, FALSE, FALSE ), EventHandler{ SELF, @M_Copy() } )
        SELF:Entry( m, "Copy Record Additive", KeyOf( Keys.C, TRUE, TRUE, FALSE ),  EventHandler{ SELF, @M_CopyAdd() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Cut Record",           KeyOf( Keys.X, TRUE, FALSE, FALSE ), EventHandler{ SELF, @M_Cut() } )
        SELF:Entry( m, "Cut Record Additive",  KeyOf( Keys.X, TRUE, TRUE, FALSE ),  EventHandler{ SELF, @M_CutAdd() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Paste",                KeyOf( Keys.V, TRUE, FALSE, FALSE ), EventHandler{ SELF, @M_Paste() } )
        SELF:Entry( m, "Paste Append",         KeyOf( Keys.A, TRUE, TRUE, FALSE ),  EventHandler{ SELF, @M_PasteAppend() } )
        SELF:Entry( m, "Paste Append All",     KeyOf( Keys.L, TRUE, TRUE, FALSE ),  EventHandler{ SELF, @M_PasteAppendAll() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "View",  Keys.None, EventHandler{ SELF, @M_ClipView() } )
        SELF:Entry( m, "Link",  Keys.None, NULL )
        SELF:Entry( m, "Clear", Keys.None, EventHandler{ SELF, @M_ClipClear() } )

        // --- Utils (follows in stage 3/5) ---
        m := ToolStripMenuItem{ "&Utils" }
        SELF:oMenu:Items:Add( m )
        FOREACH cText AS STRING IN <STRING>{ "Associate", "DBCalc", "DBRegEx" }
            SELF:Entry( m, cText, Keys.None, NULL )
        NEXT
        SELF:Entry( m, "DBReplace", Keys.None, EventHandler{ SELF, @M_Replace() } )
        FOREACH cText AS STRING IN <STRING>{ "DBSort", "DBTotal", "DBValidation" }
            SELF:Entry( m, cText, Keys.None, NULL )
        NEXT
        SELF:Entry( m, "Pack", Keys.None, EventHandler{ SELF, @M_Pack() } )
        SELF:Entry( m, "Record Count", Keys.None, EventHandler{ SELF, @M_RecordCount() } )
        FOREACH cText AS STRING IN <STRING>{ "Set Relation", "Set Window Relation" }
            SELF:Entry( m, cText, Keys.None, NULL )
        NEXT
        SELF:Entry( m, "Zap", Keys.None, EventHandler{ SELF, @M_Zap() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "FPT Analysis (memo file)", Keys.None, EventHandler{ SELF, @M_Fpt() } )
        SELF:Entry( m, "Export JSON...",         Keys.None, EventHandler{ SELF, @M_ExportJson() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Text File Editor",       Keys.None, NULL )
        SELF:Entry( m, "Open Database List",     Keys.None, NULL )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Generate Create PRG...", Keys.None, EventHandler{ SELF, @M_GenCreate() } )
        SELF:Entry( m, "Generate DBF Desc File...", Keys.None, EventHandler{ SELF, @M_GenDesc() } )

        // --- Options ---
        m := ToolStripMenuItem{ "&Options" }
        SELF:oMenu:Items:Add( m )
        SELF:mShowRecno  := SELF:Entry( m, "Show RecNo",                  Keys.None, EventHandler{ SELF, @M_ShowRecno() } )
        SELF:mShowDeleted    := SELF:Entry( m, "Show Deleted",                Keys.None, EventHandler{ SELF, @M_ShowDeleted() } )
        SELF:mAutoCommit := SELF:Entry( m, "Auto Commit Browser Updates", Keys.None, EventHandler{ SELF, @M_AutoCommit() } )
        SELF:mFullPath := SELF:Entry( m, "Show Full Path in Window Caption", Keys.None, EventHandler{ SELF, @M_FullPath() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Set Display Font", Keys.None, EventHandler{ SELF, @M_GetFont() } )
        SELF:Entry( m, "Set Defaults",     Keys.None, EventHandler{ SELF, @M_Defaults() } )
        SELF:UpdateChecks()

        // --- Window ---
        SELF:mWindow := ToolStripMenuItem{ "&Window" }
        SELF:oMenu:Items:Add( SELF:mWindow )
        SELF:Entry( SELF:mWindow, "Cascade",         Keys.None, EventHandler{ SELF, @M_Cascade() } )
        SELF:Entry( SELF:mWindow, "Tile Vertical",   Keys.None, EventHandler{ SELF, @M_TileV() } )
        SELF:Entry( SELF:mWindow, "Tile Horizontal", Keys.None, EventHandler{ SELF, @M_TileH() } )
        SELF:Entry( SELF:mWindow, "Close All",       Keys.None, EventHandler{ SELF, @M_CloseAll() } )
        SELF:oMenu:MdiWindowListItem := SELF:mWindow

        // --- Help ---
        m := ToolStripMenuItem{ "&Help" }
        SELF:oMenu:Items:Add( m )
        SELF:Entry( m, "About", Keys.None, EventHandler{ SELF, @M_About() } )

        SELF:MainMenuStrip := SELF:oMenu
        SELF:Controls:Add( SELF:oMenu )
        RETURN

    // Database menu including the list of recently opened files (rebuilt after every open)
    PRIVATE METHOD BuildDatabaseMenu() AS VOID
        LOCAL m := SELF:mDatabase AS ToolStripMenuItem
        m:DropDownItems:Clear()
        SELF:Entry( m, "Open DBF...",      KeyOf( Keys.O, TRUE, FALSE, FALSE ), EventHandler{ SELF, @M_OpenFile() } )
        SELF:Entry( m, "New...",           KeyOf( Keys.N, TRUE, FALSE, FALSE ), EventHandler{ SELF, @M_New() } )
        SELF:Entry( m, "Modify Structure", Keys.None,                           EventHandler{ SELF, @M_Structure() } )
        SELF:AddSeparator( m )
        SELF:Entry( m, "Favorites",        Keys.None, NULL )
        IF SELF:oSettings:Recent:Count > 0
            SELF:AddSeparator( m )
            FOR VAR i := 0 TO SELF:oSettings:Recent:Count - 1
                LOCAL cEntry := SELF:oSettings:Recent[i] AS STRING
                LOCAL aParts   := cEntry:Split( <CHAR>{ c'|' } ) AS STRING[]
                LOCAL cPath    := cEntry:Substring( cEntry:LastIndexOf( "|" ) + 1 ) AS STRING
                LOCAL cMode   := (STRING) aParts:GetValue( 0 ) AS STRING
                LOCAL oItem    := SELF:Entry( m, Convert.ToString( i + 1 ) + " " + cPath:ToUpper() + " - " + cMode, Keys.None, ;
                                                EventHandler{ SELF, @M_Recent() } ) AS ToolStripMenuItem
                oItem:Tag := cEntry
            NEXT
        ENDIF
        SELF:AddSeparator( m )
        SELF:Entry( m, "Exit", Keys.None, EventHandler{ SELF, @M_Exit() } ):ShortcutKeyDisplayString := "ALT+F4"
        RETURN

    PRIVATE METHOD UpdateChecks() AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            SELF:mShowRecno:Checked := oDW:ShowsRecno
            SELF:mShowDeleted:Checked   := oDW:ShowsDeleted
            SELF:mOnlyDeleted:Checked    := oDW:ShowsOnlyDeleted
            SELF:mAutoCommit:Checked := oDW:AutoCommit
        ELSE
            SELF:mShowRecno:Checked := SELF:oSettings:ShowRecno
            SELF:mShowDeleted:Checked   := SELF:oSettings:ShowDeleted
            SELF:mOnlyDeleted:Checked    := FALSE
            SELF:mAutoCommit:Checked := SELF:oSettings:AutoCommit
        ENDIF
        SELF:mFullPath:Checked := SELF:oSettings:FullPath
        RETURN

    PRIVATE METHOD BuildToolbar() AS VOID
        LOCAL ts := ToolStrip{} AS ToolStrip
        ts:GripStyle := ToolStripGripStyle.Hidden
        ts:Items:Add( SELF:MakeButton( "Open",  "Open DBF (Ctrl+O)", EventHandler{ SELF, @M_OpenFile() } ) )
        ts:Items:Add( SELF:MakeButton( "New",   "New DBF (Ctrl+N)",    EventHandler{ SELF, @M_New() } ) )
        ts:Items:Add( ToolStripSeparator{} )
        ts:Items:Add( SELF:MakeButton( "||",    "Tile Vertical",        EventHandler{ SELF, @M_TileV() } ) )
        ts:Items:Add( SELF:MakeButton( "=",     "Tile Horizontal",      EventHandler{ SELF, @M_TileH() } ) )
        ts:Items:Add( ToolStripSeparator{} )
        ts:Items:Add( SELF:MakeButton( "?",     "About",                EventHandler{ SELF, @M_About() } ) )
        SELF:Controls:Add( ts )
        RETURN

    PRIVATE METHOD MakeButton( cText AS STRING, cTip AS STRING, oHandler AS EventHandler ) AS ToolStripButton
        LOCAL oButton := ToolStripButton{ cText } AS ToolStripButton
        oButton:DisplayStyle := ToolStripItemDisplayStyle.Text
        oButton:ToolTipText  := cTip
        oButton:Click += oHandler
        RETURN oButton

    // =====================================================================
    // Background
    // =====================================================================
    PRIVATE METHOD Mdi_Paint( sender AS OBJECT, e AS PaintEventArgs ) AS VOID
        LOCAL rArea := SELF:oMdiClient:ClientRectangle AS Rectangle
        IF rArea:Width <= 0 .OR. rArea:Height <= 0
            RETURN
        ENDIF
        LOCAL oBrush := LinearGradientBrush{ rArea, Color.FromArgb( 0, 255, 255 ), Color.Black, LinearGradientMode.Vertical } AS LinearGradientBrush
        e:Graphics:FillRectangle( oBrush, rArea )
        oBrush:Dispose()
        LOCAL oFont := Font{ "Times New Roman", 48, (FontStyle) ( (INT) FontStyle.Bold + (INT) FontStyle.Italic ) } AS Font
        LOCAL cText := "FabDBFEdEnh" AS STRING
        LOCAL oSize := e:Graphics:MeasureString( cText, oFont ) AS SizeF
        LOCAL nX := ( rArea:Width - oSize:Width ) / 2 AS REAL4
        LOCAL nY := ( rArea:Height - oSize:Height ) / 2 AS REAL4
        e:Graphics:DrawString( cText, oFont, Brushes.Black, nX + 4, nY + 4 )
        e:Graphics:DrawString( cText, oFont, Brushes.White, nX, nY )
        oFont:Dispose()
        RETURN

    PRIVATE METHOD Mdi_Resize( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:oMdiClient:Invalidate()
        RETURN

    // =====================================================================
    // Open
    // =====================================================================
    PRIVATE METHOD Window_Shown( sender AS OBJECT, e AS EventArgs ) AS VOID
        // Double click on a DBF: the file arrives as the first argument
        LOCAL aArgs := Environment.GetCommandLineArgs() AS STRING[]
        IF aArgs:Length > 1
            LOCAL cFile := (STRING) aArgs:GetValue( 1 ) AS STRING     // GetValue is 0-based, 0 = exe
            IF File.Exists( cFile )
                SELF:OpenWithDialog( cFile )
            ENDIF
        ENDIF
        RETURN

    /// <summary>File from another program start (double click on a DBF while the app is running)</summary>
    PUBLIC METHOD OnExternalFile( cFile AS STRING ) AS VOID
        IF SELF:WindowState == FormWindowState.Minimized
            SELF:WindowState := FormWindowState.Normal
        ENDIF
        SELF:TopMost := TRUE                // Bring the window to the front
        SELF:TopMost := FALSE
        SELF:Activate()
        cFile := IIF( cFile == NULL, "", cFile:Trim() )
        IF cFile:Length == 0 .OR. ! File.Exists( cFile )
            RETURN
        ENDIF
        // if the file is already open -> activate this window
        FOREACH oChild AS Form IN SELF:MdiChildren
            IF oChild IS DataWindow
                LOCAL cOpen := ((DataWindow) oChild):FileName AS STRING
                TRY
                    cOpen := Path.GetFullPath( cOpen )
                CATCH
                    NOP
                END TRY
                IF String.Compare( cOpen, cFile, TRUE ) == 0
                    IF oChild:WindowState == FormWindowState.Minimized
                        oChild:WindowState := FormWindowState.Normal
                    ENDIF
                    oChild:Activate()
                    RETURN
                ENDIF
            ENDIF
        NEXT
        SELF:OpenWithDialog( cFile )
        RETURN

    PUBLIC METHOD OpenWithDialog( cFile AS STRING ) AS VOID
        LOCAL dlg := OpenDialog{ cFile, SELF:oSettings } AS OpenDialog
        IF dlg:ShowDialog( SELF ) == DialogResult.OK
            SELF:OpenDirect( cFile, dlg:Driver, dlg:Exclusive, dlg:ReadOnly, dlg:ShowRecno, dlg:ShowDeleted )
        ENDIF
        RETURN

    PRIVATE METHOD OpenDirect( cFile AS STRING, cDriver AS STRING, lExcl AS LOGIC, lReadOnly AS LOGIC, lRecno AS LOGIC, lDel AS LOGIC ) AS VOID
        LOCAL oDW := DataWindow{} AS DataWindow
        IF oDW:OpenFile( cFile, cDriver, lExcl, lReadOnly, lRecno, lDel, SELF:oSettings:AutoCommit, SELF:oSettings:FullPath )
            oDW:MdiParent := SELF
            oDW:SetFont( SELF:oSettings:GetFont() )
            IF SELF:oSettings:DataMaximized
                oDW:WindowState := FormWindowState.Maximized
            ENDIF
            oDW:Show()
            SELF:oSettings:RememberFile( cFile, oDW:Mode, cDriver )
            SELF:BuildDatabaseMenu()
        ELSE
            oDW:Dispose()
        ENDIF
        RETURN

    PRIVATE METHOD M_OpenFile( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL ofd := OpenFileDialog{} AS OpenFileDialog
        ofd:CheckFileExists := TRUE
        ofd:Filter := "DBF files (*.dbf)|*.dbf|All files (*.*)|*.*"
        SELF:SetPath( ofd )
        IF ofd:ShowDialog( SELF ) == DialogResult.OK
            SELF:OpenWithDialog( ofd:FileName )
        ENDIF
        RETURN

    PRIVATE METHOD M_Recent( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL cEntry := (STRING) ((ToolStripMenuItem) sender):Tag AS STRING
        LOCAL aParts   := cEntry:Split( <CHAR>{ c'|' } ) AS STRING[]
        LOCAL cPath    := cEntry:Substring( cEntry:LastIndexOf( "|" ) + 1 ) AS STRING
        LOCAL cMode   := (STRING) aParts:GetValue( 0 ) AS STRING
        LOCAL cDriver  := IIF( aParts:Length >= 3, (STRING) aParts:GetValue( 1 ), SELF:oSettings:Driver ) AS STRING
        IF ! File.Exists( cPath )
            MessageBox.Show( "File not found:" + Environment.NewLine + cPath, "Open" )
            RETURN
        ENDIF
        SELF:OpenDirect( cPath, cDriver, cMode:StartsWith( "EXCLUSIVE" ), cMode:Contains( "READONLY" ), ;
                           SELF:oSettings:ShowRecno, SELF:oSettings:ShowDeleted )
        RETURN

    PRIVATE METHOD M_New( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL dbfWin := DBFStructWindow{} AS DBFStructWindow
        dbfWin:Text := "Create a DBF"
        dbfWin:ShowDialog( SELF )
        RETURN

    // Modify Structure: current file (must be open exclusively) or select a file
    PRIVATE METHOD M_Structure( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL cFile    := "" AS STRING
        LOCAL cDriver   := SELF:oSettings:Driver AS STRING
        LOCAL lRecno    := SELF:oSettings:ShowRecno AS LOGIC
        LOCAL lDel      := SELF:oSettings:ShowDeleted AS LOGIC
        LOCAL lWasOpen := FALSE AS LOGIC
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            IF ! oDW:Exclusive .OR. oDW:ReadOnly
                MessageBox.Show( "Modify Structure needs the file opened EXCLUSIVE and not read-only." + Environment.NewLine + ;
                    "Please close the window and reopen the file with 'Exclusive'.", "Modify Structure", MessageBoxButtons.OK, MessageBoxIcon.Information )
                RETURN
            ENDIF
            cFile    := oDW:FileName
            cDriver   := oDW:Driver
            lRecno    := oDW:ShowsRecno
            lDel      := oDW:ShowsDeleted
            lWasOpen := TRUE
            oDW:Close()                  // Close the workarea so the file can be rebuilt
        ELSE
            LOCAL ofd := OpenFileDialog{} AS OpenFileDialog
            ofd:Title := "Modify DBF Structure"
            ofd:CheckFileExists := TRUE
            SELF:SetPath( ofd )
            ofd:Filter := "DBF files (*.dbf)|*.dbf|All files (*.*)|*.*"
            IF ofd:ShowDialog( SELF ) != DialogResult.OK
                RETURN
            ENDIF
            cFile := ofd:FileName
        ENDIF
        LOCAL dlg := StructureDialog{ cFile, cDriver } AS StructureDialog
        IF dlg:Loaded
            dlg:ShowDialog( SELF )
        ENDIF
        // Show the file again (or anew after the rebuild)
        IF lWasOpen .OR. dlg:Rebuilt
            SELF:OpenDirect( cFile, cDriver, TRUE, FALSE, lRecno, lDel )
        ENDIF
        RETURN

    PRIVATE METHOD M_Exit( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:Close()
        RETURN

    PRIVATE METHOD Window_Closing( sender AS OBJECT, e AS FormClosingEventArgs ) AS VOID
        IF SELF:oSettings:AskQuit .AND. e:CloseReason == CloseReason.UserClosing
            IF MessageBox.Show( "Quit FabDBFEdEnh?", "Confirm on Exit", MessageBoxButtons.YesNo, MessageBoxIcon.Question ) != DialogResult.Yes
                e:Cancel := TRUE
                RETURN
            ENDIF
        ENDIF
        SELF:oSettings:Save()
        RETURN

    // Options - Set Defaults
    PRIVATE METHOD M_Defaults( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL dlg := SetDefaultsDialog{ SELF:oSettings } AS SetDefaultsDialog
        IF dlg:ShowDialog( SELF ) == DialogResult.OK
            SELF:UpdateChecks()
            // repaint the open windows (date format)
            FOREACH oChild AS Form IN SELF:MdiChildren
                IF oChild IS DataWindow
                    ((DataWindow) oChild):RefreshView()
                ENDIF
            NEXT
        ENDIF
        RETURN

    // View - Select Fields
    PRIVATE METHOD M_Fields( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:ChooseFields()
        ENDIF
        RETURN

    // Start folder for the file selection (Set Defaults - Default Path)
    PRIVATE METHOD SetPath( ofd AS FileDialog ) AS VOID
        IF SELF:oSettings:DefaultPath:Length > 0 .AND. Directory.Exists( SELF:oSettings:DefaultPath )
            ofd:InitialDirectory := SELF:oSettings:DefaultPath
        ENDIF
        RETURN

    // =====================================================================
    // Active data window
    // =====================================================================
    /// <summary>
    /// Returns the text box that is being edited (open grid cell or field of the form view).
    /// Then Ctrl+C/V/Z/Home/End apply to the text and not to the whole record.
    /// </summary>
    PRIVATE METHOD TextFocus() AS TextBoxBase
        LOCAL oCheck := SELF:ActiveMdiChild AS Control
        IF oCheck == NULL
            oCheck := SELF:ActiveControl
        ENDIF
        LOCAL nDepth := 0 AS INT
        DO WHILE oCheck != NULL .AND. nDepth < 20
            nDepth++
            IF oCheck IS TextBoxBase
                RETURN (TextBoxBase) oCheck
            ENDIF
            IF oCheck IS DataGridView
                LOCAL oGrid := (DataGridView) oCheck AS DataGridView
                IF oGrid:IsCurrentCellInEditMode .AND. oGrid:EditingControl IS TextBoxBase
                    RETURN (TextBoxBase) oGrid:EditingControl
                ENDIF
                RETURN NULL
            ENDIF
            IF oCheck IS ContainerControl
                oCheck := ((ContainerControl) oCheck):ActiveControl
            ELSE
                RETURN NULL
            ENDIF
        ENDDO
        RETURN NULL

    PRIVATE METHOD ActiveWindow() AS DataWindow
        IF SELF:ActiveMdiChild IS DataWindow
            RETURN (DataWindow) SELF:ActiveMdiChild
        ENDIF
        RETURN NULL

    PRIVATE METHOD Child_Activated( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:UpdateChecks()
        RETURN

    // =====================================================================
    // Menu actions for the active data window
    // =====================================================================
    PRIVATE METHOD M_OpenIndex( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:OpenIndexFile()
        ENDIF
        RETURN

    PRIVATE METHOD M_CloseIndex( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:CloseIndexes()
        ENDIF
        RETURN

    PRIVATE METHOD M_Search( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:FocusSearch()
        ENDIF
        RETURN

    PRIVATE METHOD M_Append( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:AppendRecord()
        ENDIF
        RETURN

    PRIVATE METHOD M_Delete( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:DeleteRecord( TRUE )
        ENDIF
        RETURN

    PRIVATE METHOD M_DeleteScoped( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:DeleteScoped()
        ENDIF
        RETURN

    PRIVATE METHOD M_Cut( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oTb := SELF:TextFocus() AS TextBoxBase
        IF oTb != NULL
            IF oTb:SelectionLength > 0
                oTb:Cut()
            ENDIF
            RETURN
        ENDIF
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:CutRecord( FALSE )
        ENDIF
        RETURN

    PRIVATE METHOD M_CutAdd( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:CutRecord( TRUE )
        ENDIF
        RETURN

    PRIVATE METHOD M_Recall( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:DeleteRecord( FALSE )
        ENDIF
        RETURN

    PRIVATE METHOD M_RecallAll( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:RecallAll()
        ENDIF
        RETURN

    PRIVATE METHOD M_Top( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oTb := SELF:TextFocus() AS TextBoxBase
        IF oTb != NULL
            oTb:SelectionStart := 0
            oTb:SelectionLength := 0
            oTb:ScrollToCaret()
            RETURN
        ENDIF
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:NavTop()
        ENDIF
        RETURN

    PRIVATE METHOD M_Prev( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:NavPrev()
        ENDIF
        RETURN

    PRIVATE METHOD M_Next( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:NavNext()
        ENDIF
        RETURN

    PRIVATE METHOD M_Bottom( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oTb := SELF:TextFocus() AS TextBoxBase
        IF oTb != NULL
            oTb:SelectionStart := oTb:TextLength
            oTb:SelectionLength := 0
            oTb:ScrollToCaret()
            RETURN
        ENDIF
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:NavBottom()
        ENDIF
        RETURN

    PRIVATE METHOD M_Goto( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:FocusGoto()
        ENDIF
        RETURN

    PRIVATE METHOD M_Refresh( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:RefreshView()
        ENDIF
        RETURN

    PRIVATE METHOD M_Undo( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oTb := SELF:TextFocus() AS TextBoxBase
        IF oTb != NULL
            oTb:Undo()
            RETURN
        ENDIF
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:Undo()
        ENDIF
        RETURN

    PRIVATE METHOD M_Commit( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:Commit()
        ENDIF
        RETURN

    PRIVATE METHOD M_Hex( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:ShowHex()
        ENDIF
        RETURN

    PRIVATE METHOD M_OnlyDeleted( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:SetView( oDW:ShowsRecno, TRUE, TRUE )
            SELF:UpdateChecks()
        ENDIF
        RETURN

    PRIVATE METHOD M_AllRecords( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:SetView( oDW:ShowsRecno, TRUE, FALSE )
            SELF:UpdateChecks()
        ENDIF
        RETURN

    PRIVATE METHOD M_Copy( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oTb := SELF:TextFocus() AS TextBoxBase
        IF oTb != NULL
            IF oTb:SelectionLength > 0
                oTb:Copy()
            ENDIF
            RETURN
        ENDIF
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:CopyRecord( FALSE )
        ENDIF
        RETURN

    PRIVATE METHOD M_CopyAdd( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:CopyRecord( TRUE )
        ENDIF
        RETURN

    PRIVATE METHOD M_Paste( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oTb := SELF:TextFocus() AS TextBoxBase
        IF oTb != NULL
            oTb:Paste()
            RETURN
        ENDIF
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:PasteRecord()
        ENDIF
        RETURN

    PRIVATE METHOD M_PasteAppend( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:PasteAppend( FALSE )
        ENDIF
        RETURN

    PRIVATE METHOD M_PasteAppendAll( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:PasteAppend( TRUE )
        ENDIF
        RETURN

    PRIVATE METHOD M_ClipView( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL cText := Convert.ToString( DbClip.Records:Count ) + " record(s) in the clipboard." AS STRING
        IF DbClip.Records:Count > 0
            cText += Environment.NewLine + Environment.NewLine + "Fields: " + String.Join( ", ", List<STRING>{ DbClip.Records[0]:Keys }:ToArray() )
        ENDIF
        MessageBox.Show( cText, "DBClipboard" )
        RETURN

    PRIVATE METHOD M_ClipClear( sender AS OBJECT, e AS EventArgs ) AS VOID
        DbClip.Records:Clear()
        RETURN

    PRIVATE METHOD M_RecordCount( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:RefreshView()
            MessageBox.Show( oDW:Text, "Record Count" )
        ENDIF
        RETURN

    // --- Options ---
    PRIVATE METHOD M_ShowRecno( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:SetView( ! oDW:ShowsRecno, oDW:ShowsDeleted, oDW:ShowsOnlyDeleted )
        ELSE
            SELF:oSettings:ShowRecno := ! SELF:oSettings:ShowRecno
            SELF:oSettings:Save()
        ENDIF
        SELF:UpdateChecks()
        RETURN

    PRIVATE METHOD M_ShowDeleted( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:SetView( oDW:ShowsRecno, ! oDW:ShowsDeleted, FALSE )
        ELSE
            SELF:oSettings:ShowDeleted := ! SELF:oSettings:ShowDeleted
            SELF:oSettings:Save()
        ENDIF
        SELF:UpdateChecks()
        RETURN

    PRIVATE METHOD M_AutoCommit( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:oSettings:AutoCommit := ! SELF:mAutoCommit:Checked
        SELF:oSettings:Save()
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:AutoCommit := SELF:oSettings:AutoCommit
        ENDIF
        SELF:UpdateChecks()
        RETURN

    PRIVATE METHOD M_GetFont( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL dlg := FontDialog{} AS FontDialog
        dlg:Font        := SELF:oSettings:GetFont()
        dlg:ShowEffects := FALSE
        dlg:MinSize     := 6
        dlg:MaxSize     := 24
        IF dlg:ShowDialog( SELF ) != DialogResult.OK
            RETURN
        ENDIF
        SELF:oSettings:RememberFont( dlg:Font )
        FOREACH oChild AS Form IN SELF:MdiChildren
            IF oChild IS DataWindow
                ((DataWindow) oChild):SetFont( SELF:oSettings:GetFont() )
            ENDIF
        NEXT
        RETURN

    PRIVATE METHOD M_FullPath( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:oSettings:FullPath := ! SELF:oSettings:FullPath
        SELF:oSettings:Save()
        SELF:UpdateChecks()
        RETURN

    // --- Stage 2: Index / View ---
    PRIVATE METHOD M_IndexManager( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            LOCAL dlg := IndexManagerDialog{ oDW } AS IndexManagerDialog
            dlg:ShowDialog( SELF )
        ENDIF
        RETURN

    PRIVATE METHOD M_SelectOrder( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:FocusOrder()
        ENDIF
        RETURN

    PRIVATE METHOD M_ReIndex( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            IF MessageBox.Show( "Rebuild all indexes oDW this file?", "ReIndex", MessageBoxButtons.YesNo, MessageBoxIcon.Question ) == DialogResult.Yes
                IF oDW:ReIndex()
                    MessageBox.Show( "ReIndex finished.", "ReIndex" )
                ENDIF
            ENDIF
        ENDIF
        RETURN

    PRIVATE METHOD M_Form( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:ShowFormView( TRUE )
        ENDIF
        RETURN

    PRIVATE METHOD M_Browse( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:ShowFormView( FALSE )
        ENDIF
        RETURN

    PRIVATE METHOD M_Filter( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            LOCAL dlg := InputDialog{ "Set Filter", ;
                "Expression in X#/VO syntax, e.g.  STATUS != 'X'  or  ORDERDATE >= CToD('01.01.2026').  Empty = filter oDWf.", ;
                <STRING>{ "Filter" }, <STRING>{ oDW:FilterText }, "", FALSE } AS InputDialog
            IF dlg:ShowDialog( SELF ) == DialogResult.OK
                oDW:SetFilter( dlg:InputValue( 0 ) )
            ENDIF
        ENDIF
        RETURN

    PRIVATE METHOD M_Scope( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            IF ! oDW:HasOrder
                MessageBox.Show( "For a scope, please select an order first.", "Order Scope" )
                RETURN
            ENDIF
            LOCAL dlg := InputDialog{ "Set Order Scope", ;
                "Range in the active index. Character: the start of the key is enough. Date: DD.MM.YYYY. Empty = open.", ;
                <STRING>{ "From", "To" }, <STRING>{ oDW:ScopeFrom, oDW:ScopeTo }, "", FALSE } AS InputDialog
            IF dlg:ShowDialog( SELF ) == DialogResult.OK
                oDW:SetScope( dlg:InputValue( 0 ), dlg:InputValue( 1 ) )
            ENDIF
        ENDIF
        RETURN

    // --- Stage 3: Utils ---
    PRIVATE METHOD M_Replace( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:ReplaceValues()
        ENDIF
        RETURN

    // Pack as in xBase: close the window, rebuild DBF+FPT, recreate indexes, reopen the window
    PRIVATE METHOD M_Pack( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW == NULL
            RETURN
        ENDIF
        IF ! oDW:Exclusive .OR. oDW:ReadOnly
            MessageBox.Show( "Pack needs the file opened EXCLUSIVE and not read-only.", "Pack", MessageBoxButtons.OK, MessageBoxIcon.Information )
            RETURN
        ENDIF
        LOCAL nDelCount := oDW:CountDeleted() AS INT
        LOCAL cQuestion AS STRING
        IF nDelCount == 0
            cQuestion := "There are no deleted records." + Environment.NewLine + "Rebuild DBF and FPT compactly anyway?"
        ELSE
            cQuestion := Convert.ToString( nDelCount ) + " deleted record(s) will be removed permanently and DBF/FPT rebuilt. Continue?" + Environment.NewLine + ;
                      "The record numbers of the following records will change."
        ENDIF
        IF MessageBox.Show( cQuestion + Environment.NewLine + Environment.NewLine + "The previous file is kept as a backup *_OLD_<date>.*", ;
                "Pack", MessageBoxButtons.YesNo, MessageBoxIcon.Question ) != DialogResult.Yes
            RETURN
        ENDIF
        LOCAL cFile  := oDW:FileName AS STRING
        LOCAL cDriver := oDW:Driver AS STRING
        LOCAL lRecno  := oDW:ShowsRecno AS LOGIC
        LOCAL lDel    := oDW:ShowsDeleted AS LOGIC
        oDW:Close()
        LOCAL cMessage := "" AS STRING
        LOCAL lOk := FALSE AS LOGIC
        SELF:Cursor := Cursors.WaitCursor
        TRY
            lOk := StructureRebuild.Pack( cFile, cDriver, REF cMessage )
        FINALLY
            SELF:Cursor := Cursors.Default
        END TRY
        MessageBox.Show( cMessage, "Pack", MessageBoxButtons.OK, IIF( lOk, MessageBoxIcon.Information, MessageBoxIcon.Error ) )
        SELF:OpenDirect( cFile, cDriver, TRUE, FALSE, lRecno, lDel )
        RETURN

    PRIVATE METHOD M_Zap( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:Zap()
        ENDIF
        RETURN

    PRIVATE METHOD M_ExportJson( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:ExportJson()
        ENDIF
        RETURN

    PRIVATE METHOD M_GenCreate( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:GenerateCreateScript()
        ENDIF
        RETURN

    PRIVATE METHOD M_GenDesc( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:GenerateDescription()
        ENDIF
        RETURN

    PRIVATE METHOD M_Fpt( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL oDW := SELF:ActiveWindow() AS DataWindow
        IF oDW != NULL
            oDW:FptReport()
        ELSE
            LOCAL ofd := OpenFileDialog{} AS OpenFileDialog
            ofd:Title := "Select the DBF for the FPT analysis"
            SELF:SetPath( ofd )
            ofd:Filter := "DBF files (*.dbf)|*.dbf|All files (*.*)|*.*"
            IF ofd:ShowDialog( SELF ) == DialogResult.OK
                LOCAL cText := "" AS STRING
                SELF:Cursor := Cursors.WaitCursor
                TRY
                    cText := FptAnalysis.Report( ofd:FileName )
                CATCH ex AS IOException
                    SELF:Cursor := Cursors.Default
                    MessageBox.Show( "The file cannot be read - it is opened exclusively." + Environment.NewLine + ;
                        "The FPT analysis needs the file SHARED or closed." + Environment.NewLine + Environment.NewLine + ex:Message, ;
                        "FPT Analysis", MessageBoxButtons.OK, MessageBoxIcon.Warning )
                    RETURN
                FINALLY
                    SELF:Cursor := Cursors.Default
                END TRY
                LOCAL oTextWindow := TextWindow{ "FPT Analysis - " + Path.GetFileName( ofd:FileName ), cText } AS TextWindow
                oTextWindow:ShowDialog( SELF )
            ENDIF
        ENDIF
        RETURN

    // --- Window ---
    PRIVATE METHOD M_Cascade( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:LayoutMdi( MdiLayout.Cascade )
        RETURN

    PRIVATE METHOD M_TileV( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:LayoutMdi( MdiLayout.TileVertical )
        RETURN

    PRIVATE METHOD M_TileH( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:LayoutMdi( MdiLayout.TileHorizontal )
        RETURN

    PRIVATE METHOD M_CloseAll( sender AS OBJECT, e AS EventArgs ) AS VOID
        FOREACH oChild AS Form IN SELF:MdiChildren
            oChild:Close()
        NEXT
        RETURN

    PRIVATE METHOD M_About( sender AS OBJECT, e AS EventArgs ) AS VOID
        MessageBox.Show( "FabDBFEdEnh - DBF tool for Swissbase" + Environment.NewLine + ;
                         "Based on: FabDBFEd (github.com/FabToys/FabDBFEd)" + Environment.NewLine + ;
                         "Stage 3: Pack, Zap, DBReplace, memo editing, FPT analysis", "About" )
        RETURN

END CLASS

END NAMESPACE
