USING System
USING System.IO
USING System.Globalization
USING System.Collections.Generic
USING System.Text
USING XSharp
USING XSharp.RDD
USING XSharp.RDD.Support

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>Outcome of a table operation. No dialogs here: the caller decides what to tell the user.</summary>
PUBLIC CLASS DbfResult
    /// <summary>Records processed</summary>
    PUBLIC Done   := 0 AS INT
    /// <summary>Records skipped because another user holds the lock</summary>
    PUBLIC Locked := 0 AS INT
    /// <summary>First record number that could not be locked (0 = none)</summary>
    PUBLIC LockedRec := 0 AS LONG
    /// <summary>Exception text, empty = no error</summary>
    PUBLIC Error  := "" AS STRING
    /// <summary>The input text could not be converted to the field type (Error holds the message)</summary>
    PUBLIC Invalid := FALSE AS LOGIC
    /// <summary>Record number the operation ended on (new record, restored record ...), 0 = none</summary>
    PUBLIC Rec    := 0 AS LONG
    /// <summary>Records that raised an error (replace); LastError holds the text of the last one</summary>
    PUBLIC Errors := 0 AS INT
    PUBLIC LastError := "" AS STRING
    /// <summary>Field names that could not be taken over (paste)</summary>
    PUBLIC BadFields := List<STRING>{} AS List<STRING>
    PUBLIC PROPERTY Failed AS LOGIC GET SELF:Error:Length > 0
END CLASS

