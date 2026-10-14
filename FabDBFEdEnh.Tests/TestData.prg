USING System
USING System.IO
USING System.Collections.Generic
USING XSharp
USING XSharp.RDD
USING XSharp.RDD.Support

// The XSharp RDD layer keeps process-wide state (order conditions, defaults ...): never run tests in parallel
[assembly: Xunit.CollectionBehavior( DisableTestParallelization := TRUE )]

BEGIN NAMESPACE FabDBFEdEnh.Tests

/// <summary>Creates throw-away tables in a temp folder; the folder is deleted again by Dispose</summary>
PUBLIC CLASS TestData IMPLEMENTS IDisposable
    PUBLIC Folder AS STRING

    PUBLIC CONSTRUCTOR()
        SELF:Folder := Path.Combine( Path.GetTempPath(), "FabDBFEdEnhTests_" + Guid.NewGuid():ToString( "N" ) )
        Directory.CreateDirectory( SELF:Folder )
        RETURN

    PUBLIC METHOD Dispose() AS VOID
        TRY
            Directory.Delete( SELF:Folder, TRUE )
        CATCH
            NOP
        END TRY
        RETURN

    /// <summary>Create a DBF (driver DBFCDX) with the given fields and leave it closed</summary>
    PUBLIC METHOD CreateTable( cName AS STRING, aFields AS RddFieldInfo[] ) AS STRING
        LOCAL cFile := Path.Combine( SELF:Folder, cName + ".dbf" ) AS STRING
        IF ! CoreDb.Create( cFile, aFields, "DBFCDX", TRUE, "TESTCREATE", "", FALSE, FALSE )
            THROW Exception{ "CoreDb.Create failed for " + cFile }
        ENDIF
        DbCloseArea()
        RETURN cFile

    PUBLIC STATIC METHOD Field( cName AS STRING, cType AS STRING, nLen AS INT, nDec AS INT ) AS RddFieldInfo
        RETURN RddFieldInfo{ cName, cType, nLen, nDec }

    /// <summary>Append one record; values in field order (1-based array, AZ off)</summary>
    PUBLIC METHOD Append( cFile AS STRING, aValues AS OBJECT[] ) AS VOID
        IF ! DbUseArea( TRUE, "DBFCDX", cFile, "TESTAPPEND", FALSE, FALSE )
            THROW Exception{ "Cannot open " + cFile }
        ENDIF
        DbAppend()
        FOR VAR i := 1 TO aValues:Length
            FieldPut( (DWORD) i, aValues[i] )
        NEXT
        DbCommit()
        DbCloseArea()
        RETURN
END CLASS

END NAMESPACE
