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

END CLASS

END NAMESPACE
