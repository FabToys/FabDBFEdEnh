USING System
USING System.Threading
USING XSharp
USING XSharp.RDD.Support
USING Xunit

BEGIN NAMESPACE FabDBFEdEnh.Tests

/// <summary>Smoke tests that drive a real DataWindow (not shown) to check that it is wired correctly to DbfTable.
/// WinForms controls need an STA thread, so each test body runs on its own STA thread.</summary>
PUBLIC CLASS DataWindowTests

    PRIVATE STATIC oBody  AS Action
    PRIVATE STATIC oError AS Exception

    PRIVATE STATIC METHOD StaMain() AS VOID
        TRY
            DataWindowTests.oBody:Invoke()
        CATCH ex AS Exception
            DataWindowTests.oError := ex
        END TRY
        RETURN

    PRIVATE STATIC METHOD RunSta( oAction AS Action ) AS VOID
        DataWindowTests.oBody  := oAction
        DataWindowTests.oError := NULL
        LOCAL oThread := Thread{ ThreadStart{ NULL, @StaMain() } } AS Thread
        oThread:SetApartmentState( ApartmentState.STA )
        oThread:Start()
        oThread:Join()
        IF DataWindowTests.oError != NULL
            THROW Exception{ "Test failed on the STA thread: " + DataWindowTests.oError:ToString() }
        ENDIF
        RETURN

    [Fact];
    PUBLIC METHOD OpenFile_ShowsAllRecords() AS VOID
        RunSta( { => DataWindowTests.OpenAndCount() } )
        RETURN

    PRIVATE STATIC METHOD OpenAndCount() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "QTY", "N", 5, 0 ) } AS RddFieldInfo[]
            LOCAL cFile := oData:CreateTable( "win", aFields ) AS STRING
            FOR VAR i := 1 TO 3
                oData:Append( cFile, <OBJECT>{ "N" + Convert.ToString( i ), i } )
            NEXT
            LOCAL oWin := DataWindow{} AS DataWindow
            Assert.True( oWin:OpenFile( cFile, "DBFCDX", TRUE, FALSE, TRUE, TRUE, TRUE, FALSE ) )
            Assert.Equal( 0, oWin:CountDeleted() )
            // deleted records are shown, so record 2 stays in the view and can be recalled
            oWin:GoToCloseRec( 2, FALSE )
            oWin:DeleteRecord( TRUE )
            Assert.Equal( 1, oWin:CountDeleted() )
            oWin:DeleteRecord( FALSE )
            Assert.Equal( 0, oWin:CountDeleted() )
            oWin:Close()
            oWin:Dispose()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD WriteUndoAppendPaste_WorkThroughTheWindow() AS VOID
        RunSta( { => DataWindowTests.EditAndPaste() } )
        RETURN

    PRIVATE STATIC METHOD EditAndPaste() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "QTY", "N", 5, 0 ) } AS RddFieldInfo[]
            LOCAL cFile := oData:CreateTable( "edit", aFields ) AS STRING
            oData:Append( cFile, <OBJECT>{ "ONE", 1 } )
            LOCAL oWin := DataWindow{} AS DataWindow
            Assert.True( oWin:OpenFile( cFile, "DBFCDX", TRUE, FALSE, TRUE, FALSE, TRUE, FALSE ) )
            // field write and undo
            Assert.True( oWin:WriteField( 1, 1, "7" ) )
            oWin:GoToCloseRec( 1, FALSE )
            oWin:Undo()
            // copy record 1 to the clipboard and paste it as a new record (no dialogs on this path)
            DbClip.Records:Clear()
            oWin:CopyRecord( FALSE )
            Assert.Equal( 1, DbClip.Records:Count )
            oWin:PasteAppend( FALSE )
            oWin:AppendRecord()
            Assert.Equal( 0, oWin:CountDeleted() )
            oWin:Close()
            oWin:Dispose()
        FINALLY
            DbClip.Records:Clear()
            oData:Dispose()
        END TRY
        RETURN

END CLASS

END NAMESPACE
