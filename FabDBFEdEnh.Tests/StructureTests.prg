USING System
USING System.Collections.Generic
USING XSharp
USING XSharp.RDD.Support
USING Xunit

BEGIN NAMESPACE FabDBFEdEnh.Tests

PUBLIC CLASS StructureTests

    [Fact];
    PUBLIC METHOD CreateTable_AppendsAndCounts() AS VOID
        VAR oData := TestData{}
        TRY
            LOCAL aFields := <RddFieldInfo>{ TestData.Field( "NAME", "C", 10, 0 ), TestData.Field( "QTY", "N", 5, 0 ) } AS RddFieldInfo[]
            LOCAL cFile := oData:CreateTable( "t1", aFields ) AS STRING
            oData:Append( cFile, <OBJECT>{ "ONE", 1 } )
            oData:Append( cFile, <OBJECT>{ "TWO", 2 } )
            Assert.True( DbUseArea( TRUE, "DBFCDX", cFile, "TESTCOUNT", FALSE, TRUE ) )
            Assert.Equal( 2, (INT) RecCount() )
            DbCloseArea()
        FINALLY
            oData:Dispose()
        END TRY
        RETURN

    [Fact];
    PUBLIC METHOD MapExpression_RenamesFieldsOutsideQuotes() AS VOID
        LOCAL aFields := List<FieldDef>{} AS List<FieldDef>
        aFields:Add( FieldDef{ "NEWNAME", "C", 10, 0, "OLDNAME" } )
        Assert.Equal( "UPPER(NEWNAME)+'OLDNAME'", StructureRebuild.MapExpression( "UPPER(OLDNAME)+'OLDNAME'", aFields ) )
        RETURN

END CLASS

END NAMESPACE
