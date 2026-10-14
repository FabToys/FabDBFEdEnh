USING System
USING System.Collections.Generic
USING XSharp
USING XSharp.RDD.Support
USING Xunit

BEGIN NAMESPACE FabDBFEdEnh.Tests

/// <summary>Table operations without any window: open, view (record list), delete / recall.</summary>
PUBLIC CLASS DbfTableTests

    // 5 records: NAME = A..E, QTY = 1..5
    PRIVATE STATIC METHOD CreateFive( oData AS TestData ) AS STRING
        LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "QTY", "N", 5, 0 ) } AS RddFieldInfo[]
        LOCAL cFile := oData:CreateTable( "five", aFields ) AS STRING
        FOR VAR i := 1 TO 5
            oData:Append( cFile, <OBJECT>{ Convert.ToString( (CHAR) ( 64 + i ) ), i } )
        NEXT
        RETURN cFile

    PRIVATE STATIC METHOD OpenTable( cFile AS STRING, lExcl AS LOGIC ) AS DbfTable
        LOCAL oTable := DbfTable{} AS DbfTable
        LOCAL cError := "" AS STRING
        Assert.True( oTable:Open( cFile, "DBFCDX", lExcl, FALSE, REF cError ), cError )
        RETURN oTable

    [Fact];
    PUBLIC METHOD Open_ReadsFieldMetadata() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            Assert.True( oTable:IsOpen )
            Assert.Equal( 2, oTable:FieldCount )
            Assert.Equal( "NAME", oTable:FieldName[0] )
            Assert.Equal( "C", oTable:FieldType[0] )
            Assert.Equal( "N", oTable:FieldType[1] )
            Assert.False( oTable:FieldAuto[0] )
            oTable:Close()
            Assert.False( oTable:IsOpen )
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD Open_MissingFileFailsWithMessage() AS VOID
        LOCAL oTable := DbfTable{} AS DbfTable
        LOCAL cError := "" AS STRING
        Assert.False( oTable:Open( "C:\does\not\exist.dbf", "DBFCDX", TRUE, FALSE, REF cError ) )
        Assert.NotEqual( "", cError )
        Assert.False( oTable:IsOpen )
        RETURN

    [Fact];
    PUBLIC METHOD MakeAlias_KeepsOnlyLettersDigitsUnderscore() AS VOID
        Assert.Equal( "MY_FILE_1", DbfTable.MakeAlias( "C:\data\my file-1.dbf" ) )
        Assert.Equal( "A_1ORDERS", DbfTable.MakeAlias( "1orders.dbf" ) )
        RETURN

    [Fact];
    PUBLIC METHOD LoadList_ListsAllRecordsInNaturalOrder() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:LoadList()
            Assert.Equal( 5, oTable:Recs:Count )
            Assert.Equal( 1L, oTable:Recs[0] )
            Assert.Equal( 5L, oTable:Recs[4] )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD SetDeleted_HidesRecordUntilShowDeleted() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            Assert.Equal( 1, oTable:SetDeleted( 2, TRUE ):Done )
            oTable:LoadList()
            Assert.Equal( 4, oTable:Recs:Count )
            Assert.DoesNotContain( 2L, oTable:Recs )
            oTable:ShowDeleted := TRUE
            oTable:LoadList()
            Assert.Equal( 5, oTable:Recs:Count )
            oTable:OnlyDeleted := TRUE
            oTable:LoadList()
            Assert.Equal( 1, oTable:Recs:Count )
            Assert.Equal( 2L, oTable:Recs[0] )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD SetDeleted_RecallRestoresRecord() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:SetDeleted( 3, TRUE )
            Assert.Equal( 1, oTable:CountDeleted() )
            Assert.Equal( 1, oTable:SetDeleted( 3, FALSE ):Done )
            Assert.Equal( 0, oTable:CountDeleted() )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD RecallAll_RecallsEveryDeletedRecord() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:SetDeleted( 1, TRUE )
            oTable:SetDeleted( 4, TRUE )
            Assert.Equal( 2, oTable:CountDeleted() )
            VAR oResult := oTable:RecallAll()
            Assert.Equal( 2, oResult:Done )
            Assert.False( oResult:Failed )
            Assert.Equal( 0, oTable:CountDeleted() )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD DeleteView_DeletesOnlyRecordsMatchingFilter() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:FilterCb := MCompile( "QTY >= 3" )
            oTable:LoadList()
            Assert.Equal( 3, oTable:Recs:Count )
            VAR oResult := oTable:DeleteView()
            Assert.Equal( 3, oResult:Done )
            Assert.Equal( 3, oTable:CountDeleted() )
            // the records outside the filter are untouched
            oTable:FilterCb := NULL
            oTable:LoadList()
            Assert.Equal( 2, oTable:Recs:Count )
            Assert.Equal( 1L, oTable:Recs[0] )
            Assert.Equal( 2L, oTable:Recs[1] )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD DeleteView_SkipsRecordsThatAreAlreadyDeleted() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:SetDeleted( 2, TRUE )
            oTable:ShowDeleted := TRUE            // record 2 is in the view, but already deleted
            oTable:LoadList()
            Assert.Equal( 5, oTable:Recs:Count )
            Assert.Equal( 4, oTable:DeleteView():Done )
            Assert.Equal( 5, oTable:CountDeleted() )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    // ------------------------------------------------------------------
    // Slice 2: writing, undo, append, clipboard
    // ------------------------------------------------------------------
    PRIVATE STATIC METHOD Qty( oTable AS DbfTable, nRec AS LONG ) AS DOUBLE
        RETURN Convert.ToDouble( oTable:ReadRecord( nRec )["QTY"] )

    [Fact];
    PUBLIC METHOD WriteField_ChangesValueAndUndoRestoresIt() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            Assert.False( oTable:CanUndo )
            VAR oResult := oTable:WriteField( 2, 1, "42" )
            Assert.Equal( 1, oResult:Done )
            Assert.Equal( 42.0, Qty( oTable, 2 ) )
            Assert.True( oTable:CanUndo )
            VAR oUndo := oTable:Undo()
            Assert.Equal( 1, oUndo:Done )
            Assert.Equal( 2L, oUndo:Rec )
            Assert.Equal( 2.0, Qty( oTable, 2 ) )
            Assert.False( oTable:CanUndo )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WriteField_RejectsInvalidInputAndKeepsValue() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            VAR oResult := oTable:WriteField( 3, 1, "abc" )
            Assert.True( oResult:Invalid )
            Assert.Equal( 0, oResult:Done )
            Assert.Equal( 3.0, Qty( oTable, 3 ) )
            Assert.False( oTable:CanUndo )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WriteField_DoesNothingOnReadOnlyFile() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL cFile := CreateFive( oData ) AS STRING
            LOCAL oTable := DbfTable{} AS DbfTable
            LOCAL cError := "" AS STRING
            Assert.True( oTable:Open( cFile, "DBFCDX", FALSE, TRUE, REF cError ), cError )
            Assert.False( oTable:IsWritable( 1 ) )
            VAR oResult := oTable:WriteField( 1, 1, "99" )
            Assert.Equal( 0, oResult:Done )
            Assert.False( oResult:Failed )
            Assert.Equal( 1.0, Qty( oTable, 1 ) )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD AppendRecord_AddsEmptyRecordAndReturnsItsNumber() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            VAR oResult := oTable:AppendRecord()
            Assert.Equal( 1, oResult:Done )
            Assert.Equal( 6L, oResult:Rec )
            oTable:LoadList()
            Assert.Equal( 6, oTable:Recs:Count )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD ConvertText_HandlesTypes() AS VOID
        Assert.Equal( 1.5, (DOUBLE) DbfTable.ConvertText( "1,5", "N" ) )
        Assert.Equal( 1250.0, (DOUBLE) DbfTable.ConvertText( "1'250", "N" ) )
        Assert.Equal( 0.0, (DOUBLE) DbfTable.ConvertText( "", "N" ) )
        Assert.Equal( TRUE, (LOGIC) DbfTable.ConvertText( "J", "L" ) )
        Assert.Equal( FALSE, (LOGIC) DbfTable.ConvertText( "x", "L" ) )
        Assert.Equal( DateTime.MinValue, (DateTime) DbfTable.ConvertText( "", "D" ) )
        Assert.Equal( "text", (STRING) DbfTable.ConvertText( "  text ", "C" ) )
        Assert.Throws<FormatException>( { => DbfTable.ConvertText( "abc", "N" ) } )
        RETURN

    [Fact];
    PUBLIC METHOD PasteAppend_AddsCopiesOfClipboardRecords() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            VAR aClip := List<Dictionary<STRING, OBJECT>>{}
            aClip:Add( oTable:ReadRecord( 2 ) )
            aClip:Add( oTable:ReadRecord( 4 ) )
            VAR oResult := oTable:PasteAppend( aClip )
            Assert.Equal( 2, oResult:Done )
            Assert.Equal( 7L, oResult:Rec )
            Assert.Empty( oResult:BadFields )
            Assert.Equal( 2.0, Qty( oTable, 6 ) )
            Assert.Equal( 4.0, Qty( oTable, 7 ) )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD PasteInto_OverwritesTheRecord() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            VAR oResult := oTable:PasteInto( 1, oTable:ReadRecord( 5 ) )
            Assert.Equal( 1, oResult:Done )
            Assert.Equal( 5.0, Qty( oTable, 1 ) )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    // ------------------------------------------------------------------
    // Slice 3: filter, scope, orders, zap
    // ------------------------------------------------------------------
    // records in file order: C, A, B (NAME), QTY 1..3
    PRIVATE STATIC METHOD CreateCab( oData AS TestData ) AS STRING
        LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "QTY", "N", 5, 0 ) } AS RddFieldInfo[]
        LOCAL cFile := oData:CreateTable( "cab", aFields ) AS STRING
        oData:Append( cFile, <OBJECT>{ "C", 1 } )
        oData:Append( cFile, <OBJECT>{ "A", 2 } )
        oData:Append( cFile, <OBJECT>{ "B", 3 } )
        RETURN cFile

    [Fact];
    PUBLIC METHOD CreateOrder_IsListedAndSortsTheView() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            Assert.True( oTable:CanRestructure )
            Assert.Equal( 1, oTable:CreateOrder( "BYNAME", "NAME", "", FALSE ):Done )
            Assert.Contains( "BYNAME", oTable:OrderNames() )
            VAR aOrders := oTable:GetOrders()
            Assert.Equal( "BYNAME", (STRING) aOrders[0]:GetValue( 0 ) )
            Assert.Equal( "NAME", (STRING) aOrders[0]:GetValue( 1 ) )
            Assert.Equal( 1, oTable:SetFocusOrder( "BYNAME" ):Done )
            oTable:ActiveOrder := "BYNAME"
            Assert.Equal( "BYNAME", oTable:CurrentOrderName() )
            Assert.Equal( "NAME", oTable:ActiveOrderKey() )
            oTable:LoadList()
            Assert.Equal( 3, oTable:Recs:Count )
            Assert.Equal( 2L, oTable:Recs[0] )      // A
            Assert.Equal( 3L, oTable:Recs[1] )      // B
            Assert.Equal( 1L, oTable:Recs[2] )      // C
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD Seek_FindsKeyInActiveOrder() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            oTable:CreateOrder( "BYNAME", "NAME", "", FALSE )
            oTable:SetFocusOrder( "BYNAME" )
            VAR oResult := oTable:Seek( "B" )
            Assert.Equal( 1, oResult:Done )
            Assert.Equal( 3L, oResult:Rec )
            // beyond the last key: the last record of the order
            Assert.Equal( 1L, oTable:Seek( "Z" ):Rec )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD SetScope_LimitsTheViewToTheKeyRange() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            oTable:CreateOrder( "BYNAME", "NAME", "", FALSE )
            oTable:SetFocusOrder( "BYNAME" )
            oTable:ActiveOrder := "BYNAME"
            Assert.Equal( 1, oTable:SetScope( "A", "B" ):Done )
            oTable:LoadList()
            Assert.Equal( 2, oTable:Recs:Count )
            Assert.DoesNotContain( 1L, oTable:Recs )   // C is outside the scope
            oTable:ClearScope()
            oTable:LoadList()
            Assert.Equal( 3, oTable:Recs:Count )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD SetFilter_AcceptsLogicalAndRejectsOtherExpressions() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            Assert.Equal( 1, oTable:SetFilter( "QTY > 1" ):Done )
            Assert.Equal( "QTY > 1", oTable:FilterText )
            oTable:LoadList()
            Assert.Equal( 2, oTable:Recs:Count )
            // not logical: rejected, the previous filter stays
            VAR oBad := oTable:SetFilter( "QTY + 1" )
            Assert.True( oBad:Invalid )
            Assert.Equal( "QTY > 1", oTable:FilterText )
            // empty = filter off
            Assert.Equal( 1, oTable:SetFilter( "  " ):Done )
            Assert.Equal( "", oTable:FilterText )
            oTable:LoadList()
            Assert.Equal( 3, oTable:Recs:Count )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD DestroyOrder_RemovesItFromTheList() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            oTable:CreateOrder( "BYNAME", "NAME", "", FALSE )
            oTable:CreateOrder( "BYQTY", "STR(QTY,5)", "", FALSE )
            Assert.Equal( 2, oTable:OrderNames():Count )
            Assert.Equal( 1, oTable:DestroyOrder( "BYNAME", "" ):Done )
            Assert.Single( oTable:OrderNames() )
            Assert.Equal( "BYQTY", oTable:OrderNames()[0] )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD RebuildOrders_ReplacesAllOrdersOfTheProductionCdx() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            oTable:CreateOrder( "BYNAME", "NAME", "", FALSE )
            VAR aList := List<STRING[]>{}
            aList:Add( <STRING>{ "BYQTY", "STR(QTY,5)", "", "0" } )
            aList:Add( <STRING>{ "BYNAME2", "NAME", "", "0" } )
            VAR aStatus := oTable:RebuildOrders( aList )
            Assert.Equal( 2, aStatus:Count )
            Assert.Equal( "", aStatus[0] )
            Assert.Equal( "", aStatus[1] )
            VAR aNames := oTable:OrderNames()
            Assert.Equal( 2, aNames:Count )
            Assert.DoesNotContain( "BYNAME", aNames )
            Assert.Equal( 1, oTable:ReIndex():Done )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD Zap_RemovesAllRecords() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            Assert.Equal( 3L, oTable:RecordCount() )
            Assert.Equal( 1, oTable:Zap():Done )
            Assert.Equal( 0L, oTable:RecordCount() )
            oTable:LoadList()
            Assert.Equal( 0, oTable:Recs:Count )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD CanRestructure_IsFalseWhenSharedOrReadOnly() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL cFile := CreateCab( oData ) AS STRING
            VAR oShared := OpenTable( cFile, FALSE )
            Assert.False( oShared:CanRestructure )
            oShared:Close()
            LOCAL oRo := DbfTable{} AS DbfTable
            LOCAL cError := "" AS STRING
            Assert.True( oRo:Open( cFile, "DBFCDX", TRUE, TRUE, REF cError ), cError )
            Assert.False( oRo:CanRestructure )
            oRo:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    // ------------------------------------------------------------------
    // Slice 4: reading rows and raw bytes, replace, JSON
    // ------------------------------------------------------------------
    [Fact];
    PUBLIC METHOD ReadRow_ReturnsValuesInFieldOrderWithDeletedFlag() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:SetDeleted( 2, TRUE )
            LOCAL lDel := TRUE AS LOGIC
            VAR aRow := oTable:ReadRow( 1, TRUE, REF lDel )
            Assert.False( lDel )
            Assert.Equal( 2, aRow:Count )
            Assert.Equal( "A", Convert.ToString( aRow[0] ):Trim() )
            Assert.Equal( 1.0, Convert.ToDouble( aRow[1] ) )
            oTable:ReadRow( 2, TRUE, REF lDel )
            Assert.True( lDel )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD MemoPreview_CutsLongTextAndFlattensLineBreaks() AS VOID
        Assert.Equal( "", DbfTable.MemoPreview( NULL ) )
        Assert.Equal( "one two three", DbfTable.MemoPreview( "one" + Environment.NewLine + "two" + Environment.NewLine + "three" ) )
        VAR cLong := String{ (CHAR) 120, 300 }
        VAR cPreview := DbfTable.MemoPreview( cLong )
        Assert.Equal( 203, cPreview:Length )
        Assert.EndsWith( "...", cPreview )

    [Fact];
    PUBLIC METHOD RawReaders_ReturnHeaderRecordAndFieldBytes() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), FALSE )       // shared: the file can be read directly
            oTable:Commit()
            Assert.Equal( 1, oTable:FieldOffset( 0 ) )
            Assert.Equal( 11, oTable:FieldOffset( 1 ) )
            Assert.Equal( 10, oTable:FieldLength[0] )
            VAR aHeader := oTable:ReadHeader()
            Assert.NotNull( aHeader )
            Assert.Equal( 12, aHeader:Length )
            VAR aRecord := oTable:ReadRecordBytes( 3 )
            Assert.Equal( 16, aRecord:Length )                         // 1 flag + 10 + 5
            Assert.Equal( (BYTE) 32, aRecord[1] )                      // not deleted: blank
            VAR aName := oTable:ReadFieldBytes( 3, 0 )
            Assert.Equal( "C         ", System.Text.Encoding.ASCII:GetString( aName ) )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD ReadMemoBytes_ReadsTheBlockFromTheFptFile() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "NOTE", "M", 10, 0 ) } AS RddFieldInfo[]
            LOCAL cFile := oData:CreateTable( "memo2", aFields ) AS STRING
            oData:Append( cFile, <OBJECT>{ "ONE", "hello memo" } )
            oData:Append( cFile, <OBJECT>{ "TWO", "" } )
            VAR oTable := OpenTable( cFile, FALSE )
            oTable:Commit()
            VAR aBytes := oTable:ReadMemoBytes( 1, 1 )
            Assert.NotNull( aBytes )
            Assert.Equal( "hello memo", System.Text.Encoding.ASCII:GetString( aBytes ) )
            // empty memo: an empty array (the window then says "The memo is empty")
            Assert.Equal( 0, oTable:ReadMemoBytes( 2, 1 ):Length )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD ReplaceField_AssignsValueToMatchingRecordsOnly() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:LoadList()
            VAR oFor := oTable:Compile( "QTY > 3" )
            VAR oResult := oTable:ReplaceField( 1, NULL, 99.0, oFor, oTable:Recs )
            Assert.Equal( 2, oResult:Done )
            Assert.Equal( 0, oResult:Errors )
            Assert.Equal( 1.0, Convert.ToDouble( oTable:ReadRecord( 1 )["QTY"] ) )
            Assert.Equal( 99.0, Convert.ToDouble( oTable:ReadRecord( 4 )["QTY"] ) )
            Assert.Equal( 99.0, Convert.ToDouble( oTable:ReadRecord( 5 )["QTY"] ) )
            // computed value
            VAR oExpr := oTable:Compile( "QTY * 2" )
            VAR oAll := oTable:ReplaceField( 1, oExpr, NULL, NULL, oTable:Recs )
            Assert.Equal( 5, oAll:Done )
            Assert.Equal( 2.0, Convert.ToDouble( oTable:ReadRecord( 1 )["QTY"] ) )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WriteJson_WritesViewOrWholeFile() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:SetDeleted( 2, TRUE )
            oTable:LoadList()                                            // view: 4 records (deleted hidden)
            LOCAL cView := System.IO.Path.Combine( oData:Folder, "view.json" ) AS STRING
            LOCAL cAll  := System.IO.Path.Combine( oData:Folder, "all.json" ) AS STRING
            Assert.Equal( 4, oTable:WriteJson( cView, FALSE ) )
            Assert.Equal( 5, oTable:WriteJson( cAll, TRUE ) )
            LOCAL cText := System.IO.File.ReadAllText( cAll ) AS STRING
            Assert.Contains( """RecNo"": 2", cText )
            Assert.Contains( """Deleted"": ""*""", cText )
            Assert.Contains( """NAME"": ""B         """, cText )          // character values keep their padding
            Assert.DoesNotContain( """RecNo"": 2", System.IO.File.ReadAllText( cView ) )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD JsonValue_NormalisesEmptyDatesAndPassesOthersThrough() AS VOID
        Assert.Null( DbfTable.JsonValue( NULL ) )
        Assert.Null( DbfTable.JsonValue( System.DBNull.Value ) )
        Assert.Null( DbfTable.JsonValue( DateTime.MinValue ) )
        Assert.Equal( "x", DbfTable.JsonValue( "x" ) )
        Assert.Equal( 5, DbfTable.JsonValue( 5 ) )
        RETURN

    // ------------------------------------------------------------------
    // Generate Create PRG / description (ScriptGenerator)
    // ------------------------------------------------------------------
    PRIVATE STATIC METHOD Script( oTable AS DbfTable, nStyle AS INT, lIndexes AS LOGIC, lRecords AS LOGIC, lViewOnly AS LOGIC, nCount REF INT ) AS STRING
        VAR o := ScriptOptions{}
        o:Style    := nStyle
        o:Indexes  := lIndexes
        o:Records  := lRecords
        o:ViewOnly := lViewOnly
        VAR w := System.IO.StringWriter{}
        nCount := ScriptGenerator.WriteScript( w, oTable, o )
        RETURN w:ToString()

    [Fact];
    PUBLIC METHOD ScriptLiterals_QuoteTextForXSharpAndFoxPro() AS VOID
        LOCAL cQuote := ( (CHAR) 34 ):ToString() AS STRING
        LOCAL cSlash := ( (CHAR) 92 ):ToString() AS STRING
        Assert.Equal( cQuote + "plain" + cQuote, ScriptGenerator.XsString( "plain" ) )
        // a quote inside: e-string with the quote escaped by a backslash
        Assert.Equal( "e" + cQuote + "say " + cSlash + cQuote + "hi" + cSlash + cQuote + cQuote, ;
            ScriptGenerator.XsString( "say " + cQuote + "hi" + cQuote ) )
        // a line break: \r\n
        Assert.Contains( cSlash + "r" + cSlash + "n", ScriptGenerator.XsString( "a" + Environment.NewLine + "b" ) )
        Assert.Equal( "''", ScriptGenerator.VfpString( "" ) )
        Assert.Equal( "'abc'", ScriptGenerator.VfpString( "abc" ) )
        Assert.Equal( "'it' + CHR(39) + 's'", ScriptGenerator.VfpString( "it's" ) )
        Assert.Equal( "'a' + CHR(13) + CHR(10) + 'b'", ScriptGenerator.VfpString( "a" + Environment.NewLine + "b" ) )
        RETURN

    [Fact];
    PUBLIC METHOD ScriptNames_AndFoxProTypes() AS VOID
        Assert.Equal( "CreateCustomers", ScriptGenerator.FunctionName( "C:\data\customers.dbf" ) )
        VAR fC := FieldDef{ "NAME", "C", 30, 0, "NAME" }
        VAR fN := FieldDef{ "AMOUNT", "N", 12, 2, "AMOUNT" }
        VAR fI := FieldDef{ "ID", "I", 4, 0, "ID" }
        fI:Extra := "+"
        VAR fM := FieldDef{ "BLOB", "M", 10, 0, "BLOB" }
        fM:Extra := "B"
        VAR fX := FieldDef{ "ODD", "Z", 4, 0, "ODD" }
        Assert.Equal( "C(30)", ScriptGenerator.VfpType( fC ) )
        Assert.Equal( "N(12,2)", ScriptGenerator.VfpType( fN ) )
        Assert.Equal( "I AUTOINC", ScriptGenerator.VfpType( fI ) )
        Assert.Equal( "M NOCPTRANS", ScriptGenerator.VfpType( fM ) )
        Assert.Equal( "", ScriptGenerator.VfpType( fX ) )
        RETURN

    [Fact];
    PUBLIC METHOD WriteScript_DbCreateStyleWithIndexAndRecords() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            oTable:CreateOrder( "BYNAME", "NAME", "", FALSE )
            oTable:SetDeleted( 3, TRUE )                                   // B is deleted: not exported
            LOCAL nCount := 0 AS INT
            VAR cText := Script( oTable, ScriptOptions.StyleDbCreate, TRUE, TRUE, FALSE, REF nCount )
            Assert.Equal( 2, nCount )
            Assert.Contains( "FUNCTION CreateCab( cFile AS STRING ) AS LOGIC", cText )
            Assert.Contains( "{ ""NAME"", ""C"", 10, 0 }", cText )
            Assert.Contains( "DbCreate( cFile, aStruct, ""DBFCDX"" )", cText )
            Assert.Contains( "CreateCabRow( { ""C"", 1 } )", cText )
            Assert.Contains( "CreateCabRow( { ""A"", 2 } )", cText )
            Assert.DoesNotContain( "{ ""B"", 3 }", cText )
            Assert.Contains( "OrdCreate( cFile, ""BYNAME"", ""NAME"", {|| NAME } )", cText )
            // without records and indexes: structure only
            VAR cShort := Script( oTable, ScriptOptions.StyleDbCreate, FALSE, FALSE, FALSE, REF nCount )
            Assert.Equal( 0, nCount )
            Assert.DoesNotContain( "OrdCreate", cShort )
            Assert.DoesNotContain( "Row(", cShort )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WriteScript_RddFieldInfoStyle() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            LOCAL nCount := 0 AS INT
            VAR cText := Script( oTable, ScriptOptions.StyleRddFieldInfo, TRUE, TRUE, FALSE, REF nCount )
            Assert.Equal( 3, nCount )
            Assert.Contains( "RddFieldInfo{ ""NAME"", ""C"", 10, 0 }", cText )
            Assert.Contains( "CoreDb.Create( cFile, aFields, ""DBFCDX"", TRUE, ""CAB"", """", FALSE, FALSE )", cText )
            Assert.Contains( "CreateCabRow( <OBJECT>{ ""C"", 1 } )", cText )
            Assert.Contains( "STATIC FUNCTION CreateCabRow( aValues AS OBJECT[] ) AS VOID", cText )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WriteScript_FoxProStyleWithAllTypes() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "DUE", "D", 8, 0 ), ;
                TestData.Field( "OK", "L", 1, 0 ), TestData.Field( "NOTE", "M", 10, 0 ) } AS RddFieldInfo[]
            LOCAL cFile := oData:CreateTable( "types", aFields ) AS STRING
            oData:Append( cFile, <OBJECT>{ "O'Neil", DateTime{ 2026, 10, 14 }, TRUE, "line1" + Environment.NewLine + "line2" } )
            VAR oTable := OpenTable( cFile, TRUE )
            oTable:CreateOrder( "BYNAME", "NAME", "", FALSE )
            LOCAL nCount := 0 AS INT
            VAR cFox := Script( oTable, ScriptOptions.StyleVisualFoxPro, TRUE, TRUE, FALSE, REF nCount )
            Assert.Equal( 1, nCount )
            Assert.Contains( "CREATE TABLE types ( ;", cFox )
            Assert.Contains( "NAME C(10), ;", cFox )
            Assert.Contains( "DUE D, ;", cFox )
            Assert.Contains( "OK L, ;", cFox )
            Assert.Contains( "NOTE M )", cFox )
            Assert.Contains( "INSERT INTO types ( NAME, DUE, OK, NOTE ) VALUES ( 'O' + CHR(39) + 'Neil', {^2026-10-14}, .T., 'line1' + CHR(13) + CHR(10) + 'line2' )", cFox )
            Assert.Contains( "INDEX ON NAME TAG BYNAME", cFox )
            // the same data as X#: date as SToD in the VO style, DateTime{} in the Core style
            VAR cVo := Script( oTable, ScriptOptions.StyleDbCreate, FALSE, TRUE, FALSE, REF nCount )
            Assert.Contains( "SToD( ""20261014"" )", cVo )
            VAR cCore := Script( oTable, ScriptOptions.StyleRddFieldInfo, FALSE, TRUE, FALSE, REF nCount )
            Assert.Contains( "DateTime{ 2026, 10, 14 }", cCore )
            Assert.Contains( "TRUE", cCore )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD ScriptValues_FormatIntegersFloatsAndDecimalsInvariantly() AS VOID
        // a Visual FoxPro integer field (type I) delivers Int32: the "R" format of doubles must not be used for it
        Assert.Equal( "42", ScriptGenerator.XsValue( 42, "I", TRUE ) )
        Assert.Equal( "42", ScriptGenerator.XsValue( 42, "I", FALSE ) )
        Assert.Equal( "-7", ScriptGenerator.XsValue( (INT64) -7, "N", TRUE ) )
        Assert.Equal( "19.99", ScriptGenerator.XsValue( 19.99, "N", TRUE ) )
        Assert.Equal( "1.5", ScriptGenerator.XsValue( System.Convert.ToDecimal( 1.5 ), "Y", FALSE ) )
        Assert.Equal( "42", ScriptGenerator.VfpValue( 42, "I" ) )
        Assert.Equal( "19.99", ScriptGenerator.VfpValue( 19.99, "N" ) )
        // nothing to write: NIL / NULL, and the FoxPro defaults
        Assert.Equal( "NIL", ScriptGenerator.XsValue( NULL, "C", TRUE ) )
        Assert.Equal( "NULL", ScriptGenerator.XsValue( NULL, "C", FALSE ) )
        Assert.Equal( "{}", ScriptGenerator.VfpValue( NULL, "D" ) )
        Assert.Equal( "0", ScriptGenerator.VfpValue( NULL, "I" ) )
        RETURN

    [Fact];
    PUBLIC METHOD WriteScript_ArrayLiteralEndsWithoutLineContinuation() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            LOCAL nCount := 0 AS INT
            VAR cVo := Script( oTable, ScriptOptions.StyleDbCreate, FALSE, FALSE, FALSE, REF nCount )
            Assert.Contains( "{ ""QTY"", ""N"", 5, 0 } }" + Environment.NewLine, cVo )
            VAR cCore := Script( oTable, ScriptOptions.StyleRddFieldInfo, FALSE, FALSE, FALSE, REF nCount )
            Assert.Contains( "RddFieldInfo{ ""QTY"", ""N"", 5, 0 } } ;", cCore )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WriteScript_ViewOnlyExportsTheFilteredRecords() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:SetFilter( "QTY >= 4" )
            oTable:LoadList()
            LOCAL nCount := 0 AS INT
            VAR cView := Script( oTable, ScriptOptions.StyleDbCreate, FALSE, TRUE, TRUE, REF nCount )
            Assert.Equal( 2, nCount )
            Assert.Contains( "{ ""D"", 4 }", cView )
            Assert.DoesNotContain( "{ ""A"", 1 }", cView )
            Script( oTable, ScriptOptions.StyleDbCreate, FALSE, TRUE, FALSE, REF nCount )
            Assert.Equal( 5, nCount )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WriteDescription_ListsFieldsOffsetsAndIndexes() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateCab( oData ), TRUE )
            oTable:CreateOrder( "BYNAME", "NAME", "", FALSE )
            VAR w := System.IO.StringWriter{}
            ScriptGenerator.WriteDescription( w, oTable )
            VAR cText := w:ToString()
            Assert.Contains( "Records       : 3", cText )
            Assert.Contains( "Record length : 16 bytes", cText )
            Assert.Contains( "Fields        : 2", cText )
            Assert.Contains( " 1  NAME ", cText )
            Assert.Contains( " 2  QTY ", cText )
            Assert.Contains( "Indexes: 1", cText )
            Assert.Contains( "BYNAME", cText )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    // ------------------------------------------------------------------
    // Wild seek
    // ------------------------------------------------------------------
    [Fact];
    PUBLIC METHOD WildMatchText_FollowsTheChosenMode() AS VOID
        // contains (case does not matter, trailing blanks ignored)
        Assert.True( DbfTable.WildMatchText( "Anchor Plastic   ", "plast", DbfTable.WildContains ) )
        Assert.False( DbfTable.WildMatchText( "Anchor Plastic", "xyz", DbfTable.WildContains ) )
        // begins with
        Assert.True( DbfTable.WildMatchText( "Anchor Plastic", "ANCH", DbfTable.WildBegins ) )
        Assert.False( DbfTable.WildMatchText( "Anchor Plastic", "plastic", DbfTable.WildBegins ) )
        // exact: the whole field
        Assert.True( DbfTable.WildMatchText( "Texas     ", "texas", DbfTable.WildExact ) )
        Assert.False( DbfTable.WildMatchText( "Texas", "tex", DbfTable.WildExact ) )
        // pattern
        Assert.True( DbfTable.WildMatchText( "Billy Bob Electrical", "b*electr*", DbfTable.WildPattern ) )
        Assert.False( DbfTable.WildMatchText( "Billy Bob Electrical", "electr*", DbfTable.WildPattern ) )
        Assert.False( DbfTable.WildMatchText( NULL, "x", DbfTable.WildContains ) )
        RETURN

    [Fact];
    PUBLIC METHOD Glob_StarQuestionMarkAndBacktracking() AS VOID
        Assert.True( DbfTable.Glob( "ABC", "A*C" ) )
        Assert.True( DbfTable.Glob( "AC", "A*C" ) )
        Assert.True( DbfTable.Glob( "ABC", "A?C" ) )
        Assert.False( DbfTable.Glob( "AC", "A?C" ) )
        Assert.True( DbfTable.Glob( "ABCBC", "A*BC" ) )               // needs backtracking
        Assert.True( DbfTable.Glob( "ANYTHING", "*" ) )
        Assert.True( DbfTable.Glob( "", "*" ) )
        Assert.False( DbfTable.Glob( "ABC", "AB" ) )
        Assert.False( DbfTable.Glob( "AB", "ABC" ) )
        Assert.True( DbfTable.Glob( "ABC", "***ABC***" ) )
        RETURN

    [Fact];
    PUBLIC METHOD WildFieldText_UsesTheDisplayedText() AS VOID
        Assert.Equal( "12.50", DbfTable.WildFieldText( 12.5, "N", 2 ) )
        Assert.Equal( "T", DbfTable.WildFieldText( TRUE, "L", 0 ) )
        Assert.Equal( "", DbfTable.WildFieldText( DateTime.MinValue, "D", 0 ) )
        Assert.Equal( "", DbfTable.WildFieldText( NULL, "C", 0 ) )
        Assert.Equal( "abc", DbfTable.WildFieldText( "abc   ", "C", 0 ) )
        Assert.Equal( "", DbfTable.WildFieldText( BYTE[]{ 3 }, "M", 0 ) )
        RETURN

    [Fact];
    PUBLIC METHOD WildSeek_RestrictsTheViewToMatchingRecords() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 20, 0 ), TestData.Field( "CITY", "C", 20, 0 ), ;
                TestData.Field( "NOTE", "M", 10, 0 ) } AS RddFieldInfo[]
            LOCAL cFile := oData:CreateTable( "wild", aFields ) AS STRING
            oData:Append( cFile, <OBJECT>{ "Anchor Plastic", "Temple", "good customer" } )
            oData:Append( cFile, <OBJECT>{ "Billy Bob", "Yukon", "late payer" } )
            oData:Append( cFile, <OBJECT>{ "Craig Tucker", "Temple", "" } )
            oData:Append( cFile, <OBJECT>{ "Patty", "Trinton", "likes plastic" } )
            VAR oTable := OpenTable( cFile, TRUE )
            // all fields (memos not searched): "temple" is in the CITY of records 1 and 3
            oTable:SetWild( "temple", -1, DbfTable.WildContains, FALSE )
            oTable:LoadList()
            Assert.Equal( 2, oTable:Recs:Count )
            Assert.Equal( 1L, oTable:Recs[0] )
            Assert.Equal( 3L, oTable:Recs[1] )
            // "plastic" is in NAME of record 1 and only in the MEMO of record 4
            oTable:SetWild( "plastic", -1, DbfTable.WildContains, FALSE )
            oTable:LoadList()
            Assert.Single( oTable:Recs )
            oTable:SetWild( "plastic", -1, DbfTable.WildContains, TRUE )
            oTable:LoadList()
            Assert.Equal( 2, oTable:Recs:Count )
            // one field only: NAME does not contain "temple"
            oTable:SetWild( "temple", 0, DbfTable.WildContains, FALSE )
            oTable:LoadList()
            Assert.Empty( oTable:Recs )
            // one field, begins with
            oTable:SetWild( "b", 0, DbfTable.WildBegins, FALSE )
            oTable:LoadList()
            Assert.Single( oTable:Recs )
            Assert.Equal( 2L, oTable:Recs[0] )
            // a memo field chosen explicitly is searched even without the memo option
            oTable:SetWild( "late", 2, DbfTable.WildContains, FALSE )
            oTable:LoadList()
            Assert.Single( oTable:Recs )
            // off again
            oTable:ClearWild()
            oTable:LoadList()
            Assert.Equal( 4, oTable:Recs:Count )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WildSeek_IsCombinedWithFilterAndDeletedHandling() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )
            oTable:SetFilter( "QTY >= 3" )                               // C, D, E ... as records 3, 4, 5
            oTable:SetWild( "d", 0, DbfTable.WildContains, FALSE )
            oTable:LoadList()
            Assert.Single( oTable:Recs )
            Assert.Equal( 4L, oTable:Recs[0] )
            // a deleted record is hidden like before, and shown when deleted records are shown
            oTable:SetDeleted( 4, TRUE )
            oTable:LoadList()
            Assert.Empty( oTable:Recs )
            oTable:ShowDeleted := TRUE
            oTable:LoadList()
            Assert.Single( oTable:Recs )
            // numbers are searched as shown: QTY 3 is "3.00" with two decimals? here 0 decimals: "3"
            oTable:SetFilter( "" )
            oTable:ShowDeleted := FALSE
            oTable:SetWild( "3", 1, DbfTable.WildExact, FALSE )
            oTable:LoadList()
            Assert.Single( oTable:Recs )
            Assert.Equal( 3L, oTable:Recs[0] )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    // ------------------------------------------------------------------
    // DBFNTX: one file per order
    // ------------------------------------------------------------------
    PRIVATE STATIC METHOD OpenNtxCab( oData AS TestData ) AS DbfTable
        oData:Driver := "DBFNTX"
        LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "QTY", "N", 5, 0 ) } AS RddFieldInfo[]
        LOCAL cFile := oData:CreateTable( "ntxcab", aFields ) AS STRING
        oData:Append( cFile, <OBJECT>{ "C", 1 } )
        oData:Append( cFile, <OBJECT>{ "A", 2 } )
        oData:Append( cFile, <OBJECT>{ "B", 3 } )
        LOCAL oTable := DbfTable{} AS DbfTable
        LOCAL cError := "" AS STRING
        Assert.True( oTable:Open( cFile, "DBFNTX", TRUE, FALSE, REF cError ), cError )
        Assert.True( oTable:IsNtx )
        RETURN oTable

    PRIVATE STATIC METHOD NtxList() AS List<STRING[]>
        VAR aList := List<STRING[]>{}
        aList:Add( <STRING>{ "BYNAME", "NAME", "", "0" } )
        aList:Add( <STRING>{ "BYQTY", "STR(QTY,5)", "", "0" } )
        RETURN aList

    [Fact];
    PUBLIC METHOD NtxOrders_AreCreatedAsSeparateFiles() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenNtxCab( oData )
            Assert.Empty( StructureRebuild.ExistingNtxFiles( oTable:FileName, NtxList() ) )
            VAR aStatus := oTable:RebuildNtxOrders( NtxList(), TRUE )
            Assert.Equal( 2, aStatus:Count )
            Assert.Equal( "", aStatus[0] )
            Assert.Equal( "", aStatus[1] )
            Assert.True( System.IO.File.Exists( StructureRebuild.NtxPath( oTable:FileName, "BYNAME" ) ) )
            Assert.True( System.IO.File.Exists( StructureRebuild.NtxPath( oTable:FileName, "BYQTY" ) ) )
            Assert.Contains( "BYNAME", oTable:OrderNames() )
            Assert.Contains( "BYQTY", oTable:OrderNames() )
            // the order sorts: A, B, C
            oTable:SetFocusOrder( "BYNAME" )
            oTable:ActiveOrder := "BYNAME"
            oTable:LoadList()
            Assert.Equal( 2L, oTable:Recs[0] )
            Assert.Equal( 1L, oTable:Recs[2] )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD NtxOrders_ExistingFilesAreReplacedOrKept() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenNtxCab( oData )
            oTable:RebuildNtxOrders( NtxList(), TRUE )
            Assert.Equal( 2, StructureRebuild.ExistingNtxFiles( oTable:FileName, NtxList() ):Count )
            LOCAL cByName := StructureRebuild.NtxPath( oTable:FileName, "BYNAME" ) AS STRING
            // Yes: replaced (no error, orders open again)
            VAR aYes := oTable:RebuildNtxOrders( NtxList(), TRUE )
            Assert.Equal( "", aYes[0] )
            Assert.Equal( "", aYes[1] )
            Assert.True( System.IO.File.Exists( cByName ) )
            Assert.Contains( "BYNAME", oTable:OrderNames() )
            // No: the files are kept, reported as information, and their orders are available
            LOCAL cTable := oTable:FileName AS STRING
            oTable:Close()
            System.IO.File.SetLastWriteTime( cByName, DateTime{ 2001, 1, 1 } )     // marker: the file must not be rewritten
            oTable := DbfTable{}
            LOCAL cError := "" AS STRING
            Assert.True( oTable:Open( cTable, "DBFNTX", TRUE, FALSE, REF cError ), cError )
            VAR aNo := oTable:RebuildNtxOrders( NtxList(), FALSE )
            Assert.StartsWith( "~", aNo[0] )
            Assert.StartsWith( "~", aNo[1] )
            Assert.Equal( DateTime{ 2001, 1, 1 }, System.IO.File.GetLastWriteTime( cByName ) )   // not touched
            Assert.Contains( "BYNAME", oTable:OrderNames() )
            Assert.Contains( "BYQTY", oTable:OrderNames() )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD CreateOrder_ForConditionIsAppliedForCdx() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenTable( CreateFive( oData ), TRUE )              // QTY 1..5
            Assert.Equal( 1, oTable:CreateOrder( "BIG", "STR(QTY,5)", "QTY > 3", FALSE ):Done )
            oTable:SetFocusOrder( "BIG" )
            oTable:ActiveOrder := "BIG"
            oTable:LoadList()
            Assert.Equal( 2, oTable:Recs:Count )                               // only records 4 and 5 are in the order
            VAR aOrders := oTable:GetOrders()
            Assert.Equal( "QTY > 3", (STRING) aOrders[0]:GetValue( 2 ) )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD CreateOrder_ForConditionIsAppliedForNtx() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenNtxCab( oData )                                  // QTY 1..3
            Assert.Equal( 1, oTable:CreateOrder( "BIG", "STR(QTY,5)", "QTY > 1", FALSE ):Done )
            oTable:SetFocusOrder( "BIG" )
            oTable:ActiveOrder := "BIG"
            oTable:LoadList()
            Assert.Equal( 2, oTable:Recs:Count )
            Assert.Equal( "QTY > 1", (STRING) oTable:OpenOrders()[0]:GetValue( 2 ) )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD NtxOrders_OtherOpenIndexFilesStayOpen() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenNtxCab( oData )
            Assert.Equal( 1, oTable:CreateOrder( "OTHER", "UPPER(NAME)", "", FALSE ):Done )
            VAR aOnlyOne := List<STRING[]>{}
            aOnlyOne:Add( <STRING>{ "BYNAME", "NAME", "", "0" } )
            VAR aStatus := oTable:RebuildNtxOrders( aOnlyOne, TRUE )
            Assert.Equal( "", aStatus[0] )
            VAR aNames := oTable:OrderNames()
            Assert.Contains( "BYNAME", aNames )
            Assert.Contains( "OTHER", aNames )           // was open before and is open again
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD OpenOrders_ListsNameKeyForAndUnique() AS VOID
        VAR oData := TestData{}
        TRY
            VAR oTable := OpenNtxCab( oData )
            oTable:CreateOrder( "BYNAME", "NAME", "", FALSE )
            oTable:CreateOrder( "ONLYBIG", "STR(QTY,5)", "QTY > 1", FALSE )
            VAR aOpen := oTable:OpenOrders()
            Assert.Equal( 2, aOpen:Count )
            Assert.Equal( "BYNAME", (STRING) aOpen[0]:GetValue( 0 ) )
            Assert.Equal( "NAME", (STRING) aOpen[0]:GetValue( 1 ) )
            Assert.Equal( "QTY > 1", (STRING) aOpen[1]:GetValue( 2 ) )
            Assert.Equal( "0", (STRING) aOpen[1]:GetValue( 3 ) )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WriteMemo_StoresTextAndAllowsUndo() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "NOTE", "M", 10, 0 ) } AS RddFieldInfo[]
            LOCAL cFile := oData:CreateTable( "memo", aFields ) AS STRING
            oData:Append( cFile, <OBJECT>{ "ONE", "first" } )
            VAR oTable := OpenTable( cFile, TRUE )
            Assert.Equal( 1, oTable:WriteMemo( 1, 1, "second", "first" ):Done )
            Assert.Equal( "second", Convert.ToString( oTable:ReadRecord( 1 )["NOTE"] ):Trim() )
            Assert.Equal( 1, oTable:Undo():Done )
            Assert.Equal( "first", Convert.ToString( oTable:ReadRecord( 1 )["NOTE"] ):Trim() )
            oTable:Close()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

END CLASS

END NAMESPACE
