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

    [Fact];
    PUBLIC METHOD WildSeek_WorksThroughTheWindow() AS VOID
        RunSta( { => DataWindowTests.WildSeekOnWindow() } )
        RETURN

    PRIVATE STATIC METHOD WildSeekOnWindow() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "QTY", "N", 5, 0 ) } AS RddFieldInfo[]
            LOCAL cFile := oData:CreateTable( "seekwin", aFields ) AS STRING
            oData:Append( cFile, <OBJECT>{ "Alpha", 1 } )
            oData:Append( cFile, <OBJECT>{ "Beta", 2 } )
            oData:Append( cFile, <OBJECT>{ "Gamma", 3 } )
            LOCAL oWin := DataWindow{} AS DataWindow
            Assert.True( oWin:OpenFile( cFile, "DBFCDX", TRUE, FALSE, TRUE, FALSE, TRUE, FALSE ) )
            Assert.Equal( 3, oWin:SetWildSeek( "a", -1, DbfTable.WildContains, FALSE ) )     // Alpha, Beta, Gamma all contain an a
            Assert.Equal( 1, oWin:SetWildSeek( "et", -1, DbfTable.WildContains, FALSE ) )    // Beta
            Assert.Equal( "et", oWin:WildText )
            Assert.Contains( "WILD", oWin:Text )
            Assert.Equal( 1, oWin:SetWildSeek( "g*", 0, DbfTable.WildPattern, FALSE ) )
            oWin:ClearWildSeek()
            Assert.Equal( "", oWin:WildText )
            Assert.DoesNotContain( "WILD", oWin:Text )
            oWin:Close()
            oWin:Dispose()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD OrderScopeAndFilter_WorkThroughTheWindow() AS VOID
        RunSta( { => DataWindowTests.OrderScopeFilter() } )
        RETURN

    PRIVATE STATIC METHOD OrderScopeFilter() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "QTY", "N", 5, 0 ) } AS RddFieldInfo[]
            LOCAL cFile := oData:CreateTable( "ord", aFields ) AS STRING
            oData:Append( cFile, <OBJECT>{ "C", 1 } )
            oData:Append( cFile, <OBJECT>{ "A", 2 } )
            oData:Append( cFile, <OBJECT>{ "B", 3 } )
            LOCAL oWin := DataWindow{} AS DataWindow
            Assert.True( oWin:OpenFile( cFile, "DBFCDX", TRUE, FALSE, TRUE, FALSE, TRUE, FALSE ) )
            Assert.False( oWin:HasOrder )
            // a new order becomes the active one in the combo box
            Assert.True( oWin:NewOrder( "BYNAME", "NAME", "", FALSE ) )
            Assert.True( oWin:HasOrder )
            Assert.Equal( 1, oWin:GetOrders():Count )
            // scope A..B hides C; the filter then keeps QTY > 2 (only B)
            Assert.True( oWin:SetScope( "A", "B" ) )
            Assert.Equal( "A", oWin:ScopeFrom )
            Assert.True( oWin:SetFilter( "QTY > 2" ) )
            Assert.Equal( "QTY > 2", oWin:FilterText )
            Assert.True( oWin:SetFilter( "" ) )
            Assert.Equal( "", oWin:FilterText )
            oWin:Close()
            oWin:Dispose()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

END CLASS

END NAMESPACE
