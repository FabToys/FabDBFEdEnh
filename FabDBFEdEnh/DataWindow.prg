USING System
USING System.IO
USING System.Drawing
USING System.Globalization
USING System.Collections.Generic
USING System.Text.RegularExpressions
USING System.Windows.Forms
USING XSharp
USING XSharp.RDD
USING XSharp.RDD.Support

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>
/// Data window like in the dBAdministrator: works LIVE on the workarea.
/// The grid runs in virtual mode and only reads the visible records.
/// Changes are written immediately (record lock in shared mode).
/// Columns: 0 = RECNO, 1 = DELETED, from 2 = fields (field n in column n+1)
/// </summary>
PUBLIC CLASS DataWindow INHERIT System.Windows.Forms.Form

    // --- The table: work area, field metadata and the view (record list, filter, scope). No UI in there. ---
    PRIVATE oTable := DbfTable{} AS DbfTable

    // The window reads the table state through these (kept under the old names)
    PRIVATE PROPERTY oRdd        AS IRdd         GET SELF:oTable:Rdd
    PRIVATE PROPERTY cFile       AS STRING       GET SELF:oTable:FileName
    PRIVATE PROPERTY cDriver     AS STRING       GET SELF:oTable:Driver
    PRIVATE PROPERTY nFields     AS INT          GET SELF:oTable:FieldCount
    PRIVATE PROPERTY aFieldName  AS List<STRING> GET SELF:oTable:FieldName      // Index 0 = field 1
    PRIVATE PROPERTY aFieldType  AS List<STRING> GET SELF:oTable:FieldType
    PRIVATE PROPERTY aFieldDec   AS List<INT>    GET SELF:oTable:FieldDec
    PRIVATE PROPERTY aFieldAuto  AS List<LOGIC>  GET SELF:oTable:FieldAuto     // AutoIncrement and system fields: written by the RDD itself
    PRIVATE PROPERTY aFieldBinary AS List<LOGIC> GET SELF:oTable:FieldBinary   // binary fields (flag 4): binary memos open in the hex viewer
    PRIVATE PROPERTY lExclusive  AS LOGIC        GET SELF:oTable:Exclusive
    PRIVATE PROPERTY lReadOnly   AS LOGIC        GET SELF:oTable:ReadOnly
    PRIVATE PROPERTY lShowDeleted AS LOGIC       GET SELF:oTable:ShowDeleted SET SELF:oTable:ShowDeleted := VALUE
    PRIVATE PROPERTY lOnlyDeleted AS LOGIC       GET SELF:oTable:OnlyDeleted SET SELF:oTable:OnlyDeleted := VALUE
    PRIVATE PROPERTY lAutoCommit  AS LOGIC       GET SELF:oTable:AutoCommit  SET SELF:oTable:AutoCommit := VALUE
    // Record list in display order (active index, filter Deleted)
    PRIVATE PROPERTY aRecs       AS List<LONG>   GET SELF:oTable:Recs

    // --- Mode (display only) ---
    PRIVATE lShowRecno     AS LOGIC
    PRIVATE lFullPath     AS LOGIC

    // --- Cache of the record read last ---
    PRIVATE nCacheRec := 0 AS LONG
    PRIVATE lReading     := FALSE AS LOGIC     // currently reading a record (protection against re-entry)
    PRIVATE lMissed := FALSE AS LOGIC     // cells requested while reading
    // Row store for the grid per record number: each record is read only once when scrolling
    PRIVATE oRows := Dictionary<LONG, OBJECT[]>{} AS Dictionary<LONG, OBJECT[]>
    PRIVATE lCacheMemo := FALSE AS LOGIC   // Cache also contains the memo contents
    PRIVATE nFactor   := 1.0 AS REAL8      // Column width factor for the display font
    PRIVATE aCache    := List<OBJECT>{} AS List<OBJECT>
    PRIVATE lCacheDel AS LOGIC

    // --- Undo (last field change) ---
    PRIVATE nUndoRec  := 0 AS LONG
    PRIVATE nUndoField := 0 AS INT
    PRIVATE oUndoValue AS OBJECT

    // --- Controls ---
    PRIVATE grid      AS DbGrid
    PRIVATE cKeyExpression := "" AS STRING
    // Filter / scope (own evaluation when building the record list; stored in the table)
    PRIVATE PROPERTY oFilterCb   AS OBJECT GET SELF:oTable:FilterCb   SET SELF:oTable:FilterCb := VALUE
    PRIVATE PROPERTY cFilterText AS STRING GET SELF:oTable:FilterText SET SELF:oTable:FilterText := VALUE
    PRIVATE PROPERTY cScopeFrom  AS STRING GET SELF:oTable:ScopeFromText SET SELF:oTable:ScopeFromText := VALUE
    PRIVATE PROPERTY cScopeTo    AS STRING GET SELF:oTable:ScopeToText   SET SELF:oTable:ScopeToText := VALUE
    PRIVATE PROPERTY oScopeFrom  AS OBJECT GET SELF:oTable:ScopeFrom  SET SELF:oTable:ScopeFrom := VALUE
    PRIVATE PROPERTY oScopeTo    AS OBJECT GET SELF:oTable:ScopeTo    SET SELF:oTable:ScopeTo := VALUE
    // Form view
    PRIVATE pnlFormView     AS Panel
    PRIVATE aFormBox    := List<TextBox>{} AS List<TextBox>
    PRIVATE lFormView   := FALSE AS LOGIC
    PRIVATE nFormRow  := -1 AS INT
    PRIVATE lFormFill := FALSE AS LOGIC
    PRIVATE nReloadRec := 0 AS LONG
    PRIVATE txtGoto   AS ToolStripTextBox
    PRIVATE cmbSearch AS ToolStripComboBox
    PRIVATE cmbOrder  AS ToolStripComboBox
    PRIVATE lOrderLoad := FALSE AS LOGIC

    PUBLIC PROPERTY FileName AS STRING GET SELF:cFile
    PUBLIC PROPERTY Driver   AS STRING GET SELF:cDriver
    PUBLIC PROPERTY Exclusive AS LOGIC  GET SELF:lExclusive
    PUBLIC PROPERTY ReadOnly AS LOGIC  GET SELF:lReadOnly
    PUBLIC PROPERTY Mode AS STRING GET IIF( SELF:lExclusive, "EXCLUSIVE", "SHARED" ) + IIF( SELF:lReadOnly, "-READONLY", "" )

    // =====================================================================
    // Building the user interface
    // =====================================================================
    PUBLIC CONSTRUCTOR()
        LOCAL tsBar  AS ToolStrip

        SELF:Size := Size{ 760, 420 }
        SELF:Font := Font{ "Microsoft Sans Serif", 8.25 }

        // --- Grid ---
        SELF:grid := DbGrid{}
        SELF:grid:EnterAction := Action{ SELF, @Grid_Enter() }
        SELF:grid:Dock                    := DockStyle.Fill
        SELF:grid:VirtualMode             := TRUE
        SELF:grid:AllowUserToAddRows      := FALSE
        SELF:grid:AllowUserToDeleteRows   := FALSE
        SELF:grid:AllowUserToResizeRows   := FALSE
        SELF:grid:AllowUserToResizeColumns := TRUE    // Drag the column width with the mouse at the column header
        SELF:grid:AllowUserToOrderColumns  := TRUE    // Grab the columns by the header and move them
        SELF:grid:RowHeadersVisible       := FALSE
        SELF:grid:SelectionMode           := DataGridViewSelectionMode.FullRowSelect
        SELF:grid:MultiSelect             := FALSE
        SELF:grid:EditMode                := DataGridViewEditMode.EditOnKeystrokeOrF2
        SELF:grid:BackgroundColor         := Color.White
        SELF:grid:GridColor               := Color.FromArgb( 160, 160, 160 )
        SELF:grid:BorderStyle             := BorderStyle.None
        SELF:grid:EnableHeadersVisualStyles := FALSE
        SELF:grid:ColumnHeadersHeightSizeMode := DataGridViewColumnHeadersHeightSizeMode.DisableResizing
        SELF:grid:ColumnHeadersHeight     := 20
        SELF:grid:RowTemplate:Height      := 18
        SELF:grid:ColumnHeadersDefaultCellStyle:BackColor := SystemColors.Control
        SELF:grid:ColumnHeadersDefaultCellStyle:Alignment := DataGridViewContentAlignment.MiddleCenter
        SELF:grid:ColumnHeadersDefaultCellStyle:Font      := Font{ "Microsoft Sans Serif", 8.25 }
        SELF:grid:DefaultCellStyle:SelectionBackColor     := Color.FromArgb( 0, 120, 215 )
        SELF:grid:DefaultCellStyle:SelectionForeColor     := Color.White
        SELF:grid:DefaultCellStyle:Font                   := Font{ "Microsoft Sans Serif", 8.25 }
        SELF:grid:CellValueNeeded  += DataGridViewCellValueEventHandler{ SELF, @Grid_CellValueNeeded() }
        SELF:grid:CellValuePushed  += DataGridViewCellValueEventHandler{ SELF, @Grid_CellValuePushed() }
        SELF:grid:CellDoubleClick  += DataGridViewCellEventHandler{ SELF, @Grid_CellDoubleClick() }
        SELF:grid:CellFormatting   += DataGridViewCellFormattingEventHandler{ SELF, @Grid_CellFormatting() }
        SELF:grid:DataError        += DataGridViewDataErrorEventHandler{ SELF, @Grid_DataError() }
        SELF:grid:CurrentCellChanged += EventHandler{ SELF, @Grid_CurrentCellChanged() }
        SELF:grid:ColumnDividerDoubleClick += DataGridViewColumnDividerDoubleClickEventHandler{ SELF, @Grid_SeparatorDoubleClick() }

        // --- Toolbar: symbols + Goto / Search / Order in ONE row (like dBAdministrator) ---
        tsBar := ToolStrip{}
        tsBar:GripStyle := ToolStripGripStyle.Hidden
        tsBar:Font := Font{ "Segoe UI Symbol", 9.75 }
        tsBar:Items:Add( SELF:Symbol( 0x23EE, "First record (Ctrl+Home)",    Color.Black, EventHandler{ SELF, @Nav_Top() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x25C0, "Previous record",            Color.Black, EventHandler{ SELF, @Nav_Prev() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x25B6, "Next record",             Color.Black, EventHandler{ SELF, @Nav_Next() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x23ED, "Last record (Ctrl+End)",    Color.Black, EventHandler{ SELF, @Nav_Bottom() } ) )
        tsBar:Items:Add( ToolStripSeparator{} )
        tsBar:Items:Add( SELF:Symbol( 0x2795, "Append record (Ins)",       Color.DarkGreen, EventHandler{ SELF, @MakeButton_Append() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x2716, "Delete record (Ctrl+D)",     Color.DarkRed,   EventHandler{ SELF, @MakeButton_Delete() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x21BA, "Recall - restore record (Ctrl+R)", Color.DarkBlue, EventHandler{ SELF, @MakeButton_Recall() } ) )
        tsBar:Items:Add( ToolStripSeparator{} )
        tsBar:Items:Add( SELF:Symbol( 0x29C9, "Copy Record (Ctrl+C)",       Color.Black, EventHandler{ SELF, @MakeButton_Copy() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x2913, "Paste Append (Ctrl+Alt+A)",  Color.Black, EventHandler{ SELF, @MakeButton_PasteAppend() } ) )
        tsBar:Items:Add( ToolStripSeparator{} )
        tsBar:Items:Add( SELF:Symbol( 0x27F3, "Refresh (F5)",               Color.Black, EventHandler{ SELF, @MakeButton_Refresh() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x2630, "Form view (Shift+F2)", Color.Black, EventHandler{ SELF, @MakeButton_Form() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x25A6, "Table view (F2)",      Color.Black, EventHandler{ SELF, @MakeButton_Browse() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x0069, "Structure info",               Color.Red,   EventHandler{ SELF, @MakeButton_Structure() } ) )
        tsBar:Items:Add( SELF:Symbol( 0x0048, "Hex View",                   Color.Blue,  EventHandler{ SELF, @MakeButton_Hex() } ) )
        tsBar:Items:Add( ToolStripSeparator{} )

        SELF:txtGoto := ToolStripTextBox{}
        SELF:txtGoto:Size := Size{ 55, 21 }
        SELF:txtGoto:Font := SELF:Font
        SELF:txtGoto:KeyDown += KeyEventHandler{ SELF, @Goto_KeyDown() }
        SELF:cmbSearch := ToolStripComboBox{}
        SELF:cmbSearch:Size := Size{ 160, 21 }
        SELF:cmbSearch:Font := SELF:Font
        SELF:cmbSearch:KeyDown += KeyEventHandler{ SELF, @Search_KeyDown() }
        SELF:cmbOrder := ToolStripComboBox{}
        SELF:cmbOrder:DropDownStyle := ComboBoxStyle.DropDownList
        SELF:cmbOrder:Size := Size{ 140, 21 }
        SELF:cmbOrder:Font := SELF:Font
        SELF:cmbOrder:SelectedIndexChanged += EventHandler{ SELF, @Order_Changed() }
        tsBar:Items:Add( SELF:MakeLabel( "Goto" ) )
        tsBar:Items:Add( SELF:txtGoto )
        tsBar:Items:Add( ToolStripSeparator{} )
        tsBar:Items:Add( SELF:MakeLabel( "Search" ) )
        tsBar:Items:Add( SELF:cmbSearch )
        tsBar:Items:Add( ToolStripSeparator{} )
        tsBar:Items:Add( SELF:MakeLabel( "Order" ) )
        tsBar:Items:Add( SELF:cmbOrder )

        // Form view (initially invisible)
        SELF:pnlFormView := Panel{}
        SELF:pnlFormView:Dock       := DockStyle.Fill
        SELF:pnlFormView:AutoScroll := TRUE
        SELF:pnlFormView:BackColor  := SystemColors.Control
        SELF:pnlFormView:Visible    := FALSE

        // Order: Fill first, then the bar
        SELF:Controls:Add( SELF:pnlFormView )
        SELF:Controls:Add( SELF:grid )
        SELF:Controls:Add( tsBar )

        SELF:FormClosed += FormClosedEventHandler{ SELF, @Window_Closed() }
        RETURN

    // Symbol button from a Unicode character (font Segoe UI Symbol)
    PRIVATE METHOD Symbol( nChar AS INT, cTip AS STRING, oColor AS Color, oHandler AS EventHandler ) AS ToolStripButton
        LOCAL oButton := ToolStripButton{ Char.ConvertFromUtf32( nChar ) } AS ToolStripButton
        oButton:DisplayStyle := ToolStripItemDisplayStyle.Text
        oButton:ToolTipText  := cTip
        oButton:ForeColor    := oColor
        IF nChar == 0x0069 .OR. nChar == 0x0048       // "i" and "H" in bold like in the dBAdministrator
            oButton:Font := Font{ "Arial", 10, FontStyle.Bold }
        ENDIF
        oButton:Click += oHandler
        RETURN oButton

    PRIVATE METHOD MakeLabel( cText AS STRING ) AS ToolStripLabel
        LOCAL oLabel := ToolStripLabel{ cText } AS ToolStripLabel
        oLabel:Font := SELF:Font
        RETURN oLabel

    PRIVATE METHOD MakeButton( cText AS STRING, cTip AS STRING, oHandler AS EventHandler ) AS ToolStripButton
        LOCAL oButton := ToolStripButton{ cText } AS ToolStripButton
        oButton:DisplayStyle := ToolStripItemDisplayStyle.Text
        oButton:ToolTipText  := cTip
        oButton:Click += oHandler
        RETURN oButton

    // =====================================================================
    // Open / Close
    // =====================================================================
    PUBLIC METHOD OpenFile( cFile AS STRING, cRdd AS STRING, lExcl AS LOGIC, lReadOnly AS LOGIC, ;
                           lRecno AS LOGIC, lDeleted AS LOGIC, lAuto AS LOGIC, lPath AS LOGIC ) AS LOGIC
        LOCAL cError := "" AS STRING
        SELF:lShowRecno      := lRecno
        SELF:lShowDeleted := lDeleted
        SELF:lAutoCommit      := lAuto
        SELF:lFullPath      := lPath
        IF ! SELF:oTable:Open( cFile, cRdd, lExcl, lReadOnly, REF cError )
            MessageBox.Show( cError, "Open", MessageBoxButtons.OK, MessageBoxIcon.Error )
            RETURN FALSE
        ENDIF
        TRY
            SELF:BuildColumns()
            SELF:LoadOrders()
            SELF:LoadList( 0 )
            SELF:SetTitle()
            RETURN TRUE
        CATCH ex AS Exception
            MessageBox.Show( ex:Message, "Open", MessageBoxButtons.OK, MessageBoxIcon.Error )
            RETURN FALSE
        END TRY

    PRIVATE METHOD Window_Closed( sender AS OBJECT, e AS FormClosedEventArgs ) AS VOID
        SELF:oTable:Close()
        RETURN

    // make this workarea the current one (before every RDD call!)
    PRIVATE METHOD Sel() AS VOID
        SELF:oTable:Sel()
        RETURN

    PUBLIC METHOD SetTitle() AS VOID
        LOCAL cName := IIF( SELF:lFullPath, SELF:cFile, Path.GetFileNameWithoutExtension( SELF:cFile ):ToUpper() ) AS STRING
        SELF:Sel()
        SELF:Text := cName + " (" + Convert.ToString( (LONG) LastRec() ) + " Records  ANSI-" + SELF:Mode + ")" + ;
            IIF( SELF:cFilterText:Length > 0, "  FILTER", "" ) + IIF( SELF:oScopeFrom != NULL .OR. SELF:oScopeTo != NULL, "  SCOPE", "" ) + ;
            IIF( SELF:aRecs:Count < (LONG) LastRec(), "  [" + Convert.ToString( SELF:aRecs:Count ) + " angezeigt]", "" )
        RETURN

    // =====================================================================
    // Columns and record list
    // =====================================================================
    PRIVATE METHOD BuildColumns() AS VOID
        LOCAL oCol AS DataGridViewTextBoxColumn
        SELF:grid:Columns:Clear()

        oCol := DataGridViewTextBoxColumn{}
        oCol:Name := "RECNO"
        oCol:HeaderText := "RECNO"
        oCol:Width := (INT) Math.Round( 55 * SELF:nFactor )
        oCol:ReadOnly := TRUE
        oCol:DefaultCellStyle:Alignment := DataGridViewContentAlignment.MiddleRight
        oCol:Visible := SELF:lShowRecno
        SELF:grid:Columns:Add( oCol )

        oCol := DataGridViewTextBoxColumn{}
        oCol:Name := "DELETED"
        oCol:HeaderText := "DELETED"
        oCol:Width := (INT) Math.Round( 60 * SELF:nFactor )
        oCol:ReadOnly := TRUE
        oCol:DefaultCellStyle:Alignment := DataGridViewContentAlignment.MiddleCenter
        oCol:Visible := SELF:lShowDeleted
        SELF:grid:Columns:Add( oCol )

        FOR VAR i := 1 TO SELF:nFields
            LOCAL cType := SELF:aFieldType[i - 1] AS STRING
            LOCAL nLen := (INT) (LONG) SELF:oRdd:FieldInfo( i, DBS_LEN, NULL ) AS INT
            oCol := DataGridViewTextBoxColumn{}
            oCol:Name       := "F" + Convert.ToString( i )
            oCol:HeaderText := SELF:aFieldName[i - 1]
            oCol:SortMode   := DataGridViewColumnSortMode.NotSortable
            oCol:Width      := (INT) Math.Round( Math.Max( 50, Math.Min( 300, Math.Max( nLen, SELF:aFieldName[i - 1]:Length ) * 7 + 10 ) ) * SELF:nFactor )
            IF cType == "M"
                oCol:Width    := (INT) Math.Round( 160 * SELF:nFactor )
                oCol:ReadOnly := TRUE            // Memos only through double click
            ENDIF
            IF SELF:IsBinaryChar( i - 1 )
                oCol:ReadOnly := TRUE            // binary characters (C:B) : hex viewer through double click
            ENDIF
            IF cType == "N" .OR. cType == "F" .OR. cType == "I" .OR. cType == "Y" .OR. cType == "B"
                oCol:DefaultCellStyle:Alignment := DataGridViewContentAlignment.MiddleRight
            ENDIF
            IF SELF:lReadOnly .OR. SELF:aFieldAuto[i - 1]
                oCol:ReadOnly := TRUE
            ENDIF
            SELF:grid:Columns:Add( oCol )
        NEXT
        RETURN

    /// <summary>Read the record numbers in the order of the active index and position on nRecTarget</summary>
    PUBLIC METHOD LoadList( nRecTarget AS LONG ) AS VOID
        SELF:SyncOrder()
        SELF:oTable:LoadList()
        IF SELF:oTable:Corrupt
            MessageBox.Show( "The active index seems to be corrupt (it loops)." + Environment.NewLine + ;
                "Only the first " + Convert.ToString( SELF:aRecs:Count ) + " records are shown." + Environment.NewLine + Environment.NewLine + ;
                "Please open the file exclusively and run Index - ReIndex.", "Index corrupt", MessageBoxButtons.OK, MessageBoxIcon.Warning )
        ENDIF
        SELF:ClearCache()
        SELF:grid:RowCount := 0
        SELF:grid:RowCount := SELF:aRecs:Count
        SELF:grid:Invalidate()
        IF nRecTarget > 0
            SELF:GoToCloseRec( nRecTarget, FALSE )
        ENDIF
        IF SELF:lFormView
            SELF:nFormRow := Math.Max( 0, Math.Min( SELF:nFormRow, SELF:aRecs:Count - 1 ) )
            IF nRecTarget > 0 .AND. SELF:aRecs:IndexOf( nRecTarget ) >= 0
                SELF:nFormRow := SELF:aRecs:IndexOf( nRecTarget )
            ENDIF
            SELF:FillFormView()
        ENDIF
        SELF:SetTitle()
        RETURN

    // lMemos = FALSE: do NOT read memo fields from the FPT (grid display, fast scrolling)
    PRIVATE METHOD LoadCache( nRec AS LONG, lMemos AS LOGIC ) AS VOID
        IF nRec == SELF:nCacheRec .AND. ( SELF:lCacheMemo .OR. ! lMemos )
            RETURN
        ENDIF
        LOCAL aRow := NULL AS OBJECT[]
        // Grid: row from the row store, without reading the database again
        IF ! lMemos .AND. SELF:oRows:TryGetValue( nRec, OUT aRow )
            SELF:aCache:Clear()
            FOR VAR i := 1 TO SELF:nFields
                SELF:aCache:Add( aRow[i] )
            NEXT
            SELF:lCacheDel  := (LOGIC) aRow[SELF:nFields + 1]
            SELF:lCacheMemo := FALSE
            SELF:nCacheRec  := nRec
            RETURN
        ENDIF
        // Protect reading against re-entry: if another repaint comes in while reading
        // it must not move the record pointer (otherwise fields from 2 records in one row)
        LOCAL aValues := List<OBJECT>{} AS List<OBJECT>
        LOCAL lDel   := FALSE AS LOGIC
        SELF:lReading := TRUE
        TRY
            FOR VAR nAttempt := 1 TO 3
                SELF:Sel()
                DbGoto( nRec )
                aValues:Clear()
                FOR VAR i := 1 TO SELF:nFields
                    LOCAL oVal := NULL AS OBJECT
                    TRY
                        IF ! lMemos .AND. SELF:aFieldType[i - 1] == "M"
                            oVal := SELF:MemoPreview( SELF:oRdd:GetValue( i ) )      // Grid: keep only the preview
                        ELSE
                            oVal := SELF:oRdd:GetValue( i )
                        ENDIF
                    CATCH
                        oVal := "<Error>"
                    END TRY
                    aValues:Add( oVal )
                NEXT
                lDel := Deleted()
                IF (LONG) RecNo() == nRec
                    EXIT
                ENDIF
            NEXT
        FINALLY
            SELF:lReading := FALSE
        END TRY
        SELF:aCache:Clear()
        SELF:aCache:AddRange( aValues )
        SELF:lCacheDel  := lDel
        SELF:lCacheMemo := lMemos
        SELF:nCacheRec  := nRec
        IF ! lMemos
            aRow := OBJECT[]{ SELF:nFields + 1 }
            FOR VAR i := 1 TO SELF:nFields
                aRow[i] := SELF:aCache[i - 1]
            NEXT
            aRow[SELF:nFields + 1] := SELF:lCacheDel
            IF SELF:oRows:Count > 20000
                SELF:oRows:Clear()
            ENDIF
            SELF:oRows[nRec] := aRow
        ENDIF
        IF SELF:lMissed
            SELF:lMissed := FALSE
            SELF:grid:Invalidate()          // repaint cells skipped while reading
        ENDIF
        RETURN

    // =====================================================================
    // Grid events
    // =====================================================================
    PRIVATE METHOD Grid_CellValueNeeded( sender AS OBJECT, e AS DataGridViewCellValueEventArgs ) AS VOID
        IF e:RowIndex < 0 .OR. e:RowIndex >= SELF:aRecs:Count
            RETURN
        ENDIF
        LOCAL nRec := SELF:aRecs[e:RowIndex] AS LONG
        IF SELF:lReading
            SELF:lMissed := TRUE
            RETURN
        ENDIF
        SELF:LoadCache( nRec, FALSE )
        IF e:ColumnIndex == 0
            e:Value := Convert.ToString( nRec )
        ELSEIF e:ColumnIndex == 1
            e:Value := IIF( SELF:lCacheDel, "*", "" )
        ELSE
            e:Value := SELF:Display( e:ColumnIndex - 2 )
        ENDIF
        RETURN

    PRIVATE METHOD ClearCache() AS VOID
        SELF:nCacheRec := 0
        SELF:oRows:Clear()
        RETURN

    // Memo for the grid display: first 200 characters, line breaks as spaces
    PRIVATE METHOD MemoPreview( oValue AS OBJECT ) AS STRING
        IF oValue == NULL
            RETURN ""
        ENDIF
        LOCAL cMemo := oValue:ToString() AS STRING
        IF cMemo:Length > 400
            cMemo := cMemo:Substring( 0, 400 )
        ENDIF
        cMemo := cMemo:Replace( e"\r\n", " " ):Replace( e"\n", " " ):Replace( e"\r", " " ):TrimEnd( <CHAR>{ c' ', (CHAR) 0 } )
        RETURN IIF( cMemo:Length > 200, cMemo:Substring( 0, 200 ) + "...", cMemo )

    PRIVATE METHOD Display( nIdx AS INT ) AS STRING
        LOCAL oValue := SELF:aCache[nIdx] AS OBJECT
        LOCAL cType  := SELF:aFieldType[nIdx] AS STRING
        IF cType == "M"
            IF SELF:lCacheMemo
                RETURN SELF:MemoPreview( oValue )
            ENDIF
            RETURN IIF( oValue == NULL, "", (STRING) oValue )     // Preview from LoadCache
        ENDIF
        IF oValue == NULL
            RETURN ""
        ENDIF
        IF oValue IS IDate
            LOCAL oDate := (IDate) oValue AS IDate
            IF oDate:IsEmpty
                RETURN ""
            ENDIF
            TRY
                RETURN AppSettings.DateText( DateTime{ oDate:Year, oDate:Month, oDate:Day } )
            CATCH
                RETURN String.Format( "{0:00}.{1:00}.{2:0000}", oDate:Day, oDate:Month, oDate:Year )
            END TRY
        ENDIF
        IF oValue IS DateTime
            IF cType == "T" .AND. (DateTime) oValue != DateTime.MinValue
                RETURN AppSettings.DateText( (DateTime) oValue ) + " " + ((DateTime) oValue):ToString( "HH:mm:ss", CultureInfo.InvariantCulture )
            ENDIF
            RETURN AppSettings.DateText( (DateTime) oValue )
        ENDIF
        IF oValue IS LOGIC
            RETURN IIF( (LOGIC) oValue, "T", "F" )
        ENDIF
        IF cType == "M"
            LOCAL cMemo := oValue:ToString():TrimEnd() AS STRING
            cMemo := cMemo:Replace( e"\r\n", " " ):Replace( e"\n", " " ):Replace( e"\r", " " )
            RETURN IIF( cMemo:Length > 200, cMemo:Substring( 0, 200 ) + "...", cMemo )
        ENDIF
        IF cType == "N" .OR. cType == "F" .OR. cType == "Y" .OR. cType == "B"
            TRY
                RETURN Convert.ToDouble( oValue ):ToString( "F" + Convert.ToString( SELF:aFieldDec[nIdx] ), CultureInfo.InvariantCulture )
            CATCH
                NOP
            END TRY
        ENDIF
        RETURN oValue:ToString():TrimEnd()

    PRIVATE METHOD Grid_CellFormatting( sender AS OBJECT, e AS DataGridViewCellFormattingEventArgs ) AS VOID
        // Highlight the current cell in the selected row
        IF SELF:grid:CurrentCell != NULL .AND. e:RowIndex == SELF:grid:CurrentCell:RowIndex .AND. e:ColumnIndex == SELF:grid:CurrentCell:ColumnIndex
            e:CellStyle:SelectionBackColor := Color.FromArgb( 255, 255, 190 )
            e:CellStyle:SelectionForeColor := Color.Black
        ENDIF
        // show deleted records in grey
        IF e:RowIndex >= 0 .AND. e:RowIndex < SELF:aRecs:Count .AND. e:ColumnIndex >= 2 .AND. ! SELF:lReading
            SELF:LoadCache( SELF:aRecs[e:RowIndex], FALSE )
            IF SELF:lCacheDel
                e:CellStyle:ForeColor := Color.Gray
            ENDIF
        ENDIF
        RETURN

    // Double click on the divider in the column header: fit the width to the VISIBLE rows
    // (the default would be all rows -> with many records the whole file would be read)
    PRIVATE METHOD Grid_SeparatorDoubleClick( sender AS OBJECT, e AS DataGridViewColumnDividerDoubleClickEventArgs ) AS VOID
        TRY
            SELF:grid:AutoResizeColumn( e:ColumnIndex, DataGridViewAutoSizeColumnMode.DisplayedCells )
        CATCH
            NOP
        END TRY
        e:Handled := TRUE
        RETURN

    PRIVATE METHOD Grid_CurrentCellChanged( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:grid:CurrentCell != NULL
            SELF:grid:InvalidateRow( SELF:grid:CurrentCell:RowIndex )
        ENDIF
        RETURN

    // Enter outside of edit mode: edit the cell (memo: memo editor)
    PRIVATE METHOD Grid_Enter() AS VOID
        IF SELF:grid:CurrentCell == NULL
            RETURN
        ENDIF
        LOCAL nCol := SELF:grid:CurrentCell:ColumnIndex AS INT
        IF nCol < 2
            RETURN
        ENDIF
        IF SELF:aFieldType[nCol - 2] == "M"
            SELF:OpenMemo( SELF:grid:CurrentCell:RowIndex, nCol - 2 )
        ELSEIF ! SELF:lReadOnly
            SELF:grid:BeginEdit( TRUE )
        ENDIF
        RETURN

    PRIVATE METHOD Grid_DataError( sender AS OBJECT, e AS DataGridViewDataErrorEventArgs ) AS VOID
        e:ThrowException := FALSE
        RETURN

    /// <summary>Input in a cell -> write it to the DBF immediately</summary>
    PRIVATE METHOD Grid_CellValuePushed( sender AS OBJECT, e AS DataGridViewCellValueEventArgs ) AS VOID
        IF SELF:lReadOnly .OR. e:ColumnIndex < 2 .OR. e:RowIndex < 0 .OR. e:RowIndex >= SELF:aRecs:Count
            RETURN
        ENDIF
        LOCAL nIdx  := e:ColumnIndex - 2 AS INT
        LOCAL cType  := SELF:aFieldType[nIdx] AS STRING
        IF cType == "M"
            RETURN
        ENDIF
        LOCAL nRec  := SELF:aRecs[e:RowIndex] AS LONG
        LOCAL cText := IIF( e:Value == NULL, "", e:Value:ToString() ) AS STRING
        IF SELF:WriteField( nRec, nIdx, cText ) .AND. SELF:IsKeyField( nIdx )
            // Key field changed -> rebuild the order (after the grid event has ended)
            SELF:nReloadRec := nRec
            SELF:BeginInvoke( MethodInvoker{ SELF, @ExecuteReload() } )
        ENDIF
        RETURN

    /// <summary>Write text to field nIdx (0-based) of record nRec; returns TRUE on success</summary>
    PUBLIC METHOD WriteField( nRec AS LONG, nIdx AS INT, cText AS STRING ) AS LOGIC
        LOCAL nField := nIdx + 1 AS INT
        LOCAL cType  := SELF:aFieldType[nIdx] AS STRING
        LOCAL oNew  := NULL AS OBJECT
        LOCAL lOk   := FALSE AS LOGIC
        IF SELF:lReadOnly .OR. cType == "M" .OR. SELF:aFieldAuto[nIdx] .OR. SELF:IsBinaryChar( nIdx )
            RETURN FALSE
        ENDIF
        TRY
            oNew := SELF:ConvertText( cText, cType )
        CATCH
            MessageBox.Show( "Invalid input for field " + SELF:aFieldName[nIdx] + ": " + cText, "Input", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN FALSE
        END TRY
        TRY
            SELF:Sel()
            DbGoto( nRec )
            IF SELF:LockRecord( nRec )
                SELF:nUndoRec  := nRec
                SELF:nUndoField := nField
                SELF:oUndoValue := SELF:oRdd:GetValue( nField )
                FieldPut( nField, oNew )
                SELF:AfterWrite()
                lOk := TRUE
            ENDIF
        CATCH ex AS Exception
            MessageBox.Show( "Error while writing: " + ex:Message, "Save", MessageBoxButtons.OK, MessageBoxIcon.Error )
        END TRY
        SELF:ClearCache()
        RETURN lOk

    PRIVATE METHOD IsKeyField( nIdx AS INT ) AS LOGIC
        RETURN SELF:cKeyExpression:Length > 0 .AND. Regex.IsMatch( SELF:cKeyExpression, "\b" + Regex.Escape( SELF:aFieldName[nIdx] ) + "\b" )

    PRIVATE METHOD ExecuteReload() AS VOID
        IF SELF:nReloadRec > 0
            LOCAL nCol := IIF( SELF:grid:CurrentCell != NULL, SELF:grid:CurrentCell:ColumnIndex, 2 ) AS INT
            SELF:LoadList( SELF:nReloadRec )
            SELF:nReloadRec := 0
            LOCAL nRow := SELF:CurrentRow() AS INT
            IF nRow >= 0 .AND. nCol < SELF:grid:ColumnCount
                SELF:grid:CurrentCell := SELF:grid:Rows[nRow]:Cells[nCol]
            ENDIF
        ENDIF
        RETURN

    // Convert text from the grid to the field type (throws on invalid input)
    PRIVATE METHOD ConvertText( cText AS STRING, cType AS STRING ) AS OBJECT
        cText := cText:Trim()
        SWITCH cType
        CASE "N"
        CASE "F"
        CASE "Y"
        CASE "B"
            IF cText:Length == 0
                RETURN 0.0
            ENDIF
            RETURN Double.Parse( cText:Replace( "'", "" ):Replace( ",", "." ), CultureInfo.InvariantCulture )
        CASE "I"
            IF cText:Length == 0
                RETURN 0
            ENDIF
            RETURN Int32.Parse( cText )
        CASE "T"
            IF cText:Length == 0
                RETURN DateTime.MinValue
            ENDIF
            LOCAL dTime AS DateTime
            IF DateTime.TryParse( cText, CultureInfo.CurrentCulture, DateTimeStyles.None, OUT dTime )
                RETURN dTime
            ENDIF
            RETURN AppSettings.ParseDate( cText )
        CASE "D"
            IF cText:Length == 0
                RETURN DateTime.MinValue
            ENDIF
            RETURN AppSettings.ParseDate( cText )
        CASE "L"
            LOCAL cUpper := cText:ToUpper():Replace( ".", "" ) AS STRING
            RETURN cUpper == "T" .OR. cUpper == "Y" .OR. cUpper == "J" .OR. cUpper == "1" .OR. cUpper == "TRUE" .OR. cUpper == "JA"
        OTHERWISE
            RETURN cText
        END SWITCH

    // Record lock in shared mode
    PRIVATE METHOD LockRecord( nRec AS LONG ) AS LOGIC
        IF SELF:oTable:TryLock( nRec )
            RETURN TRUE
        ENDIF
        SELF:LockedMessage( nRec )
        RETURN FALSE

    PRIVATE METHOD LockedMessage( nRec AS LONG ) AS VOID
        MessageBox.Show( "Record " + Convert.ToString( nRec ) + " is locked by another user.", "Lock", MessageBoxButtons.OK, MessageBoxIcon.Warning )
        RETURN

    // after writing: auto commit and release the lock
    PRIVATE METHOD AfterWrite() AS VOID
        SELF:oTable:AfterWrite()
        RETURN

    PRIVATE METHOD Grid_CellDoubleClick( sender AS OBJECT, e AS DataGridViewCellEventArgs ) AS VOID
        IF e:RowIndex < 0 .OR. e:ColumnIndex < 2
            RETURN
        ENDIF
        IF SELF:aFieldType[e:ColumnIndex - 2] == "M"
            SELF:OpenMemo( e:RowIndex, e:ColumnIndex - 2 )
        ELSEIF SELF:IsBinaryChar( e:ColumnIndex - 2 )
            SELF:ShowBinaryChar( SELF:aRecs[e:RowIndex], e:ColumnIndex - 2 )
        ENDIF
        RETURN

    /// <summary>Show/edit a memo. The text is saved as it is in the editor (without padding).</summary>
    PRIVATE METHOD OpenMemo( nRow AS INT, nIdx AS INT ) AS VOID
        LOCAL nRec := SELF:aRecs[nRow] AS LONG
        // binary memo : not text, show the raw bytes in the hex viewer
        IF SELF:aFieldBinary[nIdx]
            SELF:ClearCache()
            SELF:LoadCache( nRec, TRUE )
            SELF:ShowBinaryMemo( nRec, nIdx )
            RETURN
        ENDIF
        SELF:ClearCache()
        SELF:LoadCache( nRec, TRUE )
        LOCAL oValue   := SELF:aCache[nIdx] AS OBJECT
        LOCAL cFull   := IIF( oValue == NULL, "", oValue:ToString() ) AS STRING
        LOCAL nBlock  := cFull:Length AS INT
        LOCAL cContent := cFull:TrimEnd( <CHAR>{ c' ', (CHAR) 0 } ) AS STRING
        LOCAL dlg := MemoDialog{ SELF:aFieldName[nIdx] + "  -  Record " + Convert.ToString( nRec ) + IIF( SELF:lReadOnly, "  (read only)", "" ), ;
                                 cContent, nBlock, SELF:lReadOnly } AS MemoDialog
        IF dlg:ShowDialog( SELF ) != DialogResult.OK .OR. ! dlg:Modified .OR. SELF:lReadOnly
            RETURN
        ENDIF
        LOCAL cNew := dlg:Content AS STRING
        TRY
            SELF:Sel()
            DbGoto( nRec )
            IF SELF:LockRecord( nRec )
                SELF:nUndoRec  := nRec
                SELF:nUndoField := nIdx + 1
                SELF:oUndoValue := cFull
                FieldPut( nIdx + 1, cNew )
                SELF:AfterWrite()
            ENDIF
        CATCH ex AS Exception
            MessageBox.Show( "The memo could not be saved: " + ex:Message, "Memo", MessageBoxButtons.OK, MessageBoxIcon.Error )
        END TRY
        SELF:ClearCache()
        SELF:grid:Invalidate()
        IF SELF:lFormView
            SELF:FillFormView()
        ENDIF
        RETURN

    // =====================================================================
    // Navigation
    // =====================================================================
    PRIVATE METHOD CurrentRow() AS INT
        IF SELF:lFormView
            RETURN SELF:nFormRow
        ENDIF
        IF SELF:grid:CurrentCell == NULL
            RETURN -1
        ENDIF
        RETURN SELF:grid:CurrentCell:RowIndex

    /// <summary>Set the display font for the browse grid (Options - Set Display Font)</summary>
    PUBLIC METHOD SetFont( oFont AS Font ) AS VOID
        IF oFont == NULL
            RETURN
        ENDIF
        LOCAL oDefault   := Font{ "Microsoft Sans Serif", 8.25 } AS Font
        LOCAL nBase := TextRenderer.MeasureText( "ABCDEFGHIJ0123456789", oDefault ):Width AS INT
        LOCAL nNew   := TextRenderer.MeasureText( "ABCDEFGHIJ0123456789", oFont ):Width AS INT
        LOCAL nOld   := SELF:nFactor AS REAL8
        SELF:nFactor := Math.Max( 0.5, (REAL8) nNew / (REAL8) Math.Max( 1, nBase ) )
        LOCAL nRec := SELF:CurrentRec() AS LONG
        SELF:grid:SuspendLayout()
        SELF:grid:DefaultCellStyle:Font              := oFont
        SELF:grid:ColumnHeadersDefaultCellStyle:Font := oFont
        SELF:grid:RowTemplate:Height                 := oFont:Height + 5
        SELF:grid:ColumnHeadersHeight                := oFont:Height + 7
        IF Math.Abs( nOld - SELF:nFactor ) > 0.001
            FOR VAR i := 0 TO SELF:grid:Columns:Count - 1
                LOCAL oCol := SELF:grid:Columns[i] AS DataGridViewColumn
                oCol:Width := Math.Max( 20, (INT) Math.Round( oCol:Width * SELF:nFactor / nOld ) )
            NEXT
        ENDIF
        // Row height only applies to newly created rows -> recreate the rows
        SELF:grid:RowCount := 0
        SELF:grid:RowCount := SELF:aRecs:Count
        SELF:grid:ResumeLayout()
        IF nRec > 0
            SELF:GoToCloseRec( nRec, FALSE )
        ENDIF
        SELF:grid:Invalidate()
        RETURN

    /// <summary>View - Select Fields: choose the visible columns (applies to this window)</summary>
    PUBLIC METHOD ChooseFields() AS VOID
        LOCAL aNames    := List<STRING>{} AS List<STRING>
        LOCAL aVisible := List<LOGIC>{} AS List<LOGIC>
        FOR VAR i := 2 TO SELF:grid:Columns:Count - 1
            aNames:Add( SELF:grid:Columns[i]:HeaderText )
            aVisible:Add( SELF:grid:Columns[i]:Visible )
        NEXT
        LOCAL dlg := FieldsDialog{ aNames, aVisible } AS FieldsDialog
        IF dlg:ShowDialog( SELF ) != DialogResult.OK
            RETURN
        ENDIF
        // first make a visible column the current one, then hide the others
        LOCAL nTarget := -1 AS INT
        FOR VAR i := 0 TO aNames:Count - 1
            IF dlg:IsFieldVisible( i ) .AND. nTarget < 0
                nTarget := i + 2
            ENDIF
        NEXT
        SELF:grid:Columns[nTarget]:Visible := TRUE
        IF SELF:grid:CurrentCell != NULL .AND. ! dlg:IsFieldVisible( Math.Max( 0, SELF:grid:CurrentCell:ColumnIndex - 2 ) )
            TRY
                SELF:grid:CurrentCell := SELF:grid:Rows[SELF:grid:CurrentCell:RowIndex]:Cells[nTarget]
            CATCH
                NOP
            END TRY
        ENDIF
        FOR VAR i := 0 TO aNames:Count - 1
            TRY
                SELF:grid:Columns[i + 2]:Visible := dlg:IsFieldVisible( i )
            CATCH
                NOP
            END TRY
        NEXT
        RETURN

    PUBLIC METHOD CurrentRec() AS LONG
        LOCAL n := SELF:CurrentRow() AS INT
        IF n < 0 .OR. n >= SELF:aRecs:Count
            RETURN 0
        ENDIF
        RETURN SELF:aRecs[n]

    PRIVATE METHOD GoToCloseRow( nRow AS INT ) AS VOID
        IF nRow < 0 .OR. nRow >= SELF:aRecs:Count
            RETURN
        ENDIF
        IF SELF:lFormView
            SELF:nFormRow := nRow
            SELF:FillFormView()
            RETURN
        ENDIF
        LOCAL nCol := 2 AS INT
        IF SELF:grid:CurrentCell != NULL
            nCol := SELF:grid:CurrentCell:ColumnIndex
        ENDIF
        IF nCol < 0 .OR. nCol >= SELF:grid:ColumnCount .OR. ! SELF:grid:Columns[nCol]:Visible
            nCol := IIF( SELF:grid:ColumnCount > 2, 2, 0 )
        ENDIF
        SELF:grid:CurrentCell := SELF:grid:Rows[nRow]:Cells[nCol]
        RETURN

    PUBLIC METHOD GoToCloseRec( nRec AS LONG, lMessage AS LOGIC ) AS LOGIC
        LOCAL nRow := SELF:aRecs:IndexOf( nRec ) AS INT
        IF nRow < 0
            IF lMessage
                MessageBox.Show( "Record " + Convert.ToString( nRec ) + " is not in the current view.", "Goto" )
            ENDIF
            RETURN FALSE
        ENDIF
        SELF:GoToCloseRow( nRow )
        RETURN TRUE

    PUBLIC METHOD NavTop()    AS VOID
        SELF:GoToCloseRow( 0 )
        RETURN
    PUBLIC METHOD NavBottom() AS VOID
        SELF:GoToCloseRow( SELF:grid:RowCount - 1 )
        RETURN
    PUBLIC METHOD NavPrev()   AS VOID
        SELF:GoToCloseRow( Math.Max( 0, SELF:CurrentRow() - 1 ) )
        RETURN
    PUBLIC METHOD NavNext()   AS VOID
        SELF:GoToCloseRow( SELF:CurrentRow() + 1 )
        RETURN

    PRIVATE METHOD Nav_Top( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:NavTop()
        RETURN
    PRIVATE METHOD Nav_Prev( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:NavPrev()
        RETURN
    PRIVATE METHOD Nav_Next( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:NavNext()
        RETURN
    PRIVATE METHOD Nav_Bottom( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:NavBottom()
        RETURN

    PUBLIC METHOD FocusGoto() AS VOID
        SELF:txtGoto:Focus()
        SELF:txtGoto:SelectAll()
        RETURN

    PUBLIC METHOD FocusSearch() AS VOID
        SELF:cmbSearch:Focus()
        SELF:cmbSearch:SelectAll()
        RETURN

    PRIVATE METHOD Goto_KeyDown( sender AS OBJECT, e AS KeyEventArgs ) AS VOID
        IF e:KeyCode == Keys.Enter
            e:SuppressKeyPress := TRUE
            LOCAL nRec AS LONG
            IF Int32.TryParse( SELF:txtGoto:Text:Trim(), OUT nRec )
                IF SELF:GoToCloseRec( nRec, TRUE )
                    SELF:grid:Focus()
                ENDIF
            ENDIF
        ENDIF
        RETURN

    // Search = seek in the active index (softseek)
    PRIVATE METHOD Search_KeyDown( sender AS OBJECT, e AS KeyEventArgs ) AS VOID
        IF e:KeyCode == Keys.Enter
            e:SuppressKeyPress := TRUE
            SELF:Search( SELF:cmbSearch:Text )
        ENDIF
        RETURN

    PUBLIC METHOD Search( cValue AS STRING ) AS VOID
        IF SELF:cmbOrder:SelectedIndex <= 0
            MessageBox.Show( "For a search, please select an order (index) first.", "Search" )
            RETURN
        ENDIF
        IF cValue:Length > 0 .AND. ! SELF:cmbSearch:Items:Contains( cValue )
            SELF:cmbSearch:Items:Insert( 0, cValue )
        ENDIF
        TRY
            SELF:Sel()
            DbSeek( cValue, TRUE )
            IF Eof()
                DbGoBottom()
            ENDIF
            LOCAL nRec := (LONG) RecNo() AS LONG
            IF SELF:GoToCloseRec( nRec, FALSE )
                SELF:grid:Focus()
            ENDIF
        CATCH ex AS Exception
            MessageBox.Show( "Search not possible: " + ex:Message, "Search" )
        END TRY
        RETURN

    // =====================================================================
    // Index / Order
    // =====================================================================
    PUBLIC METHOD LoadOrders() AS VOID
        LOCAL cCurrent := "" AS STRING
        SELF:lOrderLoad := TRUE
        SELF:Sel()
        SELF:cmbOrder:Items:Clear()
        SELF:cmbOrder:Items:Add( "<Natural Order>" )
        TRY
            cCurrent := ((STRING) OrdSetFocus()):Trim()
        CATCH
            cCurrent := ""
        END TRY
        FOR VAR i := 1 TO 200
            LOCAL cName := "" AS STRING
            TRY
                cName := ((STRING) OrdName( i )):Trim()
            CATCH
                cName := ""
            END TRY
            IF cName:Length == 0
                EXIT
            ENDIF
            SELF:cmbOrder:Items:Add( cName )
        NEXT
        SELF:cmbOrder:SelectedIndex := 0
        FOR VAR i := 1 TO SELF:cmbOrder:Items:Count - 1
            IF String.Compare( (STRING) SELF:cmbOrder:Items[i], cCurrent, TRUE ) == 0
                SELF:cmbOrder:SelectedIndex := i
            ENDIF
        NEXT
        SELF:lOrderLoad := FALSE
        SELF:MarkOrderColumn()
        RETURN

    PRIVATE METHOD Order_Changed( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:lOrderLoad .OR. SELF:oRdd == NULL
            RETURN
        ENDIF
        LOCAL nRec := SELF:CurrentRec() AS LONG
        // The scope only applies to the order it was set for
        SELF:oScopeFrom := NULL
        SELF:oScopeTo := NULL
        SELF:cScopeFrom := ""
        SELF:cScopeTo := ""
        TRY
            SELF:Sel()
            IF SELF:cmbOrder:SelectedIndex <= 0
                OrdSetFocus( 0 )
            ELSE
                OrdSetFocus( (STRING) SELF:cmbOrder:SelectedItem )
            ENDIF
        CATCH ex AS Exception
            MessageBox.Show( ex:Message, "Order" )
        END TRY
        SELF:MarkOrderColumn()
        SELF:LoadList( nRec )
        RETURN

    // Highlight the columns of the active index key in light blue (like dBAdministrator)
    PRIVATE METHOD MarkOrderColumn() AS VOID
        LOCAL cKey := "" AS STRING
        IF SELF:cmbOrder:SelectedIndex > 0
            TRY
                SELF:Sel()
                cKey := ((STRING) OrdKey()):ToUpper()
            CATCH
                cKey := ""
            END TRY
        ENDIF
        SELF:cKeyExpression := cKey
        FOR VAR i := 1 TO SELF:nFields
            LOCAL oCol := SELF:grid:Columns[i + 1] AS DataGridViewColumn
            IF cKey:Length > 0 .AND. Regex.IsMatch( cKey, "\b" + Regex.Escape( SELF:aFieldName[i - 1] ) + "\b" )
                oCol:HeaderCell:Style:BackColor := Color.Aqua
            ELSE
                oCol:HeaderCell:Style:BackColor := SystemColors.Control
            ENDIF
        NEXT
        RETURN

    PUBLIC METHOD OpenIndexFile() AS VOID
        LOCAL ofd := OpenFileDialog{} AS OpenFileDialog
        ofd:Filter := "Index (*.cdx;*.ntx;*.idx)|*.cdx;*.ntx;*.idx|All files (*.*)|*.*"
        ofd:InitialDirectory := Path.GetDirectoryName( SELF:cFile )
        IF ofd:ShowDialog( SELF ) == DialogResult.OK
            TRY
                SELF:Sel()
                OrdListAdd( ofd:FileName )
                SELF:LoadOrders()
            CATCH ex AS Exception
                MessageBox.Show( ex:Message, "Open index" )
            END TRY
        ENDIF
        RETURN

    PUBLIC METHOD CloseIndexes() AS VOID
        LOCAL nRec := SELF:CurrentRec() AS LONG
        TRY
            SELF:Sel()
            OrdListClear()
        CATCH ex AS Exception
            MessageBox.Show( ex:Message, "Index" )
        END TRY
        SELF:LoadOrders()
        SELF:LoadList( nRec )
        RETURN

    // =====================================================================
    // Edit records
    // =====================================================================
    PUBLIC METHOD AppendRecord() AS VOID
        IF SELF:ReadOnlyMessage()
            RETURN
        ENDIF
        TRY
            SELF:Sel()
            DbAppend()
            LOCAL nNew := (LONG) RecNo() AS LONG
            SELF:AfterWrite()
            SELF:LoadList( nNew )
        CATCH ex AS Exception
            MessageBox.Show( "Append not possible: " + ex:Message, "Append" )
        END TRY
        RETURN

    PUBLIC METHOD DeleteRecord( lDelete AS LOGIC ) AS VOID
        IF SELF:ReadOnlyMessage()
            RETURN
        ENDIF
        LOCAL nRow := SELF:CurrentRow() AS INT
        LOCAL nRec   := SELF:CurrentRec() AS LONG
        IF nRec == 0
            RETURN
        ENDIF
        LOCAL oResult := SELF:oTable:SetDeleted( nRec, lDelete ) AS DbfResult
        IF oResult:Locked > 0
            SELF:LockedMessage( nRec )
            RETURN
        ENDIF
        IF oResult:Failed
            MessageBox.Show( oResult:Error, "Delete/Recall" )
        ENDIF
        SELF:ClearCache()
        // if the record no longer fits the view, rebuild the list
        IF ( lDelete .AND. ! SELF:lShowDeleted ) .OR. ( ! lDelete .AND. SELF:lOnlyDeleted )
            SELF:LoadList( 0 )
            SELF:GoToCloseRow( Math.Min( nRow, SELF:grid:RowCount - 1 ) )
        ELSE
            SELF:grid:InvalidateRow( nRow )
        ENDIF
        IF SELF:lFormView
            SELF:FillFormView()
        ENDIF
        RETURN

    /// <summary>Delete all records of the current view (index scope + filter; deleted records are skipped)</summary>
    PUBLIC METHOD DeleteScoped() AS VOID
        IF SELF:ReadOnlyMessage()
            RETURN
        ENDIF
        IF SELF:aRecs:Count == 0
            MessageBox.Show( "There are no records in the current view.", "Scoped Delete" )
            RETURN
        ENDIF
        LOCAL cInfo := "" AS STRING
        IF SELF:oFilterCb != NULL .OR. SELF:oScopeFrom != NULL .OR. SELF:oScopeTo != NULL
            cInfo := " (filter / scope active)"
        ENDIF
        IF MessageBox.Show( Convert.ToString( SELF:aRecs:Count ) + " record(s) of the current view" + cInfo + " will be deleted. Continue?", ;
            "Scoped Delete", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2 ) != DialogResult.Yes
            RETURN
        ENDIF
        LOCAL nRec := SELF:CurrentRec() AS LONG
        LOCAL oResult := SELF:oTable:DeleteView() AS DbfResult
        IF oResult:Failed
            MessageBox.Show( oResult:Error, "Scoped Delete" )
        ENDIF
        SELF:LoadList( nRec )
        MessageBox.Show( Convert.ToString( oResult:Done ) + " records deleted." + ;
            IIF( oResult:Locked > 0, Environment.NewLine + Convert.ToString( oResult:Locked ) + " locked, not processed.", "" ), "Scoped Delete" )
        RETURN

    /// <summary>Copy the current record to the DBClipboard, then delete it</summary>
    PUBLIC METHOD CutRecord( lAdditive AS LOGIC ) AS VOID
        IF SELF:ReadOnlyMessage() .OR. SELF:CurrentRec() == 0
            RETURN
        ENDIF
        SELF:CopyRecord( lAdditive )
        SELF:DeleteRecord( TRUE )
        RETURN

    PUBLIC METHOD RecallAll() AS VOID
        IF SELF:ReadOnlyMessage()
            RETURN
        ENDIF
        IF MessageBox.Show( "Recall all deleted records?", "Recall All", MessageBoxButtons.YesNo, MessageBoxIcon.Question ) != DialogResult.Yes
            RETURN
        ENDIF
        LOCAL nRec := SELF:CurrentRec() AS LONG
        SELF:SyncOrder()
        LOCAL oResult := SELF:oTable:RecallAll() AS DbfResult
        IF oResult:Failed
            MessageBox.Show( oResult:Error, "Recall All" )
        ENDIF
        SELF:LoadList( nRec )
        MessageBox.Show( Convert.ToString( oResult:Done ) + " records recalled." + ;
            IIF( oResult:Locked > 0, Environment.NewLine + Convert.ToString( oResult:Locked ) + " locked, not processed.", "" ), "Recall All" )
        RETURN

    PUBLIC METHOD Commit() AS VOID
        SELF:oTable:Commit()
        RETURN

    // the table needs to know which order the combo box shows
    PRIVATE METHOD SyncOrder() AS VOID
        IF SELF:cmbOrder:SelectedIndex > 0
            SELF:oTable:ActiveOrder := (STRING) SELF:cmbOrder:SelectedItem
        ELSE
            SELF:oTable:ActiveOrder := ""
        ENDIF
        RETURN

    PUBLIC METHOD RefreshView() AS VOID
        LOCAL nRec := SELF:CurrentRec() AS LONG
        SELF:LoadList( nRec )
        RETURN

    // undo the last field change
    PUBLIC METHOD Undo() AS VOID
        IF SELF:nUndoRec == 0 .OR. SELF:lReadOnly
            RETURN
        ENDIF
        TRY
            SELF:Sel()
            DbGoto( SELF:nUndoRec )
            IF SELF:LockRecord( SELF:nUndoRec )
                FieldPut( SELF:nUndoField, SELF:oUndoValue )
                SELF:AfterWrite()
                SELF:GoToCloseRec( SELF:nUndoRec, FALSE )
                SELF:nUndoRec := 0
            ENDIF
        CATCH ex AS Exception
            MessageBox.Show( ex:Message, "Undo" )
        END TRY
        SELF:ClearCache()
        SELF:grid:Invalidate()
        RETURN

    PRIVATE METHOD ReadOnlyMessage() AS LOGIC
        IF SELF:lReadOnly
            MessageBox.Show( "The file is opened read-only.", "Read Only" )
        ENDIF
        RETURN SELF:lReadOnly

    // =====================================================================
    // View
    // =====================================================================
    PUBLIC METHOD SetView( lRecno AS LOGIC, lDeleted AS LOGIC, lOnlyDel AS LOGIC ) AS VOID
        LOCAL nRec := SELF:CurrentRec() AS LONG
        SELF:lShowRecno      := lRecno
        SELF:lShowDeleted := lDeleted .OR. lOnlyDel
        SELF:lOnlyDeleted   := lOnlyDel
        SELF:grid:Columns[0]:Visible := lRecno
        SELF:grid:Columns[1]:Visible := SELF:lShowDeleted
        SELF:LoadList( nRec )
        RETURN

    PUBLIC PROPERTY ShowsRecno       AS LOGIC GET SELF:lShowRecno
    PUBLIC PROPERTY ShowsDeleted  AS LOGIC GET SELF:lShowDeleted
    PUBLIC PROPERTY ShowsOnlyDeleted AS LOGIC GET SELF:lOnlyDeleted
    PUBLIC PROPERTY AutoCommit AS LOGIC GET SELF:lAutoCommit SET SELF:lAutoCommit := VALUE

    // =====================================================================
    // DBClipboard
    // =====================================================================
    PUBLIC METHOD CopyRecord( lAdditive AS LOGIC ) AS VOID
        LOCAL nRec := SELF:CurrentRec() AS LONG
        IF nRec == 0
            RETURN
        ENDIF
        LOCAL oRecord := Dictionary<STRING, OBJECT>{} AS Dictionary<STRING, OBJECT>
        SELF:Sel()
        DbGoto( nRec )
        FOR VAR i := 1 TO SELF:nFields
            TRY
                oRecord[SELF:aFieldName[i - 1]] := SELF:oRdd:GetValue( i )
            CATCH
                NOP
            END TRY
        NEXT
        IF ! lAdditive
            DbClip.Records:Clear()
        ENDIF
        DbClip.Records:Add( oRecord )
        RETURN

    // Write the values from the clipboard into the current record (same field names)
    PRIVATE METHOD WriteRecord( oRecord AS Dictionary<STRING, OBJECT>, aError AS List<STRING> ) AS VOID
        FOR VAR i := 1 TO SELF:nFields
            LOCAL cName := SELF:aFieldName[i - 1] AS STRING
            IF oRecord:ContainsKey( cName ) .AND. ! SELF:aFieldAuto[i - 1]
                TRY
                    FieldPut( i, oRecord[cName] )
                CATCH
                    IF ! aError:Contains( cName )
                        aError:Add( cName )
                    ENDIF
                END TRY
            ENDIF
        NEXT
        RETURN

    PUBLIC METHOD PasteRecord() AS VOID
        IF SELF:ReadOnlyMessage() .OR. DbClip.Records:Count == 0
            RETURN
        ENDIF
        LOCAL nRec := SELF:CurrentRec() AS LONG
        IF nRec == 0
            RETURN
        ENDIF
        IF MessageBox.Show( "Record " + Convert.ToString( nRec ) + " will be overwritten with the copied record. Continue?", "Paste", ;
                            MessageBoxButtons.YesNo, MessageBoxIcon.Question ) != DialogResult.Yes
            RETURN
        ENDIF
        LOCAL aError := List<STRING>{} AS List<STRING>
        TRY
            SELF:Sel()
            DbGoto( nRec )
            IF SELF:LockRecord( nRec )
                SELF:WriteRecord( DbClip.Records[0], aError )
                SELF:AfterWrite()
            ENDIF
        CATCH ex AS Exception
            MessageBox.Show( ex:Message, "Paste" )
        END TRY
        SELF:ClearCache()
        SELF:grid:Invalidate()
        SELF:ReportError( aError )
        RETURN

    PUBLIC METHOD PasteAppend( lAll AS LOGIC ) AS VOID
        IF SELF:ReadOnlyMessage() .OR. DbClip.Records:Count == 0
            RETURN
        ENDIF
        LOCAL aError := List<STRING>{} AS List<STRING>
        LOCAL nNum := IIF( lAll, DbClip.Records:Count, 1 ) AS INT
        LOCAL nNew := 0 AS LONG
        TRY
            SELF:Sel()
            FOR VAR i := 0 TO nNum - 1
                DbAppend()
                SELF:WriteRecord( DbClip.Records[i], aError )
                nNew := (LONG) RecNo()
            NEXT
            SELF:AfterWrite()
        CATCH ex AS Exception
            MessageBox.Show( ex:Message, "Paste Append" )
        END TRY
        SELF:LoadList( nNew )
        SELF:ReportError( aError )
        RETURN

    PRIVATE METHOD ReportError( aError AS List<STRING> ) AS VOID
        IF aError:Count > 0
            MessageBox.Show( "These fields could not be taken over (different type?):" + Environment.NewLine + ;
                             String.Join( ", ", aError:ToArray() ), "Paste", MessageBoxButtons.OK, MessageBoxIcon.Warning )
        ENDIF
        RETURN

    // =====================================================================
    // Binary memo fields: shown in the hex viewer
    // =====================================================================
    /// <summary>Raw content of a memo block, read directly from the FPT file (FoxPro / VFP memo files).
    /// Returns NULL when it cannot be read this way (no FPT file, DBT memo, block outside the file ...).</summary>
    PRIVATE METHOD ReadMemoBytes( nRec AS LONG, nIdx AS INT ) AS BYTE[]
        LOCAL cFpt := Path.ChangeExtension( SELF:cFile, ".fpt" ) AS STRING
        IF ! File.Exists( cFpt )
            RETURN NULL
        ENDIF
        SELF:Sel()
        // position of the memo pointer inside the record (byte 0 = deleted flag)
        LOCAL nOffset := 1 AS INT
        FOR VAR i := 1 TO nIdx
            nOffset += (INT) (LONG) SELF:oRdd:FieldInfo( i, DBS_LEN, NULL )
        NEXT
        LOCAL nPtrLen := (INT) (LONG) SELF:oRdd:FieldInfo( nIdx + 1, DBS_LEN, NULL ) AS INT
        LOCAL nBlockNo := 0 AS INT64
        LOCAL fs := FileStream{ SELF:cFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
        TRY
            LOCAL aHeader := BYTE[]{ 12 } AS BYTE[]
            fs:Read( aHeader, 0, 12 )
            LOCAL nHdrLen := BitConverter.ToUInt16( aHeader, 8 ) AS INT
            LOCAL nRecLen := BitConverter.ToUInt16( aHeader, 10 ) AS INT
            LOCAL aPtr := BYTE[]{ nPtrLen } AS BYTE[]
            fs:Seek( (INT64) nHdrLen + (INT64) ( nRec - 1 ) * nRecLen + nOffset, SeekOrigin.Begin )
            fs:Read( aPtr, 0, nPtrLen )
            IF nPtrLen == 4
                nBlockNo := BitConverter.ToUInt32( aPtr, 0 )                 // VFP : 4 byte binary, little endian
            ELSE
                // FoxPro 2.x : 10 digits as text
                IF ! Int64.TryParse( System.Text.Encoding.ASCII.GetString( aPtr ):Trim(), OUT nBlockNo )
                    nBlockNo := 0
                ENDIF
            ENDIF
        FINALLY
            fs:Close()
        END TRY
        IF nBlockNo == 0
            RETURN BYTE[]{ 0 }                                              // empty memo
        ENDIF
        LOCAL ft := FileStream{ cFpt, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
        TRY
            LOCAL aHead := BYTE[]{ 8 } AS BYTE[]
            ft:Read( aHead, 0, 8 )
            LOCAL aTwo := BYTE[]{ 2 } AS BYTE[]
            Array.Copy( aHead, 6, aTwo, 0, 2 )
            Array.Reverse( aTwo )                                           // block size : big endian
            LOCAL nBlockSize := (INT64) BitConverter.ToUInt16( aTwo, 0 ) AS INT64
            IF nBlockSize <= 0 .OR. nBlockNo * nBlockSize + 8 > ft:Length
                RETURN NULL
            ENDIF
            ft:Seek( nBlockNo * nBlockSize, SeekOrigin.Begin )
            LOCAL aBlock := BYTE[]{ 8 } AS BYTE[]                           // block header : type (4) + length (4), both big endian
            ft:Read( aBlock, 0, 8 )
            LOCAL aFour := BYTE[]{ 4 } AS BYTE[]
            Array.Copy( aBlock, 4, aFour, 0, 4 )
            Array.Reverse( aFour )
            LOCAL nDataLen := (INT64) BitConverter.ToUInt32( aFour, 0 ) AS INT64
            IF nDataLen < 0 .OR. nDataLen > 268435456 .OR. ft:Position + nDataLen > ft:Length
                RETURN NULL
            ENDIF
            LOCAL aData := BYTE[]{ (INT) nDataLen } AS BYTE[]
            IF nDataLen > 0
                ft:Read( aData, 0, (INT) nDataLen )
            ENDIF
            RETURN aData
        FINALLY
            ft:Close()
        END TRY

    /// <summary>Shows the content of a binary memo field (record nRec, field nIdx) in the hex viewer</summary>
    PRIVATE METHOD ShowBinaryMemo( nRec AS LONG, nIdx AS INT ) AS VOID
        LOCAL aBytes := NULL AS BYTE[]
        TRY
            SELF:Commit()
            aBytes := SELF:ReadMemoBytes( nRec, nIdx )
        CATCH ex AS IOException
            // file opened exclusively by this window : the memo file cannot be read directly -> use the RDD value below
            System.Diagnostics.Debug.WriteLine( ex:Message )
            aBytes := NULL
        CATCH ex AS Exception
            MessageBox.Show( "The memo could not be read: " + ex:Message, "Binary memo", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN
        END TRY
        IF aBytes == NULL
            // memo file not readable directly (e.g. DBT): fall back to the value delivered by the RDD
            LOCAL oValue := SELF:aCache[nIdx] AS OBJECT
            IF oValue IS BYTE[]
                aBytes := (BYTE[]) oValue
            ELSEIF oValue != NULL
                aBytes := System.Text.Encoding.GetEncoding( 28591 ):GetBytes( oValue:ToString() )
            ELSE
                aBytes := BYTE[]{ 0 }
            ENDIF
        ENDIF
        IF aBytes:Length == 0
            MessageBox.Show( "The memo is empty.", "Binary memo", MessageBoxButtons.OK, MessageBoxIcon.Information )
            RETURN
        ENDIF
        LOCAL oHex := HexaEditor{} AS HexaEditor
        oHex:Text := SELF:aFieldName[nIdx] + "  -  Record " + Convert.ToString( nRec ) + "  -  " + Convert.ToString( aBytes:Length ) + " bytes (binary memo, read only)"
        oHex:SetBytes( aBytes )
        oHex:ShowDialog( SELF )
        RETURN

    // =====================================================================
    // Binary character fields (C:B): shown in the hex viewer, never edited as text
    // =====================================================================
    /// <summary>Character field with the Binary flag: raw data, not text</summary>
    PRIVATE METHOD IsBinaryChar( nIdx AS INT ) AS LOGIC
        RETURN SELF:aFieldType[nIdx] == "C" .AND. SELF:aFieldBinary[nIdx]

    /// <summary>Raw bytes of a field, read directly from the DBF record (IOException when this window holds the file exclusively)</summary>
    PRIVATE METHOD ReadFieldBytes( nRec AS LONG, nIdx AS INT ) AS BYTE[]
        SELF:Sel()
        // position of the field inside the record (byte 0 = deleted flag)
        LOCAL nOffset := 1 AS INT
        FOR VAR i := 1 TO nIdx
            nOffset += (INT) (LONG) SELF:oRdd:FieldInfo( i, DBS_LEN, NULL )
        NEXT
        LOCAL nLen := (INT) (LONG) SELF:oRdd:FieldInfo( nIdx + 1, DBS_LEN, NULL ) AS INT
        LOCAL aData := BYTE[]{ nLen } AS BYTE[]
        LOCAL fs := FileStream{ SELF:cFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
        TRY
            LOCAL aHeader := BYTE[]{ 12 } AS BYTE[]
            fs:Read( aHeader, 0, 12 )
            LOCAL nHdrLen := BitConverter.ToUInt16( aHeader, 8 ) AS INT
            LOCAL nRecLen := BitConverter.ToUInt16( aHeader, 10 ) AS INT
            fs:Seek( (INT64) nHdrLen + (INT64) ( nRec - 1 ) * nRecLen + nOffset, SeekOrigin.Begin )
            fs:Read( aData, 0, nLen )
        FINALLY
            fs:Close()
        END TRY
        RETURN aData

    /// <summary>Shows the content of a binary character field (record nRec, field nIdx) in the hex viewer</summary>
    PRIVATE METHOD ShowBinaryChar( nRec AS LONG, nIdx AS INT ) AS VOID
        LOCAL aBytes := NULL AS BYTE[]
        TRY
            SELF:Commit()
            aBytes := SELF:ReadFieldBytes( nRec, nIdx )
        CATCH ex AS IOException
            // file held exclusively by this window : use the value delivered by the RDD below
            System.Diagnostics.Debug.WriteLine( ex:Message )
            aBytes := NULL
        CATCH ex AS Exception
            MessageBox.Show( "The field could not be read: " + ex:Message, "Binary field", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN
        END TRY
        IF aBytes == NULL
            SELF:ClearCache()
            SELF:LoadCache( nRec, TRUE )
            LOCAL oValue := SELF:aCache[nIdx] AS OBJECT
            IF oValue IS BYTE[]
                aBytes := (BYTE[]) oValue
            ELSEIF oValue != NULL
                aBytes := System.Text.Encoding.GetEncoding( 28591 ):GetBytes( oValue:ToString() )
            ELSE
                aBytes := BYTE[]{ 0 }
            ENDIF
        ENDIF
        IF aBytes:Length == 0
            MessageBox.Show( "The field is empty.", "Binary field", MessageBoxButtons.OK, MessageBoxIcon.Information )
            RETURN
        ENDIF
        LOCAL oHex := HexaEditor{} AS HexaEditor
        oHex:Text := SELF:aFieldName[nIdx] + "  -  Record " + Convert.ToString( nRec ) + "  -  " + Convert.ToString( aBytes:Length ) + " bytes (binary field, read only)"
        oHex:SetBytes( aBytes )
        oHex:ShowDialog( SELF )
        RETURN

    PRIVATE METHOD FormBinary_DoubleClick( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:nFormRow >= 0 .AND. SELF:nFormRow < SELF:aRecs:Count
            SELF:ShowBinaryChar( SELF:aRecs[SELF:nFormRow], (INT) ((TextBox) sender):Tag )
        ENDIF
        RETURN

    // =====================================================================
    // Hex view of the current record (read directly from the file)
    // =====================================================================
    PUBLIC METHOD ShowHex() AS VOID
        LOCAL nRec := SELF:CurrentRec() AS LONG
        IF nRec == 0
            RETURN
        ENDIF
        TRY
            SELF:Commit()
            LOCAL aHeader := BYTE[]{ 12 } AS BYTE[]
            LOCAL aRecord := NULL AS BYTE[]
            LOCAL fs := FileStream{ SELF:cFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
            TRY
                fs:Read( aHeader, 0, 12 )
                LOCAL nHdrLen := BitConverter.ToUInt16( aHeader, 8 ) AS INT
                LOCAL nLen  := BitConverter.ToUInt16( aHeader, 10 ) AS INT
                aRecord := BYTE[]{ nLen }
                fs:Seek( (INT64) nHdrLen + (INT64) ( nRec - 1 ) * nLen, SeekOrigin.Begin )
                fs:Read( aRecord, 0, nLen )
            FINALLY
                fs:Close()
            END TRY
            LOCAL oHex := HexaEditor{} AS HexaEditor
            oHex:Text := Path.GetFileName( SELF:cFile ) + "  -  Record " + Convert.ToString( nRec )
            oHex:SetBytes( aRecord )
            oHex:ShowDialog( SELF )
        CATCH ex AS Exception
            MessageBox.Show( ex:Message, "Hex View" )
        END TRY
        RETURN

    // =====================================================================
    // Structure info ("i"): file header, fields, indexes
    // =====================================================================
    PUBLIC METHOD ShowStructure() AS VOID
        LOCAL oInfo  := System.Text.StringBuilder{} AS System.Text.StringBuilder
        LOCAL nHdrLen  := 0 AS INT
        LOCAL nLen   := 0 AS INT
        LOCAL cStatus := "" AS STRING
        TRY
            SELF:Sel()
            LOCAL aHeader := BYTE[]{ 12 } AS BYTE[]
            LOCAL fs := FileStream{ SELF:cFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
            TRY
                fs:Read( aHeader, 0, 12 )
            FINALLY
                fs:Close()
            END TRY
            nHdrLen  := BitConverter.ToUInt16( aHeader, 8 )
            nLen   := BitConverter.ToUInt16( aHeader, 10 )
            cStatus := String.Format( "{0:00}.{1:00}.{2:0000}", aHeader:GetValue( 3 ), aHeader:GetValue( 2 ), 1900 + Convert.ToInt32( aHeader:GetValue( 1 ) ) )
        CATCH
            NOP
        END TRY

        oInfo:AppendLine( "File         : " + SELF:cFile )
        oInfo:AppendLine( "Driver       : " + SELF:cDriver + "   (" + SELF:Mode + ")" )
        oInfo:AppendLine( "Records      : " + Convert.ToString( (LONG) LastRec() ) + "   (in view: " + Convert.ToString( SELF:aRecs:Count ) + ")" )
        oInfo:AppendLine( "Record length: " + Convert.ToString( nLen ) + "   Header: " + Convert.ToString( nHdrLen ) + "   last change: " + cStatus )
        oInfo:AppendLine( "DBF size     : " + SELF:FormatSize( SELF:cFile ) )
        FOREACH cExt AS STRING IN <STRING>{ ".fpt", ".dbt", ".cdx", ".ntx" }
            LOCAL cSibling := Path.ChangeExtension( SELF:cFile, cExt ) AS STRING
            IF File.Exists( cSibling )
                oInfo:AppendLine( cExt:ToUpper():Substring( 1 ) + "-size     : " + SELF:FormatSize( cSibling ) )
            ENDIF
        NEXT
        oInfo:AppendLine( "" )
        oInfo:AppendLine( "Indexes:" )
        FOR VAR i := 1 TO 200
            LOCAL cName := "" AS STRING
            LOCAL cKey  := "" AS STRING
            TRY
                cName := ((STRING) OrdName( i )):Trim()
                cKey  := ((STRING) OrdKey( i )):Trim()
            CATCH
                NOP
            END TRY
            IF cName:Length == 0
                EXIT
            ENDIF
            oInfo:AppendLine( "  " + cName:PadRight( 12 ) + cKey )
        NEXT

        // Window with info on top and field list below
        LOCAL oForm := Form{} AS Form
        oForm:Text := "Structure - " + Path.GetFileName( SELF:cFile )
        oForm:Size := Size{ 560, 560 }
        oForm:StartPosition := FormStartPosition.CenterParent
        oForm:ShowInTaskbar := FALSE

        LOCAL txt := TextBox{} AS TextBox
        txt:Multiline  := TRUE
        txt:ReadOnly   := TRUE
        txt:ScrollBars := ScrollBars.Vertical
        txt:Font       := Font{ "Consolas", 9 }
        txt:Dock       := DockStyle.Top
        txt:Height     := 200
        txt:Text       := oInfo:ToString()

        LOCAL lv := ListView{} AS ListView
        lv:View          := View.Details
        lv:FullRowSelect := TRUE
        lv:GridLines     := TRUE
        lv:Dock          := DockStyle.Fill
        lv:Font          := Font{ "Microsoft Sans Serif", 8.25 }
        lv:Columns:Add( "Nr", 40, HorizontalAlignment.Right )
        lv:Columns:Add( "Field name", 140 )
        lv:Columns:Add( "Type", 45 )
        lv:Columns:Add( "Length", 60, HorizontalAlignment.Right )
        lv:Columns:Add( "Dec", 45, HorizontalAlignment.Right )
        lv:Columns:Add( "Offset", 60, HorizontalAlignment.Right )
        LOCAL nOffset := 1 AS INT
        FOR VAR i := 1 TO SELF:nFields
            LOCAL nFieldLen := (INT) (LONG) SELF:oRdd:FieldInfo( i, DBS_LEN, NULL ) AS INT
            LOCAL oItem := ListViewItem{ Convert.ToString( i ) } AS ListViewItem
            oItem:SubItems:Add( SELF:aFieldName[i - 1] )
            oItem:SubItems:Add( SELF:aFieldType[i - 1] )
            oItem:SubItems:Add( Convert.ToString( nFieldLen ) )
            oItem:SubItems:Add( Convert.ToString( SELF:aFieldDec[i - 1] ) )
            oItem:SubItems:Add( Convert.ToString( nOffset ) )
            nOffset += nFieldLen
            lv:Items:Add( oItem )
        NEXT

        oForm:Controls:Add( lv )
        oForm:Controls:Add( txt )
        oForm:ShowDialog( SELF )
        RETURN

    PRIVATE METHOD FormatSize( cFile AS STRING ) AS STRING
        LOCAL oInfo   := FileInfo{ cFile } AS FileInfo
        LOCAL nByte := oInfo:Length AS INT64
        LOCAL nMegaBytes   := nByte / 1048576.0 AS REAL8
        RETURN nByte:ToString( "#,0" ):Replace( ",", "'" ) + " Bytes (" + nMegaBytes:ToString( "0.00" ) + " MB)"

    // =====================================================================
    // Filter and scope
    // =====================================================================
    PUBLIC PROPERTY FilterText AS STRING GET SELF:cFilterText
    PUBLIC PROPERTY ScopeFrom   AS STRING GET SELF:cScopeFrom
    PUBLIC PROPERTY ScopeTo   AS STRING GET SELF:cScopeTo
    PUBLIC PROPERTY HasOrder   AS LOGIC  GET SELF:cmbOrder:SelectedIndex > 0

    /// <summary>Set the filter expression (empty = filter off). Needs the X# macro compiler.</summary>
    PUBLIC METHOD SetFilter( cExpression AS STRING ) AS LOGIC
        LOCAL nRec := SELF:CurrentRec() AS LONG
        cExpression := cExpression:Trim()
        IF cExpression:Length == 0
            SELF:oFilterCb   := NULL
            SELF:cFilterText := ""
            SELF:LoadList( nRec )
            RETURN TRUE
        ENDIF
        TRY
            SELF:Sel()
            LOCAL oCb := MCompile( cExpression ) AS OBJECT
            DbGoTop()
            LOCAL oTest := Eval( oCb ) AS OBJECT       // Trial run: must return LOGIC
            IF ! ( oTest IS LOGIC )
                MessageBox.Show( "The expression does not return a logical value (.T./.F.).", "Set Filter", MessageBoxButtons.OK, MessageBoxIcon.Warning )
                RETURN FALSE
            ENDIF
            SELF:oFilterCb   := oCb
            SELF:cFilterText := cExpression
        CATCH ex AS Exception
            MessageBox.Show( "Invalid filter expression:" + Environment.NewLine + ex:Message, "Set Filter", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN FALSE
        END TRY
        SELF:LoadList( nRec )
        RETURN TRUE

    /// <summary>Set the scope (from/to) in the active index; empty values = open</summary>
    PUBLIC METHOD SetScope( cFrom AS STRING, cTo AS STRING ) AS LOGIC
        LOCAL nRec := SELF:CurrentRec() AS LONG
        IF ! SELF:HasOrder .AND. ( cFrom:Length > 0 .OR. cTo:Length > 0 )
            MessageBox.Show( "For a scope, please select an order first.", "Order Scope" )
            RETURN FALSE
        ENDIF
        TRY
            SELF:oScopeFrom := SELF:oTable:ScopeValue( cFrom )
            SELF:oScopeTo := SELF:oTable:ScopeValue( cTo )
            SELF:cScopeFrom := cFrom
            SELF:cScopeTo := cTo
        CATCH ex AS Exception
            MessageBox.Show( "Invalid scope value: " + ex:Message, "Order Scope", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN FALSE
        END TRY
        SELF:LoadList( nRec )
        RETURN TRUE

    // =====================================================================
    // Index management (Index Manager)
    // =====================================================================
    /// <summary>List of the orders: name, expression, condition, index file</summary>
    PUBLIC METHOD GetOrders() AS List<STRING[]>
        LOCAL aList := List<STRING[]>{} AS List<STRING[]>
        SELF:Sel()
        FOR VAR i := 1 TO 200
            LOCAL cName := "" AS STRING
            TRY
                cName := ((STRING) OrdName( i )):Trim()
            CATCH
                cName := ""
            END TRY
            IF cName:Length == 0
                EXIT
            ENDIF
            LOCAL cKey := "", cFor := "", cBag := "" AS STRING
            TRY
                cKey := ((STRING) OrdKey( i )):Trim()
            CATCH
                NOP
            END TRY
            TRY
                cFor := ((STRING) OrdFor( i )):Trim()
            CATCH
                NOP
            END TRY
            TRY
                cBag := ((STRING) OrdBagName( i )):Trim()
            CATCH
                NOP
            END TRY
            aList:Add( <STRING>{ cName, cKey, cFor, cBag } )
        NEXT
        RETURN aList

    PRIVATE METHOD ExclusiveRequired( cAction AS STRING ) AS LOGIC
        IF SELF:lReadOnly .OR. ! SELF:lExclusive
            MessageBox.Show( cAction + " is only possible when the file is opened EXCLUSIVE and not read-only.", ;
                cAction, MessageBoxButtons.OK, MessageBoxIcon.Information )
            RETURN TRUE
        ENDIF
        RETURN FALSE

    /// <summary>Create a new order (CDX: in the production CDX, NTX: own file)</summary>
    PUBLIC METHOD NewOrder( cName AS STRING, cExpression AS STRING, cCondition AS STRING, lUnique AS LOGIC ) AS LOGIC
        IF SELF:ExclusiveRequired( "New order" )
            RETURN FALSE
        ENDIF
        LOCAL nRec := SELF:CurrentRec() AS LONG
        TRY
            SELF:Sel()
            LOCAL cBag AS STRING
            IF SELF:cDriver:ToUpper():Contains( "NTX" )
                cBag := Path.Combine( Path.GetDirectoryName( SELF:cFile ), cName + ".ntx" )
            ELSE
                cBag := Path.ChangeExtension( SELF:cFile, ".cdx" )
            ENDIF
            LOCAL cError := StructureRebuild.CreateOrder( cBag, cName, cExpression, cCondition, lUnique ) AS STRING
            IF cError:Length > 0
                MessageBox.Show( "The order could not be created:" + Environment.NewLine + cError, "New order", MessageBoxButtons.OK, MessageBoxIcon.Error )
                SELF:LoadOrders()
                RETURN FALSE
            ENDIF
            SELF:LoadOrders()
            // activate the new order
            FOR VAR i := 1 TO SELF:cmbOrder:Items:Count - 1
                IF String.Compare( (STRING) SELF:cmbOrder:Items[i], cName, TRUE ) == 0
                    SELF:cmbOrder:SelectedIndex := i
                ENDIF
            NEXT
        CATCH ex AS Exception
            MessageBox.Show( "The order could not be created:" + Environment.NewLine + ex:Message, "New order", MessageBoxButtons.OK, MessageBoxIcon.Error )
            RETURN FALSE
        END TRY
        SELF:LoadList( nRec )
        RETURN TRUE

    PUBLIC METHOD DeleteOrder( cName AS STRING, cBag AS STRING ) AS LOGIC
        IF SELF:ExclusiveRequired( "Delete order" )
            RETURN FALSE
        ENDIF
        LOCAL nRec := SELF:CurrentRec() AS LONG
        TRY
            SELF:Sel()
            OrdSetFocus( 0 )
            OrdDestroy( cName, cBag )
        CATCH ex AS Exception
            MessageBox.Show( "The order could not be deleted:" + Environment.NewLine + ex:Message, "Delete order", MessageBoxButtons.OK, MessageBoxIcon.Error )
        END TRY
        SELF:LoadOrders()
        SELF:LoadList( nRec )
        RETURN TRUE

    PUBLIC METHOD ReIndex() AS LOGIC
        IF SELF:ExclusiveRequired( "ReIndex" )
            RETURN FALSE
        ENDIF
        LOCAL nRec := SELF:CurrentRec() AS LONG
        TRY
            SELF:Cursor := Cursors.WaitCursor
            SELF:Sel()
            OrdListRebuild()
        CATCH ex AS Exception
            MessageBox.Show( "ReIndex failed:" + Environment.NewLine + ex:Message, "ReIndex", MessageBoxButtons.OK, MessageBoxIcon.Error )
        FINALLY
            SELF:Cursor := Cursors.Default
        END TRY
        SELF:LoadList( nRec )
        RETURN TRUE

    /// <summary>Rebuild the production CDX: remove all existing orders, create all orders of the list.
    /// aList: name, expression, condition, unique ("1"/"0"). Returns "" (OK) or the error message per order.</summary>
    PUBLIC METHOD CreateAllOrders( aList AS List<STRING[]> ) AS List<STRING>
        LOCAL aStatus := List<STRING>{} AS List<STRING>
        LOCAL nRec    := SELF:CurrentRec() AS LONG
        LOCAL cCdx    := Path.ChangeExtension( SELF:cFile, ".cdx" ) AS STRING
        LOCAL cBase  := Path.GetFileNameWithoutExtension( SELF:cFile ) AS STRING
        IF SELF:ExclusiveRequired( "Create indexes" )
            RETURN aStatus
        ENDIF
        IF SELF:cDriver:ToUpper():Contains( "NTX" )
            MessageBox.Show( "Recreating all orders is not yet supported for DBFNTX.", "Create indexes" )
            RETURN aStatus
        ENDIF
        SELF:Sel()
        // 1. remove the existing orders of the production CDX
        TRY
            OrdSetFocus( 0 )
        CATCH
            NOP
        END TRY
        FOREACH aOrd AS STRING[] IN SELF:GetOrders()
            LOCAL cBag := (STRING) aOrd:GetValue( 3 ) AS STRING
            IF cBag:Length == 0 .OR. String.Compare( Path.GetFileNameWithoutExtension( cBag ), cBase, TRUE ) == 0
                TRY
                    SELF:Sel()
                    OrdDestroy( (STRING) aOrd:GetValue( 0 ), IIF( cBag:Length == 0, cCdx, cBag ) )
                CATCH
                    NOP
                END TRY
            ENDIF
        NEXT
        // 2. create all orders of the list additively
        FOREACH aOrd AS STRING[] IN aList
            SELF:Sel()
            aStatus:Add( StructureRebuild.CreateOrder( cCdx, (STRING) aOrd:GetValue( 0 ), (STRING) aOrd:GetValue( 1 ), ;
                (STRING) aOrd:GetValue( 2 ), (STRING) aOrd:GetValue( 3 ) == "1" ) )
        NEXT
        SELF:LoadOrders()
        SELF:LoadList( nRec )
        RETURN aStatus

    // for dialogs that work in this workarea (e.g. create indexes)
    PUBLIC METHOD SelectArea() AS VOID
        SELF:Sel()
        RETURN

    PUBLIC METHOD AfterIndexChange() AS VOID
        LOCAL nRec := SELF:CurrentRec() AS LONG
        SELF:LoadOrders()
        SELF:LoadList( nRec )
        RETURN

    PUBLIC METHOD ActivateOrder( cName AS STRING ) AS VOID
        FOR VAR i := 1 TO SELF:cmbOrder:Items:Count - 1
            IF String.Compare( (STRING) SELF:cmbOrder:Items[i], cName, TRUE ) == 0
                SELF:cmbOrder:SelectedIndex := i
            ENDIF
        NEXT
        RETURN

    PUBLIC METHOD FocusOrder() AS VOID
        SELF:cmbOrder:Focus()
        SELF:cmbOrder:DroppedDown := TRUE
        RETURN

    // =====================================================================
    // Form view (one record, all fields below each other)
    // =====================================================================
    PUBLIC PROPERTY IsFormView AS LOGIC GET SELF:lFormView

    PUBLIC METHOD ShowFormView( lForm AS LOGIC ) AS VOID
        IF lForm == SELF:lFormView
            RETURN
        ENDIF
        IF lForm
            SELF:nFormRow := Math.Max( 0, SELF:CurrentRow() )
            IF SELF:aFormBox:Count == 0
                SELF:BuildFormView()
            ENDIF
            SELF:lFormView := TRUE
            SELF:grid:Visible    := FALSE
            SELF:pnlFormView:Visible := TRUE
            SELF:FillFormView()
        ELSE
            LOCAL nRow := SELF:nFormRow AS INT
            SELF:lFormView := FALSE
            SELF:pnlFormView:Visible := FALSE
            SELF:grid:Visible    := TRUE
            SELF:ClearCache()
            SELF:grid:Invalidate()
            SELF:GoToCloseRow( nRow )
            SELF:grid:Focus()
        ENDIF
        RETURN

    PRIVATE METHOD BuildFormView() AS VOID
        LOCAL nY := 10 AS INT
        SELF:pnlFormView:SuspendLayout()
        FOR VAR i := 1 TO SELF:nFields
            LOCAL cType := SELF:aFieldType[i - 1] AS STRING
            LOCAL nLen := (INT) (LONG) SELF:oRdd:FieldInfo( i, DBS_LEN, NULL ) AS INT
            LOCAL lbl := Label{} AS Label
            lbl:Text      := SELF:aFieldName[i - 1]
            lbl:Location  := Point{ 10, nY + 3 }
            lbl:Size      := Size{ 110, 16 }
            lbl:TextAlign := ContentAlignment.MiddleRight
            LOCAL txt := TextBox{} AS TextBox
            txt:Location := Point{ 125, nY }
            txt:Tag      := i - 1
            txt:Font     := Font{ "Microsoft Sans Serif", 8.25 }
            IF cType == "M"
                txt:Multiline  := TRUE
                txt:ScrollBars := ScrollBars.Vertical
                txt:ReadOnly   := TRUE
                txt:Size       := Size{ 500, 60 }
                txt:DoubleClick += EventHandler{ SELF, @FormMemo_DoubleClick() }
                nY += 66
            ELSE
                txt:Size     := Size{ Math.Max( 60, Math.Min( 500, nLen * 7 + 12 ) ), 20 }
                txt:ReadOnly := SELF:lReadOnly .OR. SELF:aFieldAuto[i - 1] .OR. SELF:IsBinaryChar( i - 1 )
                IF SELF:IsBinaryChar( i - 1 )
                    txt:DoubleClick += EventHandler{ SELF, @FormBinary_DoubleClick() }
                ENDIF
                txt:Leave   += EventHandler{ SELF, @FormField_Leave() }
                txt:KeyDown += KeyEventHandler{ SELF, @FormField_KeyDown() }
                nY += 24
            ENDIF
            SELF:pnlFormView:Controls:Add( lbl )
            SELF:pnlFormView:Controls:Add( txt )
            SELF:aFormBox:Add( txt )
        NEXT
        SELF:pnlFormView:ResumeLayout()
        RETURN

    PRIVATE METHOD FillFormView() AS VOID
        IF SELF:aFormBox:Count == 0
            RETURN
        ENDIF
        SELF:lFormFill := TRUE
        IF SELF:nFormRow < 0 .OR. SELF:nFormRow >= SELF:aRecs:Count
            FOREACH txt AS TextBox IN SELF:aFormBox
                txt:Text := ""
                txt:Modified := FALSE
            NEXT
        ELSE
            LOCAL nRec := SELF:aRecs[SELF:nFormRow] AS LONG
            SELF:ClearCache()
            SELF:LoadCache( nRec, TRUE )
            FOR VAR i := 0 TO SELF:aFormBox:Count - 1
                LOCAL txt := SELF:aFormBox[i] AS TextBox
                IF SELF:aFieldType[i] == "M"
                    LOCAL oValue := SELF:aCache[i] AS OBJECT
                    txt:Text := IIF( oValue == NULL, "", oValue:ToString():TrimEnd() )
                ELSE
                    txt:Text := SELF:Display( i )
                ENDIF
                txt:Modified := FALSE
                txt:BackColor := IIF( SELF:lCacheDel, Color.Gainsboro, SystemColors.Window )
            NEXT
        ENDIF
        SELF:lFormFill := FALSE
        RETURN

    // Leaving a field: write the changed value immediately
    PRIVATE METHOD FormField_Leave( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL txt := (TextBox) sender AS TextBox
        IF SELF:lFormFill .OR. ! txt:Modified .OR. SELF:nFormRow < 0 .OR. SELF:nFormRow >= SELF:aRecs:Count
            RETURN
        ENDIF
        LOCAL nIdx := (INT) txt:Tag AS INT
        LOCAL nRec := SELF:aRecs[SELF:nFormRow] AS LONG
        txt:Modified := FALSE
        IF SELF:WriteField( nRec, nIdx, txt:Text )
            IF SELF:IsKeyField( nIdx )
                SELF:LoadList( nRec )
            ELSE
                SELF:FillFormView()
            ENDIF
        ELSE
            SELF:FillFormView()
        ENDIF
        RETURN

    // Enter = next field (like Tab)
    PRIVATE METHOD FormField_KeyDown( sender AS OBJECT, e AS KeyEventArgs ) AS VOID
        IF e:KeyCode == Keys.Enter
            e:SuppressKeyPress := TRUE
            SELF:pnlFormView:SelectNextControl( (Control) sender, TRUE, TRUE, TRUE, TRUE )
        ENDIF
        RETURN

    PRIVATE METHOD FormMemo_DoubleClick( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:nFormRow >= 0
            SELF:OpenMemo( SELF:nFormRow, (INT) ((TextBox) sender):Tag )
        ENDIF
        RETURN

    PRIVATE METHOD MakeButton_Form( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:ShowFormView( TRUE )
        RETURN

    PRIVATE METHOD MakeButton_Browse( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:ShowFormView( FALSE )
        RETURN

    // =====================================================================
    // Stage 3: Pack, Zap, DBReplace, FPT analysis
    // =====================================================================
    // Natural order: with an active order (with FOR condition) records that are not in the index would be missing
    PUBLIC METHOD CountDeleted() AS INT
        SELF:SyncOrder()
        RETURN SELF:oTable:CountDeleted()

    PUBLIC METHOD Zap() AS VOID
        IF SELF:ExclusiveRequired( "Zap" )
            RETURN
        ENDIF
        LOCAL cName := Path.GetFileNameWithoutExtension( SELF:cFile ):ToUpper() AS STRING
        SELF:Sel()
        IF MessageBox.Show( "All " + Convert.ToString( (LONG) LastRec() ) + " records of " + cName + " will be deleted permanently (Zap). Continue?", ;
            "Zap", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2 ) != DialogResult.Yes
            RETURN
        ENDIF
        TRY
            SELF:Sel()
            DbZap()
        CATCH ex AS Exception
            MessageBox.Show( "Zap failed: " + ex:Message, "Zap", MessageBoxButtons.OK, MessageBoxIcon.Error )
        END TRY
        SELF:LoadList( 0 )
        RETURN

    PUBLIC METHOD ReplaceValues() AS VOID
        IF SELF:ReadOnlyMessage()
            RETURN
        ENDIF
        LOCAL dlg := ReplaceDialog{ SELF:aFieldName, SELF:aRecs:Count } AS ReplaceDialog
        IF dlg:ShowDialog( SELF ) != DialogResult.OK .OR. dlg:FieldName == NULL
            RETURN
        ENDIF
        LOCAL nIdx  := SELF:aFieldName:IndexOf( dlg:FieldName ) AS INT
        LOCAL cType  := SELF:aFieldType[nIdx] AS STRING
        LOCAL oCb   := NULL AS OBJECT
        LOCAL oFor  := NULL AS OBJECT
        LOCAL oFixed := NULL AS OBJECT
        TRY
            SELF:Sel()
            IF dlg:IsExpression
                oCb := MCompile( dlg:InputValue )
            ELSE
                oFixed := SELF:ConvertText( dlg:InputValue, IIF( cType == "M", "C", cType ) )
            ENDIF
            IF dlg:Condition:Length > 0
                oFor := MCompile( dlg:Condition )
            ENDIF
        CATCH ex AS Exception
            MessageBox.Show( "Invalid value or expression: " + ex:Message, "DBReplace", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN
        END TRY
        LOCAL aTarget := List<LONG>{} AS List<LONG>
        IF dlg:OnlyCurrent
            IF SELF:CurrentRec() > 0
                aTarget:Add( SELF:CurrentRec() )
            ENDIF
        ELSE
            aTarget:AddRange( SELF:aRecs )
            IF MessageBox.Show( "Field " + dlg:FieldName + " in up to " + Convert.ToString( aTarget:Count ) + " records: replace?", "DBReplace", ;
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question ) != DialogResult.Yes
                RETURN
            ENDIF
        ENDIF
        LOCAL nNum := 0, nLocked := 0, nError := 0 AS INT
        LOCAL cError := "" AS STRING
        SELF:Cursor := Cursors.WaitCursor
        TRY
            SELF:Sel()
            FOREACH nRec AS LONG IN aTarget
                DbGoto( nRec )
                IF oFor != NULL
                    LOCAL lMatches := FALSE AS LOGIC
                    TRY
                        lMatches := (LOGIC) Eval( oFor )
                    CATCH
                        lMatches := FALSE
                    END TRY
                    IF ! lMatches
                        LOOP
                    ENDIF
                ENDIF
                IF ! SELF:lExclusive .AND. ! DbRLock( nRec )
                    nLocked++
                    LOOP
                ENDIF
                TRY
                    LOCAL oNew := IIF( oCb != NULL, (OBJECT) Eval( oCb ), oFixed ) AS OBJECT
                    FieldPut( nIdx + 1, oNew )
                    nNum++
                CATCH ex AS Exception
                    nError++
                    cError := ex:Message
                END TRY
            NEXT
            DbCommit()
            IF ! SELF:lExclusive
                DbUnlock()
            ENDIF
        FINALLY
            SELF:Cursor := Cursors.Default
        END TRY
        SELF:RefreshView()
        MessageBox.Show( Convert.ToString( nNum ) + " records replaced." + ;
            IIF( nLocked > 0, Environment.NewLine + Convert.ToString( nLocked ) + " records locked (not changed).", "" ) + ;
            IIF( nError > 0, Environment.NewLine + Convert.ToString( nError ) + " errors, last: " + cError, "" ), "DBReplace" )
        RETURN

    // =====================================================================
    // JSON export
    // =====================================================================
    /// <summary>Value for the JSON writer: RDD wrapper types become plain .NET values, an empty date becomes null</summary>
    PRIVATE STATIC METHOD JsonValue( oValue AS OBJECT ) AS OBJECT
        IF oValue == NULL .OR. oValue IS System.DBNull
            RETURN NULL
        ENDIF
        IF oValue IS IDate
            LOCAL oDate := (IDate) oValue AS IDate
            IF oDate:IsEmpty
                RETURN NULL
            ENDIF
            RETURN DateTime{ oDate:Year, oDate:Month, oDate:Day }
        ENDIF
        IF oValue IS DateTime .AND. (DateTime) oValue == DateTime.MinValue
            RETURN NULL
        ENDIF
        IF oValue IS DbFloat
            RETURN ((DbFloat) oValue):Value
        ENDIF
        RETURN oValue

    /// <summary>Writes the records to a JSON file (Newtonsoft.Json): an array with one object per record
    /// ("Deleted", "RecNo", then the fields). lAll = all records of the file in natural order,
    /// otherwise the records of the current view (order, filter, scope). Returns the number of records written.</summary>
    PUBLIC METHOD WriteJson( cFileName AS STRING, lAll AS LOGIC ) AS INT
        LOCAL nCount := 0 AS INT
        LOCAL aExport := List<LONG>{} AS List<LONG>
        // a field may be called DELETED or RECNO : keep the meta keys apart
        LOCAL cKeyDeleted := IIF( SELF:aFieldName:Contains( "DELETED" ), "_Deleted", "Deleted" ) AS STRING
        LOCAL cKeyRecno   := IIF( SELF:aFieldName:Contains( "RECNO" ), "_RecNo", "RecNo" ) AS STRING
        SELF:Sel()
        IF lAll
            FOR VAR nRec := 1 TO (LONG) LastRec()
                aExport:Add( nRec )
            NEXT
        ELSE
            aExport:AddRange( SELF:aRecs )
        ENDIF
        LOCAL w := StreamWriter{ cFileName, FALSE, System.Text.UTF8Encoding{ FALSE } } AS StreamWriter
        TRY
            LOCAL jw := Newtonsoft.Json.JsonTextWriter{ w } AS Newtonsoft.Json.JsonTextWriter
            jw:Formatting := Newtonsoft.Json.Formatting.Indented
            jw:WriteStartArray()
            FOR VAR i := 0 TO aExport:Count - 1
                DbGoto( aExport[i] )
                jw:WriteStartObject()
                jw:WritePropertyName( cKeyDeleted )
                jw:WriteValue( IIF( Deleted(), "*", " " ) )
                jw:WritePropertyName( cKeyRecno )
                jw:WriteValue( (LONG) RecNo() )
                FOR VAR f := 1 TO SELF:nFields
                    LOCAL oValue := NULL AS OBJECT
                    TRY
                        oValue := SELF:oRdd:GetValue( f )
                    CATCH
                        oValue := NULL
                    END TRY
                    jw:WritePropertyName( SELF:aFieldName[f - 1] )
                    jw:WriteValue( JsonValue( oValue ) )
                NEXT
                jw:WriteEndObject()
                nCount++
            NEXT
            jw:WriteEndArray()
            jw:Flush()
        FINALLY
            w:Close()
        END TRY
        RETURN nCount
    /// <summary>Utils - Export JSON: asks for the file (and, for a restricted view, for the record set)</summary>
    PUBLIC METHOD ExportJson() AS VOID
        LOCAL lAll := FALSE AS LOGIC
        IF SELF:cFilterText:Length > 0 .OR. SELF:oScopeFrom != NULL .OR. SELF:oScopeTo != NULL .OR. SELF:lOnlyDeleted .OR. ! SELF:lShowDeleted
            SELF:Sel()
            LOCAL answer := MessageBox.Show( "The current view is restricted (filter, scope or hidden deleted records)." + Environment.NewLine + Environment.NewLine + ;
                "Yes = export the " + Convert.ToString( SELF:aRecs:Count ) + " records of the current view" + Environment.NewLine + ;
                "No = export all " + Convert.ToString( (LONG) LastRec() ) + " records of the file", ;
                "Export JSON", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question ) AS DialogResult
            IF answer == DialogResult.Cancel
                RETURN
            ENDIF
            lAll := ( answer == DialogResult.No )
        ENDIF
        LOCAL sfd := SaveFileDialog{} AS SaveFileDialog
        sfd:Title := "Export to JSON"
        sfd:DefaultExt := "json"
        sfd:Filter := "JSON files (*.json)|*.json|All files (*.*)|*.*"
        sfd:FileName := Path.GetFileNameWithoutExtension( SELF:cFile ) + ".json"
        sfd:InitialDirectory := Path.GetDirectoryName( SELF:cFile )
        IF sfd:ShowDialog( SELF ) != DialogResult.OK
            RETURN
        ENDIF
        LOCAL nCount := 0 AS INT
        SELF:Cursor := Cursors.WaitCursor
        TRY
            nCount := SELF:WriteJson( sfd:FileName, lAll )
        CATCH ex AS Exception
            SELF:Cursor := Cursors.Default
            MessageBox.Show( "The export failed:" + Environment.NewLine + ex:Message, "Export JSON", MessageBoxButtons.OK, MessageBoxIcon.Error )
            RETURN
        FINALLY
            SELF:Cursor := Cursors.Default
        END TRY
        MessageBox.Show( Convert.ToString( nCount ) + " records exported to " + sfd:FileName, "Export JSON", MessageBoxButtons.OK, MessageBoxIcon.Information )
        RETURN

    PUBLIC METHOD FptReport() AS VOID
        LOCAL cText := "" AS STRING
        IF SELF:lExclusive
            MessageBox.Show( "The FPT analysis reads DBF and FPT directly from disk." + Environment.NewLine + ;
                "The file must be opened SHARED for this - please close the window and reopen the file shared.", ;
                "FPT Analysis", MessageBoxButtons.OK, MessageBoxIcon.Information )
            RETURN
        ENDIF
        SELF:Commit()
        SELF:Cursor := Cursors.WaitCursor
        TRY
            cText := FptAnalysis.Report( SELF:cFile )
        CATCH ex AS IOException
            SELF:Cursor := Cursors.Default
            MessageBox.Show( "The file cannot be read (opened exclusively?):" + Environment.NewLine + ex:Message, ;
                "FPT Analysis", MessageBoxButtons.OK, MessageBoxIcon.Warning )
            RETURN
        FINALLY
            SELF:Cursor := Cursors.Default
        END TRY
        LOCAL oF := TextWindow{ "FPT Analysis - " + Path.GetFileName( SELF:cFile ), cText } AS TextWindow
        oF:ShowDialog( SELF )
        RETURN

    // =====================================================================
    // Toolbar buttons
    // =====================================================================
    PRIVATE METHOD MakeButton_Append( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:AppendRecord()
        RETURN
    PRIVATE METHOD MakeButton_Delete( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:DeleteRecord( TRUE )
        RETURN
    PRIVATE METHOD MakeButton_Recall( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:DeleteRecord( FALSE )
        RETURN
    PRIVATE METHOD MakeButton_Copy( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:CopyRecord( FALSE )
        RETURN
    PRIVATE METHOD MakeButton_PasteAppend( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:PasteAppend( FALSE )
        RETURN
    PRIVATE METHOD MakeButton_Refresh( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:RefreshView()
        RETURN
    PRIVATE METHOD MakeButton_Structure( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:ShowStructure()
        RETURN

    PRIVATE METHOD MakeButton_Hex( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:ShowHex()
        RETURN

END CLASS


/// <summary>DataGridView with Enter behaviour like in the dBAdministrator:
/// Enter = edit cell, Enter in edit mode = save and stay in the cell</summary>
PUBLIC CLASS DbGrid INHERIT DataGridView
    PUBLIC EnterAction AS Action

    // Simple accessibility object: prevents assistive tools (on-screen keyboard,
    // remote desktop, screen reader) query all rows on every cell change
    PROTECTED OVERRIDE METHOD CreateAccessibilityInstance() AS AccessibleObject
        RETURN Control.ControlAccessibleObject{ SELF }

    PROTECTED OVERRIDE METHOD ProcessDialogKey( keyData AS Keys ) AS LOGIC
        IF keyData == Keys.Enter .AND. SELF:IsCurrentCellInEditMode
            SELF:EndEdit()
            RETURN TRUE
        ENDIF
        RETURN SUPER:ProcessDialogKey( keyData )

    PROTECTED OVERRIDE METHOD ProcessDataGridViewKey( e AS KeyEventArgs ) AS LOGIC
        IF e:KeyData == Keys.Enter .AND. ! SELF:IsCurrentCellInEditMode
            IF SELF:EnterAction != NULL
                SELF:EnterAction:Invoke()
            ENDIF
            RETURN TRUE
        ENDIF
        RETURN SUPER:ProcessDataGridViewKey( e )
END CLASS

END NAMESPACE