/// <summary>A DBF opened in its own work area, together with the "view" on it: active order, deleted flag handling,
/// filter and scope. Contains no user interface code, so it can be tested without a window.</summary>
PUBLIC CLASS DbfTable
    PRIVATE STATIC nAliasCounter := 0 AS INT

    // --- Work area ---
    PRIVATE oRdd AS IRdd
    PRIVATE nArea AS DWORD
    PRIVATE aName   := List<STRING>{} AS List<STRING>      // index 0 = field 1
    PRIVATE aType   := List<STRING>{} AS List<STRING>
    PRIVATE aDec    := List<INT>{}    AS List<INT>
    PRIVATE aAuto   := List<LOGIC>{}  AS List<LOGIC>       // AutoIncrement and system fields: written by the RDD itself
    PRIVATE aBinary := List<LOGIC>{}  AS List<LOGIC>       // binary fields (flag 4)
    PRIVATE aLen    := List<INT>{}    AS List<INT>         // field lengths in bytes

    PUBLIC PROPERTY Rdd       AS IRdd   GET SELF:oRdd
    PUBLIC PROPERTY Area      AS DWORD  GET SELF:nArea
    PUBLIC PROPERTY Alias     AS STRING AUTO GET PRIVATE SET
    PUBLIC PROPERTY FileName  AS STRING AUTO GET PRIVATE SET
    PUBLIC PROPERTY Driver    AS STRING AUTO GET PRIVATE SET
    PUBLIC PROPERTY Exclusive AS LOGIC  AUTO GET PRIVATE SET
    PUBLIC PROPERTY ReadOnly  AS LOGIC  AUTO GET PRIVATE SET
    PUBLIC PROPERTY IsOpen    AS LOGIC  GET SELF:oRdd != NULL
    PUBLIC PROPERTY FieldCount AS INT   GET SELF:aName:Count
    PUBLIC PROPERTY FieldName   AS List<STRING> GET SELF:aName
    PUBLIC PROPERTY FieldType   AS List<STRING> GET SELF:aType
    PUBLIC PROPERTY FieldDec    AS List<INT>    GET SELF:aDec
    PUBLIC PROPERTY FieldAuto   AS List<LOGIC>  GET SELF:aAuto
    PUBLIC PROPERTY FieldBinary AS List<LOGIC>  GET SELF:aBinary
    PUBLIC PROPERTY FieldLength AS List<INT>    GET SELF:aLen

    // --- View ---
    /// <summary>Record numbers in display order (active order, deleted flag, scope, filter)</summary>
    PUBLIC PROPERTY Recs AS List<LONG> AUTO := List<LONG>{}
    PUBLIC PROPERTY ShowDeleted AS LOGIC AUTO
    PUBLIC PROPERTY OnlyDeleted AS LOGIC AUTO
    /// <summary>Name of the active order, "" = natural order</summary>
    PUBLIC PROPERTY ActiveOrder AS STRING AUTO := ""
    /// <summary>Compiled filter (macro code block), NULL = no filter</summary>
    PUBLIC PROPERTY FilterCb   AS OBJECT AUTO
    PUBLIC PROPERTY FilterText AS STRING AUTO := ""
    PUBLIC PROPERTY ScopeFrom     AS OBJECT AUTO
    PUBLIC PROPERTY ScopeTo       AS OBJECT AUTO
    PUBLIC PROPERTY ScopeFromText AS STRING AUTO := ""
    PUBLIC PROPERTY ScopeToText   AS STRING AUTO := ""
    /// <summary>TRUE = commit and unlock after each write</summary>
    PUBLIC PROPERTY AutoCommit AS LOGIC AUTO
    /// <summary>The last LoadList stopped because the active index seems to loop</summary>
    PUBLIC PROPERTY Corrupt AS LOGIC AUTO

    // =====================================================================
    // Open / close
    // =====================================================================
    /// <summary>Open the file in a new work area. Returns FALSE and the reason in cError when it fails.</summary>
    PUBLIC METHOD Open( cFile AS STRING, cRdd AS STRING, lExcl AS LOGIC, lReadOnly AS LOGIC, cError REF STRING ) AS LOGIC
        LOCAL oResult := NULL AS OBJECT
        cError := ""
        SELF:FileName  := cFile
        SELF:Driver    := cRdd
        SELF:Exclusive := lExcl
        SELF:ReadOnly  := lReadOnly
        TRY
            nAliasCounter++
            SELF:Alias := DbfTable.MakeAlias( cFile ) + "_" + Convert.ToString( nAliasCounter )
            IF ! DbUseArea( TRUE, cRdd, cFile, SELF:Alias, ! lExcl, lReadOnly )
                cError := "The file could not be opened:" + Environment.NewLine + cFile
                RETURN FALSE
            ENDIF
            IF ! CoreDb.Info( DBI_RDD_OBJECT, REF oResult )
                DbCloseArea()
                cError := "The file could not be opened:" + Environment.NewLine + cFile
                RETURN FALSE
            ENDIF
            SELF:oRdd  := (IRdd) oResult
            SELF:nArea := (DWORD) SELF:oRdd:Area
            SELF:ReadFields()
            RETURN TRUE
        CATCH ex AS Exception
            cError := ex:Message
            RETURN FALSE
        END TRY

    /// <summary>Alias from the file name: upper case A-Z, 0-9 and "_"; never starts with a digit</summary>
    PUBLIC STATIC METHOD MakeAlias( cFile AS STRING ) AS STRING
        LOCAL cName := Path.GetFileNameWithoutExtension( cFile ):ToUpper() AS STRING
        LOCAL oText := StringBuilder{} AS StringBuilder
        FOREACH c AS CHAR IN cName
            IF ( c >= 'A' .AND. c <= 'Z' ) .OR. ( c >= '0' .AND. c <= '9' ) .OR. c == '_'
                oText:Append( c )
            ELSE
                oText:Append( '_' )
            ENDIF
        NEXT
        LOCAL cAlias := oText:ToString() AS STRING
        IF cAlias:Length == 0 .OR. Char.IsDigit( cAlias[0] )
            cAlias := "A_" + cAlias
        ENDIF
        RETURN cAlias

    PRIVATE METHOD ReadFields() AS VOID
        SELF:aName:Clear()
        SELF:aType:Clear()
        SELF:aDec:Clear()
        SELF:aAuto:Clear()
        SELF:aBinary:Clear()
        SELF:aLen:Clear()
        FOR VAR i := 1 TO SELF:oRdd:FieldCount
            SELF:aName:Add( SELF:oRdd:FieldName( i ):ToUpper() )
            SELF:aType:Add( ((STRING) SELF:oRdd:FieldInfo( i, DBS_TYPE, NULL )):ToUpper():Substring( 0, 1 ) )
            SELF:aDec:Add( (INT) (LONG) SELF:oRdd:FieldInfo( i, DBS_DEC, NULL ) )
            LOCAL nFlags := 0 AS INT
            TRY
                nFlags := Convert.ToInt32( SELF:oRdd:FieldInfo( i, DBS_FLAGS, NULL ) )
            CATCH
                nFlags := 0
            END TRY
            SELF:aAuto:Add( ( nFlags & 9 ) != 0 )          // 1 = System, 8 = AutoIncrement
            SELF:aBinary:Add( ( nFlags & 4 ) != 0 )        // 4 = Binary
            SELF:aLen:Add( (INT) (LONG) SELF:oRdd:FieldInfo( i, DBS_LEN, NULL ) )
        NEXT
        RETURN

    /// <summary>Write pending changes and close the work area</summary>
    PUBLIC METHOD Close() AS VOID
        TRY
            IF SELF:oRdd != NULL
                SELF:Sel()
                IF ! SELF:ReadOnly
                    DbCommit()
                    DbUnlock()
                ENDIF
                DbCloseArea()
                SELF:oRdd := NULL
            ENDIF
        CATCH
            NOP
        END TRY
        RETURN

    /// <summary>Make this work area the current one (before every RDD call!)</summary>
    PUBLIC METHOD Sel() AS VOID
        DbSelectArea( SELF:nArea )
        RETURN

    // =====================================================================
    // Locking / writing helpers
    // =====================================================================
    /// <summary>Record lock in shared mode (always TRUE when the file is open exclusive)</summary>
    PUBLIC METHOD TryLock( nRec AS LONG ) AS LOGIC
        IF SELF:Exclusive
            RETURN TRUE
        ENDIF
        SELF:Sel()
        RETURN DbRLock( nRec )

    /// <summary>After writing: auto commit and release the lock</summary>
    PUBLIC METHOD AfterWrite() AS VOID
        IF SELF:AutoCommit
            DbCommit()
            IF ! SELF:Exclusive
                DbUnlock()
            ENDIF
        ENDIF
        RETURN

    /// <summary>Commit and release the lock</summary>
    PUBLIC METHOD Commit() AS VOID
        IF SELF:ReadOnly
            RETURN
        ENDIF
        SELF:Sel()
        DbCommit()
        IF ! SELF:Exclusive
            DbUnlock()
        ENDIF
        RETURN

    // =====================================================================
    // Order helpers
    // =====================================================================
    PUBLIC METHOD NaturalOrder() AS VOID
        TRY
            SELF:Sel()
            OrdSetFocus( 0 )
        CATCH
            NOP
        END TRY
        RETURN

    PUBLIC METHOD RestoreOrder() AS VOID
        TRY
            IF SELF:ActiveOrder:Length > 0
                SELF:Sel()
                OrdSetFocus( SELF:ActiveOrder )
            ENDIF
        CATCH
            NOP
        END TRY
        RETURN

    // =====================================================================
    // The view: record list
    // =====================================================================
    /// <summary>Read the record numbers in the order of the active index into Recs, applying the deleted flag
    /// handling, the scope and the filter</summary>
    PUBLIC METHOD LoadList() AS VOID
        LOCAL lDel AS LOGIC
        SELF:Sel()
        // write the open record buffer and set the active order again (read the index positions afresh)
        TRY
            IF ! SELF:ReadOnly
                DbCommit()
            ENDIF
            IF SELF:ActiveOrder:Length > 0
                OrdSetFocus( SELF:ActiveOrder )
            ENDIF
        CATCH
            NOP
        END TRY
        SELF:Recs:Clear()
        SELF:Corrupt := FALSE
        DbGoTop()
        LOCAL lScope := SELF:ActiveOrder:Length > 0 .AND. ( SELF:ScopeFrom != NULL .OR. SELF:ScopeTo != NULL ) AS LOGIC
        // Protection against an endless loop with a corrupt index: more steps than records -> abort
        LOCAL nMax   := (LONG) LastRec() + 10 AS LONG
        LOCAL nSteps := 0 AS LONG
        DO WHILE ! Eof()
            nSteps++
            IF nSteps > nMax
                SELF:Corrupt := TRUE
                EXIT
            ENDIF
            LOCAL lOk := TRUE AS LOGIC
            lDel := Deleted()
            IF SELF:OnlyDeleted
                lOk := lDel
            ELSEIF ! SELF:ShowDeleted
                lOk := ! lDel
            ENDIF
            IF lOk .AND. lScope
                // no early EXIT: the index sort order (collation) can differ from the text comparison
                lOk := SELF:CompareScope() == 0
            ENDIF
            IF lOk .AND. SELF:FilterCb != NULL
                TRY
                    lOk := (LOGIC) Eval( SELF:FilterCb )
                CATCH
                    lOk := FALSE
                END TRY
            ENDIF
            IF lOk
                SELF:Recs:Add( (LONG) RecNo() )
            ENDIF
            DbSkip( 1 )
        ENDDO
        RETURN

    /// <summary>Convert the scope text to match the type of the index key</summary>
    PUBLIC METHOD ScopeValue( cText AS STRING ) AS OBJECT
        IF cText:Length == 0
            RETURN NULL
        ENDIF
        LOCAL oPattern := NULL AS OBJECT
        SELF:Sel()
        DbGoTop()
        IF ! Eof()
            oPattern := OrdKeyVal()
        ENDIF
        IF oPattern IS STRING .OR. oPattern == NULL
            RETURN cText
        ENDIF
        IF oPattern IS IDate .OR. oPattern IS DateTime
            RETURN AppSettings.ParseDate( cText )
        ENDIF
        RETURN Double.Parse( cText:Replace( "'", "" ):Replace( ",", "." ), CultureInfo.InvariantCulture )

    /// <summary>Compare the current key with the scope: -1 = before "from", 0 = inside, 1 = after "to"</summary>
    PUBLIC METHOD CompareScope() AS INT
        LOCAL oKey := NULL AS OBJECT
        TRY
            oKey := OrdKeyVal()
        CATCH
            RETURN 0
        END TRY
        IF SELF:ScopeFrom != NULL .AND. SELF:CompareValue( oKey, SELF:ScopeFrom ) < 0
            RETURN -1
        ENDIF
        IF SELF:ScopeTo != NULL .AND. SELF:CompareValue( oKey, SELF:ScopeTo ) > 0
            RETURN 1
        ENDIF
        RETURN 0

    // Character: compare only over the length of the scope value (like Clipper/VO)
    PRIVATE METHOD CompareValue( oKey AS OBJECT, oLimit AS OBJECT ) AS INT
        IF oKey == NULL
            RETURN 0
        ENDIF
        IF oLimit IS STRING
            LOCAL cLimit := (STRING) oLimit AS STRING
            LOCAL cKey    := oKey:ToString() AS STRING
            IF cKey:Length > cLimit:Length
                cKey := cKey:Substring( 0, cLimit:Length )
            ENDIF
            // case-insensitive, accented characters sorted like the Windows sort order
            RETURN Math.Sign( String.Compare( cKey, cLimit, StringComparison.CurrentCultureIgnoreCase ) )
        ENDIF
        IF oLimit IS DateTime
            LOCAL dKey AS DateTime
            IF oKey IS IDate
                LOCAL oDate := (IDate) oKey AS IDate
                IF oDate:IsEmpty
                    RETURN -1
                ENDIF
                dKey := DateTime{ oDate:Year, oDate:Month, oDate:Day }
            ELSE
                dKey := Convert.ToDateTime( oKey )
            ENDIF
            RETURN Math.Sign( DateTime.Compare( dKey, (DateTime) oLimit ) )
        ENDIF
        RETURN Math.Sign( Convert.ToDouble( oKey ):CompareTo( Convert.ToDouble( oLimit ) ) )

    // =====================================================================
    // Reading records
    // =====================================================================
    /// <summary>Memo text for a list: first 200 characters, line breaks as spaces</summary>
    PUBLIC STATIC METHOD MemoPreview( oValue AS OBJECT ) AS STRING
        IF oValue == NULL
            RETURN ""
        ENDIF
        LOCAL cMemo := oValue:ToString() AS STRING
        IF cMemo:Length > 400
            cMemo := cMemo:Substring( 0, 400 )
        ENDIF
        cMemo := cMemo:Replace( e"\r\n", " " ):Replace( e"\n", " " ):Replace( e"\r", " " ):TrimEnd( <CHAR>{ c' ', (CHAR) 0 } )
        RETURN IIF( cMemo:Length > 200, cMemo:Substring( 0, 200 ) + "...", cMemo )

    /// <summary>The values of record nRec in field order. lMemos = FALSE: memo fields come back as a short preview
    /// (the FPT is not read for display). The record is read again (up to 3 times) when another read moved the
    /// record pointer in between.</summary>
    PUBLIC METHOD ReadRow( nRec AS LONG, lMemos AS LOGIC, lDeleted REF LOGIC ) AS List<OBJECT>
        LOCAL aValues := List<OBJECT>{} AS List<OBJECT>
        lDeleted := FALSE
        FOR VAR nAttempt := 1 TO 3
            SELF:Sel()
            DbGoto( nRec )
            aValues:Clear()
            FOR VAR i := 1 TO SELF:aName:Count
                LOCAL oVal := NULL AS OBJECT
                TRY
                    IF ! lMemos .AND. SELF:aType[i - 1] == "M"
                        oVal := DbfTable.MemoPreview( SELF:oRdd:GetValue( i ) )
                    ELSE
                        oVal := SELF:oRdd:GetValue( i )
                    ENDIF
                CATCH
                    oVal := "<Error>"
                END TRY
                aValues:Add( oVal )
            NEXT
            lDeleted := Deleted()
            IF (LONG) RecNo() == nRec
                EXIT
            ENDIF
        NEXT
        RETURN aValues

    /// <summary>First 12 bytes of the DBF header (read from disk), NULL when the file cannot be read</summary>
    PUBLIC METHOD ReadHeader() AS BYTE[]
        TRY
            LOCAL aHeader := BYTE[]{ 12 } AS BYTE[]
            LOCAL fs := FileStream{ SELF:FileName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
            TRY
                fs:Read( aHeader, 0, 12 )
            FINALLY
                fs:Close()
            END TRY
            RETURN aHeader
        CATCH
            RETURN NULL
        END TRY

    /// <summary>Offset of field nIdx (0-based) inside the record; byte 0 is the deleted flag</summary>
    PUBLIC METHOD FieldOffset( nIdx AS INT ) AS INT
        LOCAL nOffset := 1 AS INT
        FOR VAR i := 0 TO nIdx - 1
            nOffset += SELF:aLen[i]
        NEXT
        RETURN nOffset

    /// <summary>Raw bytes of a whole record (with deleted flag), read directly from the DBF file.
    /// IOException when this process holds the file exclusively.</summary>
    PUBLIC METHOD ReadRecordBytes( nRec AS LONG ) AS BYTE[]
        LOCAL aHeader := BYTE[]{ 12 } AS BYTE[]
        LOCAL aRecord := NULL AS BYTE[]
        LOCAL fs := FileStream{ SELF:FileName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
        TRY
            fs:Read( aHeader, 0, 12 )
            LOCAL nHdrLen := BitConverter.ToUInt16( aHeader, 8 ) AS INT
            LOCAL nLen    := BitConverter.ToUInt16( aHeader, 10 ) AS INT
            aRecord := BYTE[]{ nLen }
            fs:Seek( (INT64) nHdrLen + (INT64) ( nRec - 1 ) * nLen, SeekOrigin.Begin )
            fs:Read( aRecord, 0, nLen )
        FINALLY
            fs:Close()
        END TRY
        RETURN aRecord

    /// <summary>Raw bytes of a field (0-based index), read directly from the DBF record (IOException when this
    /// process holds the file exclusively)</summary>
    PUBLIC METHOD ReadFieldBytes( nRec AS LONG, nIdx AS INT ) AS BYTE[]
        LOCAL nOffset := SELF:FieldOffset( nIdx ) AS INT
        LOCAL nLen    := SELF:aLen[nIdx] AS INT
        LOCAL aData   := BYTE[]{ nLen } AS BYTE[]
        LOCAL fs := FileStream{ SELF:FileName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
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

    /// <summary>Raw content of a memo block, read directly from the FPT file (FoxPro / VFP memo files).
    /// Returns NULL when it cannot be read this way (no FPT file, DBT memo, block outside the file ...).</summary>
    PUBLIC METHOD ReadMemoBytes( nRec AS LONG, nIdx AS INT ) AS BYTE[]
        LOCAL cFpt := Path.ChangeExtension( SELF:FileName, ".fpt" ) AS STRING
        IF ! File.Exists( cFpt )
            RETURN NULL
        ENDIF
        LOCAL nOffset  := SELF:FieldOffset( nIdx ) AS INT
        LOCAL nPtrLen  := SELF:aLen[nIdx] AS INT
        LOCAL nBlockNo := 0 AS INT64
        LOCAL fs := FileStream{ SELF:FileName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite } AS FileStream
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

    // =====================================================================
    // Replace
    // =====================================================================
    /// <summary>Compile a macro expression in the context of this work area</summary>
    PUBLIC METHOD Compile( cExpression AS STRING ) AS OBJECT
        SELF:Sel()
        RETURN MCompile( cExpression )

    /// <summary>Assign a value to field nIdx (0-based) in the given records. The value is either oFixed or the
    /// result of the compiled expression oCb; oFor (optional) decides per record. Done = records changed,
    /// Locked = skipped (locked), Errors / LastError = records that raised an error.</summary>
    PUBLIC METHOD ReplaceField( nIdx AS INT, oCb AS OBJECT, oFixed AS OBJECT, oFor AS OBJECT, aTarget AS List<LONG> ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
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
                IF ! SELF:Exclusive .AND. ! DbRLock( nRec )
                    oResult:Locked++
                    LOOP
                ENDIF
                TRY
                    LOCAL oNew := IIF( oCb != NULL, (OBJECT) Eval( oCb ), oFixed ) AS OBJECT
                    FieldPut( nIdx + 1, oNew )
                    oResult:Done++
                CATCH ex AS Exception
                    oResult:Errors++
                    oResult:LastError := ex:Message
                END TRY
            NEXT
            DbCommit()
            IF ! SELF:Exclusive
                DbUnlock()
            ENDIF
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    // =====================================================================
    // JSON export
    // =====================================================================
    /// <summary>Value for the JSON writer: RDD wrapper types become plain .NET values, an empty date becomes null</summary>
    PUBLIC STATIC METHOD JsonValue( oValue AS OBJECT ) AS OBJECT
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
    /// ("Deleted", "RecNo", then the fields). lAll = all records of the file in natural order, otherwise the
    /// records of the current view (order, filter, scope). Returns the number of records written.</summary>
    PUBLIC METHOD WriteJson( cFileName AS STRING, lAll AS LOGIC ) AS INT
        LOCAL nCount  := 0 AS INT
        LOCAL aExport := List<LONG>{} AS List<LONG>
        // a field may be called DELETED or RECNO : keep the meta keys apart
        LOCAL cKeyDeleted := IIF( SELF:aName:Contains( "DELETED" ), "_Deleted", "Deleted" ) AS STRING
        LOCAL cKeyRecno   := IIF( SELF:aName:Contains( "RECNO" ), "_RecNo", "RecNo" ) AS STRING
        SELF:Sel()
        IF lAll
            FOR VAR nRec := 1 TO (LONG) LastRec()
                aExport:Add( nRec )
            NEXT
        ELSE
            aExport:AddRange( SELF:Recs )
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
                FOR VAR f := 1 TO SELF:aName:Count
                    LOCAL oValue := NULL AS OBJECT
                    TRY
                        oValue := SELF:oRdd:GetValue( f )
                    CATCH
                        oValue := NULL
                    END TRY
                    jw:WritePropertyName( SELF:aName[f - 1] )
                    jw:WriteValue( DbfTable.JsonValue( oValue ) )
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

    // =====================================================================
    // Delete / recall
    // =====================================================================
    /// <summary>Set (lDelete) or clear the deleted flag of one record.</summary>
    PUBLIC METHOD SetDeleted( nRec AS LONG, lDelete AS LOGIC ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            DbGoto( nRec )
            IF ! SELF:TryLock( nRec )
                oResult:Locked    := 1
                oResult:LockedRec := nRec
                RETURN oResult
            ENDIF
            IF lDelete
                DbDelete()
            ELSE
                DbRecall()
            ENDIF
            SELF:AfterWrite()
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Recall every deleted record of the file (independent of the view)</summary>
    PUBLIC METHOD RecallAll() AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            LOCAL nMax := (LONG) LastRec() + 10 AS LONG
            SELF:NaturalOrder()
            DbGoTop()
            DO WHILE ! Eof() .AND. nMax > 0
                nMax--
                IF Deleted()
                    IF SELF:Exclusive .OR. DbRLock( RecNo() )
                        DbRecall()
                        oResult:Done++
                    ELSE
                        oResult:Locked++
                    ENDIF
                ENDIF
                DbSkip( 1 )
            ENDDO
            SELF:RestoreOrder()
            DbCommit()
            IF ! SELF:Exclusive
                DbUnlock()
            ENDIF
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Delete all records that are currently in the view (Recs). Records that are already deleted are skipped.</summary>
    PUBLIC METHOD DeleteView() AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        // snapshot: the list changes while records disappear from the view
        LOCAL aTodo := List<LONG>{ SELF:Recs } AS List<LONG>
        TRY
            SELF:Sel()
            FOREACH nR AS LONG IN aTodo
                DbGoto( nR )
                IF Deleted()
                    LOOP
                ENDIF
                IF SELF:Exclusive .OR. DbRLock( nR )
                    DbDelete()
                    oResult:Done++
                ELSE
                    oResult:Locked++
                ENDIF
            NEXT
            DbCommit()
            IF ! SELF:Exclusive
                DbUnlock()
            ENDIF
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    // =====================================================================
    // Writing
    // =====================================================================
    // --- Undo: the last field change ---
    PUBLIC PROPERTY UndoRec   AS LONG   AUTO := 0
    PUBLIC PROPERTY UndoField AS INT    AUTO := 0
    PUBLIC PROPERTY UndoValue AS OBJECT AUTO
    PUBLIC PROPERTY CanUndo   AS LOGIC  GET SELF:UndoRec != 0 .AND. ! SELF:ReadOnly

    /// <summary>Character field with the Binary flag (C:B): shown in the hex viewer, never edited as text</summary>
    PUBLIC METHOD IsBinaryChar( nIdx AS INT ) AS LOGIC
        RETURN SELF:aType[nIdx] == "C" .AND. SELF:aBinary[nIdx]

    /// <summary>The field can be edited as text (not read only, not memo, not auto / system, not binary)</summary>
    PUBLIC METHOD IsWritable( nIdx AS INT ) AS LOGIC
        RETURN ! SELF:ReadOnly .AND. SELF:aType[nIdx] != "M" .AND. ! SELF:aAuto[nIdx] .AND. ! SELF:IsBinaryChar( nIdx )

    /// <summary>Convert text from an input control to the field type (throws on invalid input)</summary>
    PUBLIC STATIC METHOD ConvertText( cText AS STRING, cType AS STRING ) AS OBJECT
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

    /// <summary>Write text to field nIdx (0-based) of record nRec. Done = 1 on success; nothing happens (Done = 0,
    /// no error) when the field is not writable.</summary>
    PUBLIC METHOD WriteField( nRec AS LONG, nIdx AS INT, cText AS STRING ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        LOCAL nField  := nIdx + 1 AS INT
        LOCAL oNew    := NULL AS OBJECT
        IF ! SELF:IsWritable( nIdx )
            RETURN oResult
        ENDIF
        TRY
            oNew := DbfTable.ConvertText( cText, SELF:aType[nIdx] )
        CATCH
            oResult:Invalid := TRUE
            oResult:Error   := "Invalid input for field " + SELF:aName[nIdx] + ": " + cText
            RETURN oResult
        END TRY
        TRY
            SELF:Sel()
            DbGoto( nRec )
            IF SELF:TryLock( nRec )
                SELF:UndoRec   := nRec
                SELF:UndoField := nField
                SELF:UndoValue := SELF:oRdd:GetValue( nField )
                FieldPut( nField, oNew )
                SELF:AfterWrite()
                oResult:Done := 1
            ELSE
                oResult:Locked    := 1
                oResult:LockedRec := nRec
            ENDIF
        CATCH ex AS Exception
            oResult:Error := "Error while writing: " + ex:Message
        END TRY
        RETURN oResult

    /// <summary>Write a memo value. cOldFull = what the field held, for undo.</summary>
    PUBLIC METHOD WriteMemo( nRec AS LONG, nIdx AS INT, cNew AS STRING, cOldFull AS STRING ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            DbGoto( nRec )
            IF SELF:TryLock( nRec )
                SELF:UndoRec   := nRec
                SELF:UndoField := nIdx + 1
                SELF:UndoValue := cOldFull
                FieldPut( nIdx + 1, cNew )
                SELF:AfterWrite()
                oResult:Done := 1
            ELSE
                oResult:Locked    := 1
                oResult:LockedRec := nRec
            ENDIF
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Undo the last field change; Rec = the restored record</summary>
    PUBLIC METHOD Undo() AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        IF ! SELF:CanUndo
            RETURN oResult
        ENDIF
        TRY
            SELF:Sel()
            DbGoto( SELF:UndoRec )
            IF SELF:TryLock( SELF:UndoRec )
                FieldPut( SELF:UndoField, SELF:UndoValue )
                SELF:AfterWrite()
                oResult:Done := 1
                oResult:Rec  := SELF:UndoRec
                SELF:UndoRec := 0
            ELSE
                oResult:Locked    := 1
                oResult:LockedRec := SELF:UndoRec
            ENDIF
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Append an empty record; Rec = its record number</summary>
    PUBLIC METHOD AppendRecord() AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            DbAppend()
            oResult:Rec := (LONG) RecNo()
            SELF:AfterWrite()
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    // =====================================================================
    // Records as clipboard values
    // =====================================================================
    /// <summary>The values of a record by field name (what DBClipboard holds)</summary>
    PUBLIC METHOD ReadRecord( nRec AS LONG ) AS Dictionary<STRING, OBJECT>
        LOCAL oRecord := Dictionary<STRING, OBJECT>{} AS Dictionary<STRING, OBJECT>
        SELF:Sel()
        DbGoto( nRec )
        FOR VAR i := 1 TO SELF:aName:Count
            TRY
                oRecord[SELF:aName[i - 1]] := SELF:oRdd:GetValue( i )
            CATCH
                NOP
            END TRY
        NEXT
        RETURN oRecord

    /// <summary>Write the values into the CURRENT record (same field names); auto fields are skipped, fields that
    /// refuse the value are listed in aError</summary>
    PUBLIC METHOD WriteRecord( oRecord AS Dictionary<STRING, OBJECT>, aError AS List<STRING> ) AS VOID
        FOR VAR i := 1 TO SELF:aName:Count
            LOCAL cName := SELF:aName[i - 1] AS STRING
            IF oRecord:ContainsKey( cName ) .AND. ! SELF:aAuto[i - 1]
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

    /// <summary>Overwrite record nRec with the values</summary>
    PUBLIC METHOD PasteInto( nRec AS LONG, oRecord AS Dictionary<STRING, OBJECT> ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            DbGoto( nRec )
            IF SELF:TryLock( nRec )
                SELF:WriteRecord( oRecord, oResult:BadFields )
                SELF:AfterWrite()
                oResult:Done := 1
                oResult:Rec  := nRec
            ELSE
                oResult:Locked    := 1
                oResult:LockedRec := nRec
            ENDIF
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Append one new record per entry; Rec = the last one</summary>
    PUBLIC METHOD PasteAppend( aRecords AS List<Dictionary<STRING, OBJECT>> ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            FOREACH oRecord AS Dictionary<STRING, OBJECT> IN aRecords
                DbAppend()
                SELF:WriteRecord( oRecord, oResult:BadFields )
                oResult:Rec := (LONG) RecNo()
                oResult:Done++
            NEXT
            SELF:AfterWrite()
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    // =====================================================================
    // Filter and scope
    // =====================================================================
    /// <summary>Set the filter expression (empty = filter off). Needs the X# macro compiler. Does not reload the list.
    /// Invalid = the expression is not usable (Error holds the message), the previous filter stays.</summary>
    PUBLIC METHOD SetFilter( cExpression AS STRING ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        cExpression := cExpression:Trim()
        IF cExpression:Length == 0
            SELF:FilterCb   := NULL
            SELF:FilterText := ""
            oResult:Done := 1
            RETURN oResult
        ENDIF
        TRY
            SELF:Sel()
            LOCAL oCb := MCompile( cExpression ) AS OBJECT
            DbGoTop()
            LOCAL oTest := Eval( oCb ) AS OBJECT       // Trial run: must return LOGIC
            IF ! ( oTest IS LOGIC )
                oResult:Invalid := TRUE
                oResult:Error   := "The expression does not return a logical value (.T./.F.)."
                RETURN oResult
            ENDIF
            SELF:FilterCb   := oCb
            SELF:FilterText := cExpression
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Invalid := TRUE
            oResult:Error   := "Invalid filter expression:" + Environment.NewLine + ex:Message
        END TRY
        RETURN oResult

    /// <summary>Set the scope (from/to) for the active order; empty values = open. Does not reload the list.</summary>
    PUBLIC METHOD SetScope( cFrom AS STRING, cTo AS STRING ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            LOCAL oFrom := SELF:ScopeValue( cFrom ) AS OBJECT
            LOCAL oTo   := SELF:ScopeValue( cTo ) AS OBJECT
            SELF:ScopeFrom     := oFrom
            SELF:ScopeTo       := oTo
            SELF:ScopeFromText := cFrom
            SELF:ScopeToText   := cTo
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Invalid := TRUE
            oResult:Error   := "Invalid scope value: " + ex:Message
        END TRY
        RETURN oResult

    /// <summary>The scope only applies to the order it was set for</summary>
    PUBLIC METHOD ClearScope() AS VOID
        SELF:ScopeFrom     := NULL
        SELF:ScopeTo       := NULL
        SELF:ScopeFromText := ""
        SELF:ScopeToText   := ""
        RETURN

    // =====================================================================
    // Orders (indexes)
    // =====================================================================
    PUBLIC PROPERTY IsNtx AS LOGIC GET SELF:Driver:ToUpper():Contains( "NTX" )
    /// <summary>Structure changes (index creation, reindex, zap) need exclusive, writable access</summary>
    PUBLIC PROPERTY CanRestructure AS LOGIC GET ! SELF:ReadOnly .AND. SELF:Exclusive

    /// <summary>Names of all orders of all open index files</summary>
    PUBLIC METHOD OrderNames() AS List<STRING>
        LOCAL aNames := List<STRING>{} AS List<STRING>
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
            aNames:Add( cName )
        NEXT
        RETURN aNames

    /// <summary>Name of the order that is active in the work area ("" = natural order)</summary>
    PUBLIC METHOD CurrentOrderName() AS STRING
        TRY
            SELF:Sel()
            RETURN ((STRING) OrdSetFocus()):Trim()
        CATCH
            RETURN ""
        END TRY

    /// <summary>Key expression of the active order (upper case), "" when there is none</summary>
    PUBLIC METHOD ActiveOrderKey() AS STRING
        TRY
            SELF:Sel()
            RETURN ((STRING) OrdKey()):ToUpper()
        CATCH
            RETURN ""
        END TRY

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

    /// <summary>Make an order active in the work area ("" = natural order)</summary>
    PUBLIC METHOD SetFocusOrder( cName AS STRING ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            IF cName:Length == 0
                OrdSetFocus( 0 )
            ELSE
                OrdSetFocus( cName )
            ENDIF
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Soft seek in the active order; Rec = the record found (the last record when beyond the end)</summary>
    PUBLIC METHOD Seek( cValue AS STRING ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            DbSeek( cValue, TRUE )
            IF Eof()
                DbGoBottom()
            ENDIF
            oResult:Rec  := (LONG) RecNo()
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Open an additional index file</summary>
    PUBLIC METHOD AddIndexFile( cIndexFile AS STRING ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            OrdListAdd( cIndexFile )
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Close all index files</summary>
    PUBLIC METHOD ClearIndexFiles() AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            OrdListClear()
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Create a new order (CDX: in the production CDX, NTX: own file)</summary>
    PUBLIC METHOD CreateOrder( cName AS STRING, cExpression AS STRING, cCondition AS STRING, lUnique AS LOGIC ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            LOCAL cBag AS STRING
            IF SELF:IsNtx
                cBag := Path.Combine( Path.GetDirectoryName( SELF:FileName ), cName + ".ntx" )
            ELSE
                cBag := Path.ChangeExtension( SELF:FileName, ".cdx" )
            ENDIF
            LOCAL cError := StructureRebuild.CreateOrder( cBag, cName, cExpression, cCondition, lUnique ) AS STRING
            IF cError:Length > 0
                oResult:Error := cError
            ELSE
                oResult:Done := 1
            ENDIF
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    PUBLIC METHOD DestroyOrder( cName AS STRING, cBag AS STRING ) AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            OrdSetFocus( 0 )
            OrdDestroy( cName, cBag )
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    PUBLIC METHOD ReIndex() AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            OrdListRebuild()
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Rebuild the production CDX: remove its orders, create all orders of the list.
    /// aList: name, expression, condition, unique ("1"/"0"). Returns "" (OK) or the error message per order.</summary>
    PUBLIC METHOD RebuildOrders( aList AS List<STRING[]> ) AS List<STRING>
        LOCAL aStatus := List<STRING>{} AS List<STRING>
        LOCAL cCdx    := Path.ChangeExtension( SELF:FileName, ".cdx" ) AS STRING
        LOCAL cBase   := Path.GetFileNameWithoutExtension( SELF:FileName ) AS STRING
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
        RETURN aStatus

    // =====================================================================
    // Zap
    // =====================================================================
    /// <summary>Number of records in the file (deleted ones included)</summary>
    PUBLIC METHOD RecordCount() AS LONG
        SELF:Sel()
        RETURN (LONG) LastRec()

    /// <summary>Remove all records physically</summary>
    PUBLIC METHOD Zap() AS DbfResult
        LOCAL oResult := DbfResult{} AS DbfResult
        TRY
            SELF:Sel()
            DbZap()
            oResult:Done := 1
        CATCH ex AS Exception
            oResult:Error := ex:Message
        END TRY
        RETURN oResult

    /// <summary>Number of deleted records in the file (independent of the view)</summary>
    PUBLIC METHOD CountDeleted() AS INT
        LOCAL nDelCount := 0 AS INT
        SELF:Sel()
        LOCAL nMax := (LONG) LastRec() + 10 AS LONG
        SELF:NaturalOrder()
        DbGoTop()
        DO WHILE ! Eof() .AND. nMax > 0
            nMax--
            IF Deleted()
                nDelCount++
            ENDIF
            DbSkip( 1 )
        ENDDO
        SELF:RestoreOrder()
        RETURN nDelCount

END CLASS

END NAMESPACE
