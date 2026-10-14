USING System
USING System.IO
USING System.Drawing
USING System.Globalization
USING System.Collections.Generic
USING System.Windows.Forms
USING XSharp
USING XSharp.RDD
USING XSharp.RDD.Support

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>Field definition for the structure rebuild; AltName = field in the old file ("" = new field)</summary>
PUBLIC CLASS FieldDef
    PUBLIC Name    AS STRING
    PUBLIC FieldType     AS STRING
    PUBLIC Length  AS INT
    PUBLIC Dec     AS INT
    PUBLIC OldName AS STRING
    // Part of the RDD type after the ":" (flags like B = binary, + = AutoIncrement, N = nullable)
    PUBLIC Extra  AS STRING
    PUBLIC PROPERTY TypeFull AS STRING GET SELF:FieldType + IIF( SELF:Extra:Length > 0, ":" + SELF:Extra, "" )
    PUBLIC CONSTRUCTOR( cName AS STRING, cType AS STRING, nLen AS INT, nDec AS INT, cOld AS STRING )
        SELF:Name    := cName:ToUpper()
        SELF:FieldType     := cType:ToUpper()
        SELF:Length  := nLen
        SELF:Dec     := nDec
        SELF:OldName := cOld:ToUpper()
        SELF:Extra  := ""
        RETURN

    /// <summary>Read a field definition from the opened workarea, including the flags (AutoIncrement ...)</summary>
    PUBLIC STATIC METHOD FromRdd( oRdd AS IRdd, nPos AS INT ) AS FieldDef
        LOCAL cFull   := (STRING) oRdd:FieldInfo( nPos, DBS_TYPE, NULL ) AS STRING
        LOCAL cExtra := "" AS STRING
        LOCAL nColon     := cFull:IndexOf( ':' ) AS INT
        IF nColon > 0
            cExtra := cFull:Substring( nColon + 1 )
        ENDIF
        LOCAL f := FieldDef{ oRdd:FieldName( nPos ), cFull:Substring( 0, 1 ), ;
            (INT) (LONG) oRdd:FieldInfo( nPos, DBS_LEN, NULL ), (INT) (LONG) oRdd:FieldInfo( nPos, DBS_DEC, NULL ), ;
            oRdd:FieldName( nPos ) } AS FieldDef
        f:Extra := cExtra
        RETURN f
END CLASS


