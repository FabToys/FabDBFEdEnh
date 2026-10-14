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
