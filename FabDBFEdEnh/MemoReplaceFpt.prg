USING System
USING System.IO
USING System.Text
USING System.Drawing
USING System.Collections.Generic
USING System.Windows.Forms

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>
/// FPT analysis (FlexFile/FoxPro memo) like the PowerShell script FptAnalyse.ps1, read only.
/// Note: in this project arrays are 1-based (ZeroArrays off) -> buf[1] is the first byte.
/// Methods like BitConverter.ToUInt16( buf, n ), however, expect 0-based offsets.
/// </summary>
PUBLIC STATIC CLASS FptAnalysis

    PUBLIC STATIC METHOD Report( cDbf AS STRING ) AS STRING
        LOCAL o    := StringBuilder{} AS StringBuilder
        LOCAL cFpt := Path.ChangeExtension( cDbf, ".fpt" ) AS STRING
        IF ! File.Exists( cFpt )
            RETURN "No FPT file found: " + cFpt
        ENDIF
        LOCAL df := FileStream{ cDbf, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
        LOCAL ff := FileStream{ cFpt, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
        TRY
            // ---- DBF header ----
            LOCAL h := BYTE[]{ 32 } AS BYTE[]
            df:Read( h, 0, 32 )
            LOCAL nRec := BitConverter.ToInt32( h, 4 ) AS INT
            LOCAL nHeaderLen  := BitConverter.ToUInt16( h, 8 ) AS INT
            LOCAL nRecLen  := BitConverter.ToUInt16( h, 10 ) AS INT

            // ---- Fields (only remember the memos) ----
            LOCAL aName := List<STRING>{} AS List<STRING>
            LOCAL aOffset  := List<INT>{} AS List<INT>      // 0-based offset in the record (byte 0 = deleted flag)
            LOCAL aLen  := List<INT>{} AS List<INT>
            LOCAL nOffset  := 1 AS INT
            LOCAL fieldDesc    := BYTE[]{ 32 } AS BYTE[]
            DO WHILE TRUE
                IF df:Read( fieldDesc, 0, 1 ) < 1 .OR. fieldDesc[1] == 0x0D
                    EXIT
                ENDIF
                IF df:Read( fieldDesc, 1, 31 ) < 31
                    EXIT
                ENDIF
                LOCAL nType := fieldDesc[12] AS BYTE
                LOCAL nLen := fieldDesc[17] AS INT
                IF nType == 67                                   // 'C': length > 255 in the decimal byte
                    nLen += fieldDesc[18] * 256
                ENDIF
                IF nType == 77                                   // 'M'
                    aName:Add( Encoding.ASCII.GetString( fieldDesc, 0, 11 ):Replace( e"\0", "" ):Trim() )
                    aOffset:Add( nOffset )
                    aLen:Add( nLen )
                ENDIF
                nOffset += nLen
            ENDDO

            // ---- FPT header ----
            LOCAL fptHeader := BYTE[]{ 8 } AS BYTE[]
            ff:Read( fptHeader, 0, 8 )
            LOCAL nNext := BE( fptHeader, 0 ) AS INT64
            LOCAL nBlockSize   := BE( fptHeader, 4 ) AS INT64
            IF nBlockSize <= 0
                nBlockSize := 64
            ENDIF
            LOCAL nFileSize := ff:Length AS INT64

            o:AppendLine( "File       : " + cDbf )
            o:AppendLine( "Records    : " + N( nRec ) + ", record length " + N( nRecLen ) + IIF( nOffset != nRecLen, "  (WARNING: field lengths " + N( nOffset ) + " <> record length)", "" ) )
            o:AppendLine( "FPT        : " + N( nFileSize ) + " Bytes (" + MB( nFileSize ) + "), block size " + N( nBlockSize ) )
            o:AppendLine( "NextFree   : " + N( nNext * nBlockSize ) + IIF( nNext * nBlockSize == nFileSize, " (= end of file, ok)", " (not equal to end of file!)" ) )
            o:AppendLine( "Memo fields: " + String.Join( " ", aName:ToArray() ) )
            o:AppendLine( "" )

            // ---- Go through the records ----
            LOCAL aStats   := List<List<INT64[]>>{} AS List<List<INT64[]>>      // per field: {length, content, record, lines}
            LOCAL aEmpty   := List<INT>{} AS List<INT>
            FOR VAR i := 0 TO aName:Count - 1
                aStats:Add( List<INT64[]>{} )
                aEmpty:Add( 0 )
            NEXT
            LOCAL oUsed := Dictionary<INT64, INT64[]>{} AS Dictionary<INT64, INT64[]>   // Pos -> {Alloc, record, field}
            LOCAL oTypes  := Dictionary<INT64, INT>{} AS Dictionary<INT64, INT>
            LOCAL aError := List<STRING>{} AS List<STRING>
            LOCAL nDeleted := 0 AS INT
            LOCAL rec := BYTE[]{ nRecLen } AS BYTE[]
            LOCAL buf := BYTE[]{ 1048576 } AS BYTE[]

            FOR VAR r := 0 TO nRec - 1
                df:Seek( (INT64) nHeaderLen + (INT64) r * nRecLen, SeekOrigin.Begin )
                IF df:Read( rec, 0, nRecLen ) < nRecLen
                    aError:Add( "DBF ends before record " + N( r + 1 ) )
                    EXIT
                ENDIF
                IF rec[1] == 42                                  // '*'
                    nDeleted++
                ENDIF
                FOR VAR m := 0 TO aName:Count - 1
                    LOCAL nBlock := 0 AS INT64
                    IF aLen[m] == 10
                        LOCAL cLine := Encoding.ASCII.GetString( rec, aOffset[m], 10 ):Replace( e"\0", "" ):Trim() AS STRING
                        IF cLine:Length == 0
                            aEmpty[m] := aEmpty[m] + 1
                            LOOP
                        ENDIF
                        IF ! Int64.TryParse( cLine, OUT nBlock )
                            aError:Add( "Record " + N( r + 1 ) + " " + aName[m] + ": pointer unreadable '" + cLine + "'" )
                            LOOP
                        ENDIF
                    ELSE
                        nBlock := BitConverter.ToUInt32( rec, aOffset[m] )
                    ENDIF
                    IF nBlock == 0
                        aEmpty[m] := aEmpty[m] + 1
                        LOOP
                    ENDIF
                    LOCAL nPos := nBlock * nBlockSize AS INT64
                    IF nPos < 512 .OR. nPos + 8 > nFileSize
                        aError:Add( "Record " + N( r + 1 ) + " " + aName[m] + ": block " + N( nBlock ) + " outside of the file" )
                        LOOP
                    ENDIF
                    ff:Seek( nPos, SeekOrigin.Begin )
                    ff:Read( fptHeader, 0, 8 )
                    LOCAL nBlockType := BE( fptHeader, 0 ) AS INT64
                    LOCAL nBlockLen := BE( fptHeader, 4 ) AS INT64
                    LOCAL nOld := 0 AS INT
                    oTypes:TryGetValue( nBlockType, OUT nOld )
                    oTypes[nBlockType] := nOld + 1
                    IF ( nBlockType != 1 .AND. nBlockType != 1019 ) .OR. nPos + 8 + nBlockLen > nFileSize
                        aError:Add( "Record " + N( r + 1 ) + " " + aName[m] + ": block " + N( nBlock ) + " has type " + N( nBlockType ) + ", length " + N( nBlockLen ) + ;
                            IIF( nBlockType == 1001, " (released -> content lost)", "" ) )
                        LOOP
                    ENDIF
                    LOCAL nAllocated := ( 8 + nBlockLen + nBlockSize - 1 ) / nBlockSize * nBlockSize AS INT64
                    IF oUsed:ContainsKey( nPos )
                        aError:Add( "Record " + N( r + 1 ) + " " + aName[m] + ": block " + N( nBlock ) + " duplicate, also record " + N( oUsed[nPos][2] ) )
                        LOOP
                    ENDIF
                    oUsed[nPos] := <INT64>{ nAllocated, r + 1, m }

                    // Read content: lines, length without trailing spaces/nulls/CR/LF
                    LOCAL nRest := nBlockLen, nContent := 0, nRead := 0 AS INT64
                    LOCAL nRows := IIF( nBlockLen > 0, 1, 0 ) AS INT64
                    DO WHILE nRest > 0
                        LOCAL n := ff:Read( buf, 0, (INT) Math.Min( (INT64) buf:Length, nRest ) ) AS INT
                        IF n <= 0
                            EXIT
                        ENDIF
                        FOR VAR i := 1 TO n
                            LOCAL x := buf[i] AS BYTE
                            IF x == 10
                                nRows++
                            ENDIF
                            IF x != 32 .AND. x != 0 .AND. x != 13 .AND. x != 10
                                nContent := nRead + i
                            ENDIF
                        NEXT
                        nRead += n
                        nRest -= n
                    ENDDO
                    aStats[m]:Add( <INT64>{ nBlockLen, nContent, r + 1, nRows } )
                NEXT
            NEXT

            // ---- Overlaps and dead space ----
            LOCAL aPos := List<INT64>{ oUsed:Keys } AS List<INT64>
            aPos:Sort()
            LOCAL nLiveBytes := 0 AS INT64
            FOR VAR i := 0 TO aPos:Count - 1
                LOCAL aBlock := oUsed[aPos[i]] AS INT64[]
                nLiveBytes += aBlock[1]
                IF i > 0
                    LOCAL aPrev := oUsed[aPos[i - 1]] AS INT64[]
                    IF aPos[i - 1] + aPrev[1] > aPos[i]
                        aError:Add( "Record " + N( aBlock[2] ) + " overlaps record " + N( aPrev[2] ) )
                    ENDIF
                ENDIF
            NEXT
            LOCAL nTotal := nFileSize - 512 - nLiveBytes AS INT64

            o:AppendLine( "Deleted records: " + N( nDeleted ) )
            o:Append( "Block types of the pointers: " )
            FOREACH oPair AS KeyValuePair<INT64, INT> IN oTypes
                o:Append( N( oPair:Key ) + "=" + N( oPair:Value ) + "  " )
            NEXT
            o:AppendLine( "(1=text VO, 1019=StringLong X#, 1001=released)" )
            o:AppendLine( "Used       : " + N( nLiveBytes ) + " Bytes (" + MB( nLiveBytes ) + ")" )
            LOCAL nPercent := nTotal * 100.0 / Math.Max( nFileSize, (INT64) 1 ) AS REAL8
            o:AppendLine( "Dead space : " + N( nTotal ) + " Bytes (" + MB( nTotal ) + ", " + nPercent:ToString( "0.0" ) + " %)" )
            o:AppendLine( "" )

            FOR VAR m := 0 TO aName:Count - 1
                LOCAL aSt := aStats[m] AS List<INT64[]>
                o:AppendLine( "== " + aName[m] + ": " + N( aSt:Count ) + " memos, " + N( aEmpty[m] ) + " empty" )
                IF aSt:Count == 0
                    o:AppendLine( "" )
                    LOOP
                ENDIF
                LOCAL aPosList := List<INT64>{} AS List<INT64>
                LOCAL aI := List<INT64>{} AS List<INT64>
                LOCAL oMaxL := aSt[0] AS INT64[]
                LOCAL oMaxI := aSt[0] AS INT64[]
                LOCAL nSumLen := 0, nSumIn := 0 AS INT64
                LOCAL oFrequent := Dictionary<INT64, INT>{} AS Dictionary<INT64, INT>
                FOREACH aEntry AS INT64[] IN aSt
                    IF aEntry[1] > oMaxL[1]
                        oMaxL := aEntry
                    ENDIF
                    IF aEntry[2] > oMaxI[2]
                        oMaxI := aEntry
                    ENDIF
                    nSumLen += aEntry[1]
                    nSumIn += aEntry[2]
                    aPosList:Add( aEntry[1] )
                    aI:Add( aEntry[2] )
                    LOCAL nHigh := 0 AS INT
                    oFrequent:TryGetValue( aEntry[1], OUT nHigh )
                    oFrequent[aEntry[1]] := nHigh + 1
                NEXT
                aPosList:Sort()
                aI:Sort()
                o:AppendLine( "  Block length (incl. padding): max " + N( oMaxL[1] ) + " (record " + N( oMaxL[3] ) + ", " + MB( oMaxL[1] ) + "), 99% " + N( Q( aPosList, 0.99 ) ) + ;
                              ", 95% " + N( Q( aPosList, 0.95 ) ) + ", Median " + N( Q( aPosList, 0.5 ) ) + ", average " + N( nSumLen / aSt:Count ) )
                o:AppendLine( "  Actual content (without padding): max " + N( oMaxI[2] ) + " (record " + N( oMaxI[3] ) + ", " + MB( oMaxI[2] ) + ", " + N( oMaxI[4] ) + " lines), 99% " + ;
                              N( Q( aI, 0.99 ) ) + ", 95% " + N( Q( aI, 0.95 ) ) + ", 90% " + N( Q( aI, 0.90 ) ) + ", Median " + N( Q( aI, 0.5 ) ) + ", average " + N( nSumIn / aSt:Count ) )
                o:Append( "  Content larger than:" )
                FOREACH nCenturyOff AS INT64 IN <INT64>{ 1000, 5000, 10000, 50000, 100000, 150000 }
                    LOCAL nCnt := 0 AS INT
                    FOREACH nX AS INT64 IN aI
                        IF nX > nCenturyOff
                            nCnt++
                        ENDIF
                    NEXT
                    o:Append( "  " + N( nCenturyOff ) + ": " + N( nCnt ) )
                NEXT
                o:AppendLine( "" )
                LOCAL aTop := List<KeyValuePair<INT64, INT>>{ oFrequent } AS List<KeyValuePair<INT64, INT>>
                aTop:Sort( { a, b => b:Value:CompareTo( a:Value ) } )
                o:Append( "  Most frequent block lengths:" )
                FOR VAR i := 0 TO Math.Min( 5, aTop:Count ) - 1
                    o:Append( "  " + N( aTop[i]:Key ) + " x" + N( aTop[i]:Value ) )
                NEXT
                o:AppendLine( "" )
                o:AppendLine( "" )
            NEXT

            o:AppendLine( "Broken pointers / errors: " + N( aError:Count ) )
            FOREACH cF AS STRING IN aError
                o:AppendLine( "  " + cF )
            NEXT
        CATCH ex AS Exception
            o:AppendLine( "" )
            o:AppendLine( "ERROR: " + ex:Message )
        FINALLY
            df:Close()
            ff:Close()
        END TRY
        RETURN o:ToString()

    // Big-endian 32 bit from a 0-based offset (the array itself is 1-based!)
    PRIVATE STATIC METHOD BE( a AS BYTE[], nOffset0 AS INT ) AS INT64
        RETURN (INT64) a[nOffset0 + 1] * 16777216 + (INT64) a[nOffset0 + 2] * 65536 + (INT64) a[nOffset0 + 3] * 256 + (INT64) a[nOffset0 + 4]

    PRIVATE STATIC METHOD N( n AS INT64 ) AS STRING
        RETURN n:ToString( "#,0" ):Replace( ",", "'" ):Replace( ".", "'" )

    PRIVATE STATIC METHOD MB( n AS INT64 ) AS STRING
        LOCAL nMegaBytes := n / 1048576.0 AS REAL8
        RETURN nMegaBytes:ToString( "0.000" ) + " MB"

    // Quantile of a sorted list
    PRIVATE STATIC METHOD Q( a AS List<INT64>, p AS REAL8 ) AS INT64
        LOCAL i := (INT) ( p * a:Count ) AS INT
        IF i >= a:Count
            i := a:Count - 1
        ENDIF
        RETURN a[i]
END CLASS


/// <summary>Window for a text report with "Save as"</summary>
PUBLIC CLASS TextWindow INHERIT System.Windows.Forms.Form
    PRIVATE txt AS TextBox
    PUBLIC CONSTRUCTOR( cTitle AS STRING, cText AS STRING )
        SELF:Text          := cTitle
        SELF:Size          := Size{ 900, 600 }
        SELF:StartPosition := FormStartPosition.CenterParent
        SELF:ShowInTaskbar := FALSE
        SELF:txt := TextBox{}
        SELF:txt:Multiline  := TRUE
        SELF:txt:ReadOnly   := TRUE
        SELF:txt:WordWrap   := FALSE
        SELF:txt:ScrollBars := ScrollBars.Both
        SELF:txt:Font       := Font{ "Consolas", 9.75 }
        SELF:txt:Dock       := DockStyle.Fill
        SELF:txt:Text       := cText:Replace( e"\r\n", e"\n" ):Replace( e"\n", e"\r\n" )
        LOCAL pnl := FlowLayoutPanel{} AS FlowLayoutPanel
        pnl:Dock          := DockStyle.Bottom
        pnl:Height        := 36
        pnl:FlowDirection := FlowDirection.RightToLeft
        LOCAL bClose := Button{} AS Button
        bClose:Text := "Close"
        bClose:Width := 100
        bClose:Click += EventHandler{ SELF, @Close_Click() }
        LOCAL bSave := Button{} AS Button
        bSave:Text := "Save..."
        bSave:Width := 100
        bSave:Click += EventHandler{ SELF, @Save_Click() }
        pnl:Controls:Add( bClose )
        pnl:Controls:Add( bSave )
        SELF:Controls:Add( SELF:txt )
        SELF:Controls:Add( pnl )
        RETURN
    PRIVATE METHOD Close_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:Close()
        RETURN
    PRIVATE METHOD Save_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL sfd := SaveFileDialog{} AS SaveFileDialog
        sfd:Filter := "Text (*.txt)|*.txt|All files (*.*)|*.*"
        sfd:DefaultExt := "txt"
        IF sfd:ShowDialog( SELF ) == DialogResult.OK
            File.WriteAllText( sfd:FileName, SELF:txt:Text, Encoding.UTF8 )
        ENDIF
        RETURN
END CLASS


/// <summary>Edit a memo; shows the content without padding, the padding is kept when saving</summary>
PUBLIC CLASS MemoDialog INHERIT System.Windows.Forms.Form
    // ICSharpCode.TextEditor (the editor of the original FabDBFEd memo window)
    PRIVATE txt AS ICSharpCode.TextEditor.TextEditorControl
    PRIVATE lChanged := FALSE AS LOGIC
    PUBLIC PROPERTY Content AS STRING GET SELF:txt:Text
    PUBLIC PROPERTY Modified AS LOGIC GET SELF:lChanged

    PUBLIC CONSTRUCTOR( cTitle AS STRING, cContent AS STRING, nBlock AS INT, lReadOnly AS LOGIC )
        SELF:Text          := cTitle
        SELF:Size          := Size{ 800, 560 }
        SELF:StartPosition := FormStartPosition.CenterParent
        SELF:ShowInTaskbar := FALSE
        SELF:txt := ICSharpCode.TextEditor.TextEditorControl{}
        SELF:txt:Font          := Font{ "Consolas", 9.75 }
        SELF:txt:Dock          := DockStyle.Fill
        SELF:txt:IsReadOnly    := lReadOnly
        SELF:txt:ShowInvalidLines := FALSE
        SELF:txt:Text          := cContent
        // changes are tracked from now on (setting the initial text must not count)
        SELF:lChanged := FALSE
        SELF:txt:TextChanged += EventHandler{ SELF, @Editor_TextChanged() }
        SELF:Shown += EventHandler{ SELF, @Dialog_Shown() }

        LOCAL pnl := Panel{} AS Panel
        pnl:Dock   := DockStyle.Bottom
        pnl:Height := 36
        LOCAL lbl := Label{} AS Label
        lbl:Location := Point{ 8, 11 }
        lbl:AutoSize := TRUE
        lbl:ForeColor := Color.DimGray
        lbl:Text := "Content: " + Convert.ToString( cContent:Length ) + " characters" + ;
                    IIF( nBlock > cContent:Length, "   (saved: " + Convert.ToString( nBlock ) + " characters incl. trailing spaces - removed when saving)", "" )
        LOCAL bOK := Button{} AS Button
        bOK:Text := IIF( lReadOnly, "Close", "Save" )
        bOK:Width := 100
        bOK:Anchor := (AnchorStyles) ( (INT) AnchorStyles.Right + (INT) AnchorStyles.Top )
        bOK:Location := Point{ SELF:ClientSize:Width - 215, 6 }
        bOK:DialogResult := IIF( lReadOnly, System.Windows.Forms.DialogResult.Cancel, System.Windows.Forms.DialogResult.OK )
        LOCAL bCancel := Button{} AS Button
        bCancel:Text := "Cancel"
        bCancel:Width := 100
        bCancel:Anchor := (AnchorStyles) ( (INT) AnchorStyles.Right + (INT) AnchorStyles.Top )
        bCancel:Location := Point{ SELF:ClientSize:Width - 110, 6 }
        bCancel:DialogResult := System.Windows.Forms.DialogResult.Cancel
        bCancel:Visible := ! lReadOnly
        pnl:Controls:Add( lbl )
        pnl:Controls:Add( bOK )
        pnl:Controls:Add( bCancel )
        SELF:CancelButton := bCancel
        SELF:Controls:Add( SELF:txt )
        SELF:Controls:Add( pnl )
        // as in the original memo window: the text area fills the editor control
        SELF:txt:ActiveTextAreaControl:Dock := DockStyle.Fill
        RETURN

    PRIVATE METHOD Editor_TextChanged( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:lChanged := TRUE
        RETURN

    // nothing typed yet when the window appears: forget changes made while it was being built
    PRIVATE METHOD Dialog_Shown( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:lChanged := FALSE
        RETURN
END CLASS


/// <summary>DBReplace: replace a field in several records</summary>
PUBLIC CLASS ReplaceDialog INHERIT System.Windows.Forms.Form
    PRIVATE cmbField   AS ComboBox
    PRIVATE txtValue   AS TextBox
    PRIVATE chkExpr  AS CheckBox
    PRIVATE rbAll    AS RadioButton
    PRIVATE rbCurrent AS RadioButton
    PRIVATE txtFor    AS TextBox

    PUBLIC PROPERTY FieldName        AS STRING GET (STRING) SELF:cmbField:SelectedItem
    PUBLIC PROPERTY InputValue        AS STRING GET SELF:txtValue:Text
    PUBLIC PROPERTY IsExpression AS LOGIC  GET SELF:chkExpr:Checked
    PUBLIC PROPERTY OnlyCurrent  AS LOGIC  GET SELF:rbCurrent:Checked
    PUBLIC PROPERTY Condition   AS STRING GET SELF:txtFor:Text:Trim()

    PUBLIC CONSTRUCTOR( aFields AS List<STRING>, nCount AS INT )
        SELF:Text            := "DBReplace"
        SELF:FormBorderStyle := FormBorderStyle.FixedDialog
        SELF:StartPosition   := FormStartPosition.CenterParent
        SELF:MaximizeBox     := FALSE
        SELF:MinimizeBox     := FALSE
        SELF:ShowInTaskbar   := FALSE
        SELF:Font            := Font{ "Microsoft Sans Serif", 8.25 }
        SELF:ClientSize      := Size{ 470, 250 }

        SELF:Controls:Add( SELF:Caption( "Field", 15 ) )
        SELF:cmbField := ComboBox{}
        SELF:cmbField:DropDownStyle := ComboBoxStyle.DropDownList
        SELF:cmbField:Location := Point{ 110, 12 }
        SELF:cmbField:Size := Size{ 200, 21 }
        FOREACH cF AS STRING IN aFields
            SELF:cmbField:Items:Add( cF )
        NEXT
        IF SELF:cmbField:Items:Count > 0
            SELF:cmbField:SelectedIndex := 0
        ENDIF
        SELF:Controls:Add( SELF:cmbField )

        SELF:Controls:Add( SELF:Caption( "New value", 45 ) )
        SELF:txtValue := TextBox{}
        SELF:txtValue:Location := Point{ 110, 42 }
        SELF:txtValue:Size := Size{ 345, 20 }
        SELF:Controls:Add( SELF:txtValue )

        SELF:chkExpr := CheckBox{}
        SELF:chkExpr:Text := "evaluate as expression (e.g.  Upper(LASTNAME)  or  AMOUNT * 1.081)"
        SELF:chkExpr:Location := Point{ 110, 68 }
        SELF:chkExpr:AutoSize := TRUE
        SELF:Controls:Add( SELF:chkExpr )

        SELF:Controls:Add( SELF:Caption( "Scope", 100 ) )
        SELF:rbAll := RadioButton{}
        SELF:rbAll:Text := "all records of the current view (" + Convert.ToString( nCount ) + ")"
        SELF:rbAll:Location := Point{ 110, 98 }
        SELF:rbAll:AutoSize := TRUE
        SELF:rbAll:Checked := TRUE
        SELF:Controls:Add( SELF:rbAll )
        SELF:rbCurrent := RadioButton{}
        SELF:rbCurrent:Text := "current record only"
        SELF:rbCurrent:Location := Point{ 110, 120 }
        SELF:rbCurrent:AutoSize := TRUE
        SELF:Controls:Add( SELF:rbCurrent )

        SELF:Controls:Add( SELF:Caption( "Condition (For)", 153 ) )
        SELF:txtFor := TextBox{}
        SELF:txtFor:Location := Point{ 110, 150 }
        SELF:txtFor:Size := Size{ 345, 20 }
        SELF:Controls:Add( SELF:txtFor )
        LOCAL lblHint := Label{} AS Label
        lblHint:Text := "optional, e.g.  Empty(EMAIL)  -  filter, scope and show deleted of the view also apply."
        lblHint:Location := Point{ 110, 174 }
        lblHint:Size := Size{ 350, 30 }
        lblHint:ForeColor := Color.DimGray
        SELF:Controls:Add( lblHint )

        LOCAL bOK := Button{} AS Button
        bOK:Text := "Replace"
        bOK:Location := Point{ 295, 215 }
        bOK:Size := Size{ 75, 24 }
        bOK:DialogResult := System.Windows.Forms.DialogResult.OK
        LOCAL bCancel := Button{} AS Button
        bCancel:Text := "Cancel"
        bCancel:Location := Point{ 380, 215 }
        bCancel:Size := Size{ 75, 24 }
        bCancel:DialogResult := System.Windows.Forms.DialogResult.Cancel
        SELF:Controls:Add( bOK )
        SELF:Controls:Add( bCancel )
        SELF:AcceptButton := bOK
        SELF:CancelButton := bCancel
        RETURN

    PRIVATE METHOD Caption( cText AS STRING, nY AS INT ) AS Label
        LOCAL l := Label{} AS Label
        l:Text := cText
        l:Location := Point{ 12, nY }
        l:AutoSize := TRUE
        RETURN l
END CLASS

END NAMESPACE