/// <summary>Modify Structure for an existing DBF (the data is kept)</summary>
PUBLIC CLASS StructureDialog INHERIT System.Windows.Forms.Form
    PRIVATE cFile  AS STRING
    PRIVATE cDriver AS STRING
    PRIVATE lv      AS ListView
    PRIVATE aFields := List<FieldDef>{} AS List<FieldDef>
    PUBLIC  Loaded := FALSE AS LOGIC
    PUBLIC  Rebuilt := FALSE AS LOGIC

    PUBLIC CONSTRUCTOR( cFile AS STRING, cRdd AS STRING )
        SELF:cFile  := cFile
        SELF:cDriver := cRdd
        SELF:Text          := "Modify Structure - " + Path.GetFileName( cFile )
        SELF:Size          := Size{ 560, 520 }
        SELF:StartPosition := FormStartPosition.CenterParent
        SELF:ShowInTaskbar := FALSE
        SELF:MinimizeBox   := FALSE
        SELF:Font          := Font{ "Microsoft Sans Serif", 8.25 }

        SELF:lv := ListView{}
        SELF:lv:View          := View.Details
        SELF:lv:FullRowSelect := TRUE
        SELF:lv:GridLines     := TRUE
        SELF:lv:MultiSelect   := FALSE
        SELF:lv:HideSelection := FALSE
        SELF:lv:Dock          := DockStyle.Fill
        SELF:lv:Columns:Add( "Nr", 40, HorizontalAlignment.Right )
        SELF:lv:Columns:Add( "Field name", 120 )
        SELF:lv:Columns:Add( "Type", 40 )
        SELF:lv:Columns:Add( "Length", 60, HorizontalAlignment.Right )
        SELF:lv:Columns:Add( "Dec", 40, HorizontalAlignment.Right )
        SELF:lv:Columns:Add( "previous", 110 )
        SELF:lv:DoubleClick += EventHandler{ SELF, @Change_Click() }

        LOCAL pnl := FlowLayoutPanel{} AS FlowLayoutPanel
        pnl:Dock          := DockStyle.Right
        pnl:Width         := 125
        pnl:FlowDirection := FlowDirection.TopDown
        pnl:Padding       := Padding{ 6 }
        pnl:Controls:Add( SELF:MakeButton( "New field...",  EventHandler{ SELF, @New_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Change...",     EventHandler{ SELF, @Change_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Delete",       EventHandler{ SELF, @DeleteRecord_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Move up",      EventHandler{ SELF, @Up_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Move down",     EventHandler{ SELF, @Down_Click() } ) )
        LOCAL lblEmpty := Label{} AS Label
        lblEmpty:Height := 20
        pnl:Controls:Add( lblEmpty )
        pnl:Controls:Add( SELF:MakeButton( "Rebuild",        EventHandler{ SELF, @Rebuild_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Cancel",      EventHandler{ SELF, @Cancel_Click() } ) )

        SELF:Controls:Add( SELF:lv )
        SELF:Controls:Add( pnl )

        SELF:Loaded := SELF:LoadStructure()
        RETURN

    PRIVATE METHOD MakeButton( cText AS STRING, oHandler AS EventHandler ) AS Button
        LOCAL b := Button{} AS Button
        b:Text   := cText
        b:Width  := 108
        b:Height := 26
        b:Click += oHandler
        RETURN b

    // read the existing structure (open the file briefly exclusive, read only)
    PRIVATE METHOD LoadStructure() AS LOGIC
        LOCAL oResult := NULL AS OBJECT
        TRY
            IF ! DbUseArea( TRUE, SELF:cDriver, SELF:cFile, "STRUCTREAD", FALSE, TRUE )
                MessageBox.Show( "The file could not be opened exclusively (used by another program?).", SELF:Text )
                RETURN FALSE
            ENDIF
            CoreDb.Info( DBI_RDD_OBJECT, REF oResult )
            LOCAL oRdd := (IRdd) oResult AS IRdd
            FOR VAR i := 1 TO oRdd:FieldCount
                SELF:aFields:Add( FieldDef.FromRdd( oRdd, i ) )
            NEXT
            DbCloseArea()
        CATCH ex AS Exception
            MessageBox.Show( "The structure could not be read:" + Environment.NewLine + ex:Message, SELF:Text )
            RETURN FALSE
        END TRY
        SELF:RefreshList( 0 )
        RETURN TRUE

    PRIVATE METHOD RefreshList( nChoice AS INT ) AS VOID
        SELF:lv:BeginUpdate()
        SELF:lv:Items:Clear()
        FOR VAR i := 0 TO SELF:aFields:Count - 1
            LOCAL f := SELF:aFields[i] AS FieldDef
            LOCAL oItem := ListViewItem{ Convert.ToString( i + 1 ) } AS ListViewItem
            oItem:SubItems:Add( f:Name )
            oItem:SubItems:Add( f:TypeFull )
            oItem:SubItems:Add( Convert.ToString( f:Length ) )
            oItem:SubItems:Add( Convert.ToString( f:Dec ) )
            oItem:SubItems:Add( IIF( f:OldName:Length == 0, "(new)", IIF( f:OldName == f:Name, "", f:OldName ) ) )
            SELF:lv:Items:Add( oItem )
        NEXT
        SELF:lv:EndUpdate()
        IF nChoice >= 0 .AND. nChoice < SELF:lv:Items:Count
            SELF:lv:Items[nChoice]:Selected := TRUE
            SELF:lv:Items[nChoice]:EnsureVisible()
        ENDIF
        RETURN

    PRIVATE METHOD Selection() AS INT
        IF SELF:lv:SelectedIndices:Count == 0
            RETURN -1
        ENDIF
        RETURN SELF:lv:SelectedIndices[0]

    // Use the FieldWindow from FabDBFEd for the input
    PRIVATE METHOD FieldInput( f AS FieldDef ) AS LOGIC
        LOCAL fw := FieldWindow{} AS FieldWindow
        LOCAL cTypeOld := f:FieldType AS STRING
        fw:FillTypeCombo( SELF:cDriver )
        fw:FieldName     := f:Name
        fw:FieldType     := f:FieldType           // sets the length to the default -> set the length afterwards
        fw:FieldLength   := Convert.ToString( f:Length )
        fw:FieldDecimals := Convert.ToString( f:Dec )
        IF fw:ShowDialog( SELF ) != DialogResult.OK
            RETURN FALSE
        ENDIF
        f:Name   := fw:FieldName:Trim():ToUpper()
        f:FieldType    := fw:FieldType:ToUpper()
        IF f:FieldType != cTypeOld
            f:Extra := ""              // Flags belong to the old type (e.g. AutoIncrement)
        ENDIF
        f:Length := Convert.ToInt32( fw:FieldLength )
        f:Dec    := Convert.ToInt32( fw:FieldDecimals )
        RETURN TRUE

    PRIVATE METHOD New_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL f := FieldDef{ "", "C", 10, 0, "" } AS FieldDef
        IF SELF:FieldInput( f )
            LOCAL n := SELF:Selection() AS INT
            IF n < 0
                SELF:aFields:Add( f )
                n := SELF:aFields:Count - 1
            ELSE
                n++
                SELF:aFields:Insert( n, f )
            ENDIF
            SELF:RefreshList( n )
        ENDIF
        RETURN

    PRIVATE METHOD Change_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL n := SELF:Selection() AS INT
        IF n >= 0 .AND. SELF:FieldInput( SELF:aFields[n] )
            SELF:RefreshList( n )
        ENDIF
        RETURN

    PRIVATE METHOD DeleteRecord_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL n := SELF:Selection() AS INT
        IF n >= 0
            IF MessageBox.Show( "Field " + SELF:aFields[n]:Name + ": remove it? The data of this field is lost during the rebuild.", ;
                    SELF:Text, MessageBoxButtons.YesNo, MessageBoxIcon.Warning ) == DialogResult.Yes
                SELF:aFields:RemoveAt( n )
                SELF:RefreshList( Math.Min( n, SELF:aFields:Count - 1 ) )
            ENDIF
        ENDIF
        RETURN

    PRIVATE METHOD Up_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL n := SELF:Selection() AS INT
        IF n > 0
            LOCAL f := SELF:aFields[n] AS FieldDef
            SELF:aFields:RemoveAt( n )
            SELF:aFields:Insert( n - 1, f )
            SELF:RefreshList( n - 1 )
        ENDIF
        RETURN

    PRIVATE METHOD Down_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL n := SELF:Selection() AS INT
        IF n >= 0 .AND. n < SELF:aFields:Count - 1
            LOCAL f := SELF:aFields[n] AS FieldDef
            SELF:aFields:RemoveAt( n )
            SELF:aFields:Insert( n + 1, f )
            SELF:RefreshList( n + 1 )
        ENDIF
        RETURN

    PRIVATE METHOD Cancel_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:Close()
        RETURN

    PRIVATE METHOD Rebuild_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        // Checks
        IF SELF:aFields:Count == 0
            MessageBox.Show( "At least one field is required.", SELF:Text )
            RETURN
        ENDIF
        LOCAL aNames := List<STRING>{} AS List<STRING>
        FOREACH f AS FieldDef IN SELF:aFields
            IF f:Name:Length == 0 .OR. f:Name:Length > 10 .OR. aNames:Contains( f:Name )
                MessageBox.Show( "Field name invalid or duplicate: '" + f:Name + "'", SELF:Text )
                RETURN
            ENDIF
            aNames:Add( f:Name )
        NEXT
        IF MessageBox.Show( "The file will now be rebuilt." + Environment.NewLine + ;
                "Deleted records are NOT taken over (the record numbers change as a result)." + Environment.NewLine + ;
                "The previous file is kept as a backup  *_OLD_<date>.*  in the same folder." + Environment.NewLine + Environment.NewLine + ;
                "Continue?", SELF:Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question ) != DialogResult.Yes
            RETURN
        ENDIF
        LOCAL cMessage := "" AS STRING
        LOCAL aOrders  := List<STRING[]>{} AS List<STRING[]>
        SELF:Cursor := Cursors.WaitCursor
        TRY
            SELF:Rebuilt := StructureRebuild.Execute( SELF:cFile, SELF:cDriver, SELF:aFields, REF cMessage, REF aOrders )
        FINALLY
            SELF:Cursor := Cursors.Default
        END TRY
        MessageBox.Show( cMessage, SELF:Text, MessageBoxButtons.OK, IIF( SELF:Rebuilt, MessageBoxIcon.Information, MessageBoxIcon.Error ) )
        IF SELF:Rebuilt
            // as in the VO tool: show the existing indexes and recreate them with "Create"
            IF aOrders:Count > 0
                LOCAL dlg := NewIndexDialog{ SELF:cFile, SELF:cDriver, aOrders, NULL } AS NewIndexDialog
                dlg:ShowDialog( SELF )
            ENDIF
            SELF:Close()
        ENDIF
        RETURN
END CLASS


/// <summary>Performs the rebuild: new DBF, copy the data, backup, recreate the indexes</summary>
PUBLIC STATIC CLASS StructureRebuild

    PUBLIC STATIC METHOD Execute( cFile AS STRING, cDriver AS STRING, aFields AS List<FieldDef>, cMessage REF STRING, aOrdersFrom REF List<STRING[]> ) AS LOGIC
        LOCAL cFolder  := Path.GetDirectoryName( cFile ) AS STRING
        LOCAL cBase   := Path.GetFileNameWithoutExtension( cFile ) AS STRING
        LOCAL cExtension  := IIF( Path.GetExtension( cFile ):Length == 0, ".dbf", Path.GetExtension( cFile ) ) AS STRING
        LOCAL cNew     := Path.Combine( cFolder, cBase + "_NEW_TMP" + cExtension ) AS STRING
        LOCAL aOrders  := List<STRING[]>{} AS List<STRING[]>
        LOCAL aOther  := List<STRING>{} AS List<STRING>
        LOCAL nRecords  := 0 AS INT
        LOCAL nError  := 0 AS INT
        LOCAL nRemoved     := 0 AS INT
        LOCAL oResult  := NULL AS OBJECT
        LOCAL nOldArea := 0 AS DWORD
        LOCAL nNewArea := 0 AS DWORD
        LOCAL lNtx     := cDriver:ToUpper():Contains( "NTX" ) AS LOGIC

        // ---- 1. create the new file ----
        TRY
            StructureRebuild.DeleteFiles( cNew )
            LOCAL aInfo := List<RddFieldInfo>{} AS List<RddFieldInfo>
            FOREACH f AS FieldDef IN aFields
                aInfo:Add( RddFieldInfo{ f:Name, f:TypeFull, f:Length, f:Dec } )
            NEXT
            IF ! CoreDb.Create( cNew, aInfo:ToArray(), cDriver, TRUE, "STRUCTNEW", "", FALSE, FALSE )
                cMessage := "The new file could not be created."
                RETURN FALSE
            ENDIF
        CATCH ex AS Exception
            cMessage := "Error creating the new file:" + Environment.NewLine + ex:Message
            RETURN FALSE
        END TRY

        // ---- 2. open the old file exclusively, remember the orders, copy the data ----
        TRY
            IF ! DbUseArea( TRUE, cDriver, cFile, "STRUCTOLD", FALSE, TRUE )
                cMessage := "The previous file could not be opened exclusively."
                StructureRebuild.DeleteFiles( cNew )
                RETURN FALSE
            ENDIF
            CoreDb.Info( DBI_RDD_OBJECT, REF oResult )
            LOCAL oOld := (IRdd) oResult AS IRdd
            nOldArea := (DWORD) oOld:Area

            // Remember the orders of the production CDX (name, expression, condition, unique)
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
                LOCAL cKey := "", cFor := "", cBag := "", cUni := "0" AS STRING
                // read each item separately so that an error does not discard the whole order
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
                TRY
                    cUni := IIF( (LOGIC) DbOrderInfo( DBOI_UNIQUE, "", i ), "1", "0" )
                CATCH
                    NOP
                END TRY
                IF ! lNtx .AND. ( cBag:Length == 0 .OR. String.Compare( Path.GetFileNameWithoutExtension( cBag ), cBase, TRUE ) == 0 )
                    aOrders:Add( <STRING>{ cName, cKey, cFor, cUni } )
                ELSEIF ! aOther:Contains( cBag )
                    aOther:Add( cBag )
                ENDIF
            NEXT
            OrdSetFocus( 0 )

            // Mapping new field position -> old field position
            LOCAL aSource := List<INT>{} AS List<INT>
            FOREACH f AS FieldDef IN aFields
                LOCAL nOld := 0 AS INT
                IF f:OldName:Length > 0
                    FOR VAR j := 1 TO oOld:FieldCount
                        IF String.Compare( oOld:FieldName( j ), f:OldName, TRUE ) == 0
                            nOld := j
                        ENDIF
                    NEXT
                ENDIF
                aSource:Add( nOld )
            NEXT

            IF ! DbUseArea( TRUE, cDriver, cNew, "STRUCTNEW", FALSE, FALSE )
                DbSelectArea( nOldArea )
                DbCloseArea()
                cMessage := "The new file could not be opened."
                RETURN FALSE
            ENDIF
            CoreDb.Info( DBI_RDD_OBJECT, REF oResult )
            LOCAL oNew := (IRdd) oResult AS IRdd
            nNewArea := (DWORD) oNew:Area
            // AutoIncrement fields: the RDD assigns the value itself (FieldPut is forbidden).
            // So set the counter to the old value before every append, so the values stay unchanged.
            LOCAL aAuto    := List<INT>{} AS List<INT>
            LOCAL aCounter := List<OBJECT>{} AS List<OBJECT>
            FOR VAR nA := 0 TO aFields:Count - 1
                IF aSource[nA] > 0 .AND. aFields[nA]:Extra:Contains( "+" )
                    aAuto:Add( nA )
                    aCounter:Add( oOld:FieldInfo( aSource[nA], DBS_COUNTER, NULL ) )
                ENDIF
            NEXT

            // Copy the records in natural order, leave out deleted records (like Pack)
            oOld:GoTop()
            DO WHILE ! oOld:EoF
                IF oOld:Deleted
                    nRemoved++
                    oOld:Skip( 1 )
                    LOOP
                ENDIF
                FOREACH nA AS INT IN aAuto
                    oNew:FieldInfo( nA + 1, DBS_COUNTER, oOld:GetValue( aSource[nA] ) )
                NEXT
                DbAppend()
                FOR VAR k := 0 TO aFields:Count - 1
                    IF aSource[k] > 0 .AND. ! aAuto:Contains( k )
                        TRY
                            LOCAL oValue := oOld:GetValue( aSource[k] ) AS OBJECT
                            IF oValue != NULL
                                FieldPut( k + 1, StructureRebuild.ConvertValue( oValue, aFields[k] ) )
                            ENDIF
                        CATCH
                            nError++
                        END TRY
                    ENDIF
                NEXT
                nRecords++
                oOld:Skip( 1 )
            ENDDO
            // Counters of the AutoIncrement fields back to the original state (next free value)
            FOR VAR nZ := 0 TO aAuto:Count - 1
                oNew:FieldInfo( aAuto[nZ] + 1, DBS_COUNTER, aCounter[nZ] )
            NEXT
            DbCommit()
            DbCloseArea()                 // new file
            DbSelectArea( nOldArea )
            DbCloseArea()                 // old file
        CATCH ex AS Exception
            TRY
                IF nNewArea > 0
                    DbSelectArea( nNewArea )
                    DbCloseArea()
                ENDIF
                IF nOldArea > 0
                    DbSelectArea( nOldArea )
                    DbCloseArea()
                ENDIF
            CATCH
                NOP
            END TRY
            StructureRebuild.DeleteFiles( cNew )
            cMessage := "Error copying the data (original unchanged):" + Environment.NewLine + ex:Message
            RETURN FALSE
        END TRY

        // ---- 3. swap the files: original -> backup, new -> original ----
        LOCAL cStamp := DateTime.Now:ToString( "yyyyMMdd_HHmmss" ) AS STRING
        LOCAL cBackup    := Path.Combine( cFolder, cBase + "_OLD_" + cStamp ) AS STRING
        LOCAL nSeq     := 1 AS INT
        // two rebuilds in the same second: never overwrite an existing backup
        DO WHILE File.Exists( cBackup + cExtension ) .OR. File.Exists( cBackup + ".fpt" ) .OR. File.Exists( cBackup + ".dbt" ) .OR. File.Exists( cBackup + ".cdx" )
            nSeq++
            cBackup := Path.Combine( cFolder, cBase + "_OLD_" + cStamp + "_" + Convert.ToString( nSeq ) )
        ENDDO
        TRY
            FOREACH cExt AS STRING IN <STRING>{ cExtension, ".fpt", ".dbt", ".cdx" }
            LOCAL cSource := Path.ChangeExtension( cFile, cExt ) AS STRING
                IF File.Exists( cSource ) .AND. ( cExt != ".cdx" .OR. ! lNtx )
                    File.Move( cSource, cBackup + cExt )
                ENDIF
            NEXT
            FOREACH cExt AS STRING IN <STRING>{ cExtension, ".fpt", ".dbt" }
            LOCAL cSource := Path.ChangeExtension( cNew, cExt ) AS STRING
                IF File.Exists( cSource )
                    File.Move( cSource, Path.ChangeExtension( cFile, cExt ) )
                ENDIF
            NEXT
        CATCH ex AS Exception
            cMessage := "Error renaming the files:" + Environment.NewLine + ex:Message + Environment.NewLine + Environment.NewLine + ;
                        "Please check the folder: backup " + cBackup + ".*  and new file " + cNew
            RETURN FALSE
        END TRY

        // Adapt the field names in the index expressions to renamed fields
        FOREACH aOrd AS STRING[] IN aOrders
            aOrd:SetValue( StructureRebuild.MapExpression( (STRING) aOrd:GetValue( 1 ), aFields ), 1 )
            aOrd:SetValue( StructureRebuild.MapExpression( (STRING) aOrd:GetValue( 2 ), aFields ), 2 )
        NEXT
        aOrdersFrom := aOrders

        // ---- Message ----
        cMessage := "Rebuild finished." + Environment.NewLine + ;
                    Convert.ToString( nRecords ) + " records taken over, " + Convert.ToString( nRemoved ) + " deleted records removed, " + ;
                    Convert.ToString( aOrders:Count ) + " indexes ready to be recreated." + Environment.NewLine + ;
                    "Backup: " + Path.GetFileName( cBackup ) + ".*"
        IF nError > 0
            cMessage += Environment.NewLine + Environment.NewLine + Convert.ToString( nError ) + " field values could not be converted (left empty)."
        ENDIF
        IF aOther:Count > 0
            cMessage += Environment.NewLine + Environment.NewLine + "These index files were NOT rebuilt:" + Environment.NewLine + String.Join( Environment.NewLine, aOther:ToArray() )
        ENDIF
        RETURN TRUE

    /// <summary>Replace renamed fields (AltName != Name) in an index expression.
        /// The expression is read word by word; text between quotes is left unchanged.</summary>
        PUBLIC STATIC METHOD MapExpression( cExpression AS STRING, aFields AS List<FieldDef> ) AS STRING
            IF cExpression == NULL .OR. cExpression:Length == 0
                RETURN ""
            ENDIF
            LOCAL cResult      := System.Text.StringBuilder{} AS System.Text.StringBuilder
            LOCAL cApostrophe := (CHAR) 39 AS CHAR
            LOCAL cQuote   := (CHAR) 34 AS CHAR
            LOCAL nPos := 0 AS INT
            DO WHILE nPos < cExpression:Length
                LOCAL c := cExpression[nPos] AS CHAR
                IF c == cApostrophe .OR. c == cQuote
                    LOCAL nEnd := cExpression:IndexOf( c, nPos + 1 ) AS INT
                    IF nEnd < 0
                        nEnd := cExpression:Length - 1
                    ENDIF
                    cResult:Append( cExpression:Substring( nPos, nEnd - nPos + 1 ) )
                    nPos := nEnd + 1
                ELSEIF Char.IsLetterOrDigit( c ) .OR. c == '_'
                    LOCAL nWordEnd := nPos AS INT
                    DO WHILE nWordEnd < cExpression:Length .AND. ( Char.IsLetterOrDigit( cExpression[nWordEnd] ) .OR. cExpression[nWordEnd] == '_' )
                        nWordEnd++
                    ENDDO
                    LOCAL cWord := cExpression:Substring( nPos, nWordEnd - nPos ) AS STRING
                    FOREACH f AS FieldDef IN aFields
                        IF f:OldName:Length > 0 .AND. String.Compare( f:OldName, f:Name, TRUE ) != 0 .AND. String.Compare( cWord, f:OldName, TRUE ) == 0
                            cWord := f:Name
                            EXIT
                        ENDIF
                    NEXT
                    cResult:Append( cWord )
                    nPos := nWordEnd
                ELSE
                    cResult:Append( c )
                    nPos++
                ENDIF
            ENDDO
            RETURN cResult:ToString()

        // Adapt the value to the new field type
    PRIVATE STATIC METHOD ConvertValue( oValue AS OBJECT, f AS FieldDef ) AS OBJECT
        LOCAL cText AS STRING
        // Text representation for a type change
        IF oValue IS IDate
            LOCAL oDate := (IDate) oValue AS IDate
            IF f:FieldType == "D"
                RETURN oValue
            ENDIF
            cText := IIF( oDate:IsEmpty, "", String.Format( "{0:00}.{1:00}.{2:0000}", oDate:Day, oDate:Month, oDate:Year ) )
        ELSEIF oValue IS DateTime
            IF f:FieldType == "T" .OR. f:FieldType == "D"
                RETURN oValue                       // DateTime field (T) or date
            ENDIF
            cText := ((DateTime) oValue):ToString( "dd.MM.yyyy HH:mm:ss", CultureInfo.InvariantCulture )
        ELSEIF oValue IS BYTE[]
            RETURN oValue                           // Take binary data over unchanged
        ELSEIF oValue IS LOGIC
            IF f:FieldType == "L"
                RETURN oValue
            ENDIF
            cText := IIF( (LOGIC) oValue, "T", "F" )
        ELSEIF oValue IS STRING
            cText := ((STRING) oValue):TrimEnd()
            IF f:FieldType == "C" .OR. f:FieldType == "M"
                RETURN oValue                       // same type: unchanged (memo padding is kept)
            ENDIF
        ELSE
            IF f:FieldType == "N" .OR. f:FieldType == "F" .OR. f:FieldType == "I" .OR. f:FieldType == "Y" .OR. f:FieldType == "B"
                RETURN oValue
            ENDIF
            cText := Convert.ToString( oValue, CultureInfo.InvariantCulture )
        ENDIF
        SWITCH f:FieldType
        CASE "C"
            RETURN cText
        CASE "M"
            RETURN cText
        CASE "L"
            LOCAL cUpper := cText:Trim():ToUpper():Replace( ".", "" ) AS STRING
            RETURN cUpper == "T" .OR. cUpper == "Y" .OR. cUpper == "J" .OR. cUpper == "1" .OR. cUpper == "TRUE"
        CASE "T"
            IF cText:Trim():Length == 0
                RETURN DateTime.MinValue
            ENDIF
            RETURN DateTime.ParseExact( cText:Trim(), <STRING>{ "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy", "d.M.yyyy", "yyyyMMdd" }, CultureInfo.InvariantCulture, DateTimeStyles.None )
        CASE "D"
            IF cText:Trim():Length == 0
                RETURN DateTime.MinValue
            ENDIF
            RETURN DateTime.ParseExact( cText:Trim(), <STRING>{ "dd.MM.yyyy", "d.M.yyyy", "dd.MM.yy", "yyyyMMdd" }, CultureInfo.InvariantCulture, DateTimeStyles.None )
        OTHERWISE
            IF cText:Trim():Length == 0
                RETURN 0.0
            ENDIF
            RETURN Double.Parse( cText:Trim():Replace( "'", "" ):Replace( ",", "." ), CultureInfo.InvariantCulture )
        END SWITCH

    /// <summary>Pack as in xBase: rebuild DBF and FPT without deleted records, then recreate all indexes.
    /// The file must not be open while doing this.</summary>
    PUBLIC STATIC METHOD Pack( cFile AS STRING, cDriver AS STRING, cMessage REF STRING ) AS LOGIC
        LOCAL oResult := NULL AS OBJECT
        LOCAL aFields := List<FieldDef>{} AS List<FieldDef>
        // Take over the structure unchanged
        TRY
            IF ! DbUseArea( TRUE, cDriver, cFile, "PACKREAD", FALSE, TRUE )
                cMessage := "The file could not be opened exclusively."
                RETURN FALSE
            ENDIF
            CoreDb.Info( DBI_RDD_OBJECT, REF oResult )
            LOCAL oRdd := (IRdd) oResult AS IRdd
            FOR VAR i := 1 TO oRdd:FieldCount
                aFields:Add( FieldDef.FromRdd( oRdd, i ) )
            NEXT
            DbCloseArea()
        CATCH ex AS Exception
            cMessage := "The structure could not be read: " + ex:Message
            RETURN FALSE
        END TRY

        LOCAL aOrders := List<STRING[]>{} AS List<STRING[]>
        LOCAL cRebuild  := "" AS STRING
        IF ! StructureRebuild.Execute( cFile, cDriver, aFields, REF cRebuild, REF aOrders )
            cMessage := cRebuild
            RETURN FALSE
        ENDIF

        // recreate all indexes of the production CDX
        LOCAL aError := List<STRING>{} AS List<STRING>
        IF aOrders:Count > 0
            TRY
                IF DbUseArea( TRUE, cDriver, cFile, "PACKINDEX", FALSE, FALSE )
                    LOCAL cCdx := Path.ChangeExtension( cFile, ".cdx" ) AS STRING
                    FOREACH aOrd AS STRING[] IN aOrders
                        LOCAL cF := StructureRebuild.CreateOrder( cCdx, (STRING) aOrd:GetValue( 0 ), (STRING) aOrd:GetValue( 1 ), ;
                            (STRING) aOrd:GetValue( 2 ), (STRING) aOrd:GetValue( 3 ) == "1" ) AS STRING
                        IF cF:Length > 0
                            aError:Add( (STRING) aOrd:GetValue( 0 ) + ": " + cF )
                        ENDIF
                    NEXT
                    DbCloseArea()
                ELSE
                    aError:Add( "The file cannot be opened for the index rebuild" )
                ENDIF
            CATCH ex AS Exception
                aError:Add( ex:Message )
            END TRY
        ENDIF
        cMessage := cRebuild:Replace( "Rebuild finished.", "Pack finished (DBF and FPT rebuilt)." ) ;
                          :Replace( " indexes ready to be recreated.", " indexes recreated." )
        IF aError:Count > 0
            cMessage += Environment.NewLine + Environment.NewLine + "Index errors:" + Environment.NewLine + String.Join( Environment.NewLine, aError:ToArray() )
        ENDIF
        RETURN TRUE

    /// <summary>Read the orders of the production CDX of a file: name, expression, condition, unique ("1"/"0")</summary>
    PUBLIC STATIC METHOD ReadOrders( cDbf AS STRING, cDriver AS STRING ) AS List<STRING[]>
        LOCAL aList := List<STRING[]>{} AS List<STRING[]>
        LOCAL cBase := Path.GetFileNameWithoutExtension( cDbf ) AS STRING
        TRY
            IF DbUseArea( TRUE, cDriver, cDbf, "ORDERSREAD", TRUE, TRUE )
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
                    LOCAL cKey := "", cFor := "", cBag := "", cUni := "0" AS STRING
                    // read each item separately so that an error does not discard the whole order
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
                    TRY
                        cUni := IIF( (LOGIC) DbOrderInfo( DBOI_UNIQUE, "", i ), "1", "0" )
                    CATCH
                        NOP
                    END TRY
                    IF cBag:Length == 0 .OR. String.Compare( Path.GetFileNameWithoutExtension( cBag ), cBase, TRUE ) == 0
                        aList:Add( <STRING>{ cName, cKey, cFor, cUni } )
                    ENDIF
                NEXT
                DbCloseArea()
            ENDIF
        CATCH ex AS Exception
            MessageBox.Show( "The indexes could not be read:" + Environment.NewLine + ex:Message, "Indexes" )
        END TRY
        RETURN aList

    /// <summary>Create an order additively in the CURRENT workarea (existing orders are kept).
    /// Returns "" on success, otherwise the error message.</summary>
    PUBLIC STATIC METHOD CreateOrder( cBag AS STRING, cName AS STRING, cKey AS STRING, cFor AS STRING, lUnique AS LOGIC ) AS STRING
        TRY
            LOCAL oCond := DbOrderCondInfo{} AS DbOrderCondInfo
            oCond:Additive := TRUE
            oCond:Active   := TRUE
            IF cFor:Trim():Length > 0
                oCond:ForExpression := cFor:Trim()
                oCond:ForBlock      := (ICodeblock) MCompile( cFor:Trim() )
            ENDIF
            IF ! CoreDb.OrdCreate( cBag, cName, cKey, (ICodeblock) MCompile( cKey ), lUnique, oCond )
                RETURN "OrdCreate returned FALSE"
            ENDIF
        CATCH ex AS Exception
            RETURN ex:Message
        END TRY
        RETURN ""

    PRIVATE STATIC METHOD DeleteFiles( cDbf AS STRING ) AS VOID
        FOREACH cExt AS STRING IN <STRING>{ Path.GetExtension( cDbf ), ".fpt", ".dbt", ".cdx" }
        TRY
        IF File.Exists( Path.ChangeExtension( cDbf, cExt ) )
                    File.Delete( Path.ChangeExtension( cDbf, cExt ) )
                ENDIF
            CATCH
                NOP
            END TRY
        NEXT
        RETURN
END CLASS


/// <summary>Show and recreate indexes (after a structure rebuild or from another file)</summary>
PUBLIC CLASS NewIndexDialog INHERIT System.Windows.Forms.Form
    PRIVATE cFile   AS STRING
    PRIVATE cDriver  AS STRING
    PRIVATE oWindow AS DataWindow
    PRIVATE lv       AS ListView

    PUBLIC CONSTRUCTOR( cFile AS STRING, cRdd AS STRING, aOrders AS List<STRING[]>, oF AS DataWindow )
        SELF:cFile   := cFile
        SELF:cDriver  := cRdd
        SELF:oWindow := oF
        SELF:Text          := "Create indexes - " + Path.GetFileName( cFile )
        SELF:Size          := Size{ 780, 400 }
        SELF:StartPosition := FormStartPosition.CenterParent
        SELF:ShowInTaskbar := FALSE
        SELF:MinimizeBox   := FALSE
        SELF:Font          := Font{ "Microsoft Sans Serif", 8.25 }

        SELF:lv := ListView{}
        SELF:lv:View          := View.Details
        SELF:lv:CheckBoxes    := TRUE
        SELF:lv:FullRowSelect := TRUE
        SELF:lv:GridLines     := TRUE
        SELF:lv:MultiSelect   := FALSE
        SELF:lv:HideSelection := FALSE
        SELF:lv:Dock          := DockStyle.Fill
        SELF:lv:Columns:Add( "Order", 120 )
        SELF:lv:Columns:Add( "Expression", 300 )
        SELF:lv:Columns:Add( "Condition", 140 )
        SELF:lv:Columns:Add( "Unique", 50 )
        SELF:lv:Columns:Add( "Status", 120 )
        SELF:lv:DoubleClick += EventHandler{ SELF, @Edit_Click() }
        FOREACH aOrd AS STRING[] IN aOrders
            LOCAL oItem := ListViewItem{ (STRING) aOrd:GetValue( 0 ) } AS ListViewItem
            oItem:SubItems:Add( (STRING) aOrd:GetValue( 1 ) )
            oItem:SubItems:Add( (STRING) aOrd:GetValue( 2 ) )
            oItem:SubItems:Add( IIF( (STRING) aOrd:GetValue( 3 ) == "1", "yes", "" ) )
            oItem:SubItems:Add( "" )
            oItem:Checked := TRUE
            SELF:lv:Items:Add( oItem )
        NEXT

        LOCAL pnl := FlowLayoutPanel{} AS FlowLayoutPanel
        pnl:Dock          := DockStyle.Right
        pnl:Width         := 125
        pnl:FlowDirection := FlowDirection.TopDown
        pnl:Padding       := Padding{ 6 }
        pnl:Controls:Add( SELF:MakeButton( "Create",    EventHandler{ SELF, @Create_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Edit...", EventHandler{ SELF, @Edit_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Close",   EventHandler{ SELF, @Close_Click() } ) )

        SELF:Controls:Add( SELF:lv )
        SELF:Controls:Add( pnl )
        RETURN

    PRIVATE METHOD MakeButton( cText AS STRING, oHandler AS EventHandler ) AS Button
        LOCAL b := Button{} AS Button
        b:Text   := cText
        b:Width  := 108
        b:Height := 26
        b:Click += oHandler
        RETURN b

    PRIVATE METHOD Edit_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:lv:SelectedItems:Count == 0
            RETURN
        ENDIF
        LOCAL oItem := SELF:lv:SelectedItems[0] AS ListViewItem
        LOCAL dlg := InputDialog{ "Edit order", "", <STRING>{ "Name", "Expression", "Condition" }, ;
            <STRING>{ oItem:Text, oItem:SubItems[1]:Text, oItem:SubItems[2]:Text }, "Unique", oItem:SubItems[3]:Text == "yes" } AS InputDialog
        IF dlg:ShowDialog( SELF ) == DialogResult.OK
            oItem:Text := dlg:InputValue( 0 )
            oItem:SubItems[1]:Text := dlg:InputValue( 1 )
            oItem:SubItems[2]:Text := dlg:InputValue( 2 )
            oItem:SubItems[3]:Text := IIF( dlg:MakeCheckBox, "yes", "" )
        ENDIF
        RETURN

    PRIVATE METHOD Create_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL cCdx    := Path.ChangeExtension( SELF:cFile, ".cdx" ) AS STRING
        LOCAL nSucceeded     := 0 AS INT
        LOCAL nError := 0 AS INT
        LOCAL lSelf := SELF:oWindow == NULL AS LOGIC
        SELF:Cursor := Cursors.WaitCursor
        TRY
            IF lSelf
                IF ! DbUseArea( TRUE, SELF:cDriver, SELF:cFile, "INDEXNEW", FALSE, FALSE )
                    MessageBox.Show( "The file could not be opened exclusively.", SELF:Text )
                    RETURN
                ENDIF
            ELSE
                SELF:oWindow:SelectArea()
            ENDIF
            FOREACH oItem AS ListViewItem IN SELF:lv:Items
                IF oItem:Checked .AND. oItem:SubItems[4]:Text != "OK"
                    LOCAL cError := StructureRebuild.CreateOrder( cCdx, oItem:Text, oItem:SubItems[1]:Text, oItem:SubItems[2]:Text, oItem:SubItems[3]:Text == "yes" ) AS STRING
                    IF cError:Length == 0
                        oItem:SubItems[4]:Text := "OK"
                        nSucceeded++
                    ELSE
                        oItem:SubItems[4]:Text := "Error: " + cError
                        nError++
                    ENDIF
                ENDIF
            NEXT
            IF lSelf
                DbCloseArea()
            ENDIF
        FINALLY
            SELF:Cursor := Cursors.Default
        END TRY
        IF SELF:oWindow != NULL
            SELF:oWindow:AfterIndexChange()
        ENDIF
        MessageBox.Show( Convert.ToString( nSucceeded ) + " indexes created" + IIF( nError > 0, ", " + Convert.ToString( nError ) + " with errors (see column Status)", "" ) + ".", SELF:Text )
        RETURN

    PRIVATE METHOD Close_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:Close()
        RETURN
END CLASS

END NAMESPACE
