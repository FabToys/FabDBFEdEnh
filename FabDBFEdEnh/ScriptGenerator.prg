USING System
USING System.IO
USING System.Text
USING System.Drawing
USING System.Globalization
USING System.Collections.Generic
USING System.Windows.Forms
USING XSharp
USING XSharp.RDD

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>What Generate Create PRG should write</summary>
PUBLIC CLASS ScriptOptions
    /// <summary>X# with DbCreate() and an array (VO / Vulcan dialects)</summary>
    PUBLIC CONST StyleDbCreate := 0 AS INT
    /// <summary>X# with RddFieldInfo and CoreDb.Create (Core dialect)</summary>
    PUBLIC CONST StyleRddFieldInfo := 1 AS INT
    /// <summary>Visual FoxPro: CREATE TABLE, INDEX ON, INSERT INTO</summary>
    PUBLIC CONST StyleVisualFoxPro := 2 AS INT

    PUBLIC Style    := 0 AS INT
    /// <summary>Also write the index definitions</summary>
    PUBLIC Indexes  := TRUE AS LOGIC
    /// <summary>Also write the existing records (not deleted ones)</summary>
    PUBLIC Records  := FALSE AS LOGIC
    /// <summary>Records: only those of the current view (order, filter, scope) instead of the whole file</summary>
    PUBLIC ViewOnly := FALSE AS LOGIC
END CLASS


/// <summary>Writes the structure (and optionally indexes and records) of a table as source code, and the plain
/// text description of a table. No user interface here, so everything can be tested.</summary>
PUBLIC STATIC CLASS ScriptGenerator

    // =====================================================================
    // Literals
    // =====================================================================
    /// <summary>X# string literal. Text with quotes or control characters becomes an e"..." string</summary>
    PUBLIC STATIC METHOD XsString( cText AS STRING ) AS STRING
        LOCAL cQuote := (CHAR) 34 AS CHAR
        LOCAL cSlash := (CHAR) 92 AS CHAR
        LOCAL lPlain := TRUE AS LOGIC
        FOREACH c AS CHAR IN cText
            IF c == cQuote .OR. c < (CHAR) 32
                lPlain := FALSE
                EXIT
            ENDIF
        NEXT
        IF lPlain
            RETURN cQuote:ToString() + cText + cQuote:ToString()
        ENDIF
        LOCAL oText := StringBuilder{} AS StringBuilder
        oText:Append( "e" ):Append( cQuote )
        FOREACH c AS CHAR IN cText
            IF c == cQuote
                oText:Append( cSlash ):Append( cQuote )
            ELSEIF c == cSlash
                oText:Append( cSlash ):Append( cSlash )
            ELSEIF c == (CHAR) 13
                oText:Append( cSlash ):Append( "r" )
            ELSEIF c == (CHAR) 10
                oText:Append( cSlash ):Append( "n" )
            ELSEIF c == (CHAR) 9
                oText:Append( cSlash ):Append( "t" )
            ELSEIF c < (CHAR) 32
                oText:Append( cSlash ):Append( "u" ):Append( ( (INT) c ):ToString( "X4" ) )
            ELSE
                oText:Append( c )
            ENDIF
        NEXT
        oText:Append( cQuote )
        RETURN oText:ToString()

    /// <summary>Visual FoxPro string expression: '...', "...", or pieces joined with + CHR(n)</summary>
    PUBLIC STATIC METHOD VfpString( cText AS STRING ) AS STRING
        IF cText:Length == 0
            RETURN "''"
        ENDIF
        // line breaks and quotes cannot be written inside a literal: join literals with CHR()
        LOCAL aParts := List<STRING>{} AS List<STRING>
        LOCAL oPiece := StringBuilder{} AS StringBuilder
        FOREACH c AS CHAR IN cText
            IF c == (CHAR) 13 .OR. c == (CHAR) 10 .OR. c == (CHAR) 39 .OR. c < (CHAR) 32
                IF oPiece:Length > 0
                    aParts:Add( "'" + oPiece:ToString() + "'" )
                    oPiece:Clear()
                ENDIF
                aParts:Add( "CHR(" + ( (INT) c ):ToString() + ")" )
            ELSE
                oPiece:Append( c )
            ENDIF
        NEXT
        IF oPiece:Length > 0
            aParts:Add( "'" + oPiece:ToString() + "'" )
        ENDIF
        RETURN String.Join( " + ", aParts:ToArray() )

    PRIVATE STATIC METHOD Number( oValue AS OBJECT ) AS STRING
        // "R" (round trip) is valid for floating point only; integers and decimals use the plain invariant text
        IF oValue IS DOUBLE .OR. oValue IS REAL4
            RETURN ((IFormattable) oValue):ToString( "R", CultureInfo.InvariantCulture )
        ENDIF
        RETURN Convert.ToString( oValue, CultureInfo.InvariantCulture )

    /// <summary>The value as RDD delivers it, with wrappers removed. NULL = nothing to write (empty date, binary)</summary>
    PRIVATE STATIC METHOD Normalize( oValue AS OBJECT, cType AS STRING ) AS OBJECT
        LOCAL oPlain := DbfTable.JsonValue( oValue ) AS OBJECT
        IF oPlain IS BYTE[]
            RETURN NULL                                     // binary content is not exported
        ENDIF
        IF oPlain IS DateTime .AND. cType == "D"
            RETURN ((DateTime) oPlain):Date
        ENDIF
        RETURN oPlain

    /// <summary>Value as X# source. lVo: VO / Vulcan dialect (SToD, NIL); otherwise Core dialect (DateTime{})</summary>
    PUBLIC STATIC METHOD XsValue( oValue AS OBJECT, cType AS STRING, lVo AS LOGIC ) AS STRING
        LOCAL oV := ScriptGenerator.Normalize( oValue, cType ) AS OBJECT
        IF oV == NULL
            RETURN IIF( lVo, "NIL", "NULL" )
        ENDIF
        IF oV IS DateTime
            LOCAL d := (DateTime) oV AS DateTime
            IF cType == "D"
                IF lVo
                    RETURN "SToD( " + ScriptGenerator.XsString( d:ToString( "yyyyMMdd", CultureInfo.InvariantCulture ) ) + " )"
                ENDIF
                RETURN String.Format( CultureInfo.InvariantCulture, "DateTime{{ {0}, {1}, {2} }}", d:Year, d:Month, d:Day )
            ENDIF
            RETURN String.Format( CultureInfo.InvariantCulture, "DateTime{{ {0}, {1}, {2}, {3}, {4}, {5} }}", ;
                d:Year, d:Month, d:Day, d:Hour, d:Minute, d:Second )
        ENDIF
        IF oV IS LOGIC
            RETURN IIF( (LOGIC) oV, "TRUE", "FALSE" )
        ENDIF
        IF oV IS STRING
            IF cType == "C"
                RETURN ScriptGenerator.XsString( ((STRING) oV):TrimEnd( (CHAR) 32 ) )
            ENDIF
            RETURN ScriptGenerator.XsString( (STRING) oV )
        ENDIF
        IF oV IS IConvertible .AND. ! ( oV IS Char )
            RETURN ScriptGenerator.Number( oV )
        ENDIF
        RETURN ScriptGenerator.XsString( oV:ToString() )

    /// <summary>Value as Visual FoxPro source</summary>
    PUBLIC STATIC METHOD VfpValue( oValue AS OBJECT, cType AS STRING ) AS STRING
        LOCAL oV := ScriptGenerator.Normalize( oValue, cType ) AS OBJECT
        IF oV == NULL
            IF cType == "D" .OR. cType == "T"
                RETURN "{}"
            ELSEIF cType == "N" .OR. cType == "F" .OR. cType == "I" .OR. cType == "B" .OR. cType == "Y"
                RETURN "0"
            ELSEIF cType == "L"
                RETURN ".F."
            ENDIF
            RETURN "''"
        ENDIF
        IF oV IS DateTime
            LOCAL d := (DateTime) oV AS DateTime
            IF cType == "D"
                RETURN "{^" + d:ToString( "yyyy-MM-dd", CultureInfo.InvariantCulture ) + "}"
            ENDIF
            RETURN "{^" + d:ToString( "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture ) + "}"
        ENDIF
        IF oV IS LOGIC
            RETURN IIF( (LOGIC) oV, ".T.", ".F." )
        ENDIF
        IF oV IS STRING
            IF cType == "C"
                RETURN ScriptGenerator.VfpString( ((STRING) oV):TrimEnd( (CHAR) 32 ) )
            ENDIF
            RETURN ScriptGenerator.VfpString( (STRING) oV )
        ENDIF
        IF oV IS IConvertible .AND. ! ( oV IS Char )
            RETURN ScriptGenerator.Number( oV )
        ENDIF
        RETURN ScriptGenerator.VfpString( oV:ToString() )

    /// <summary>Field type for CREATE TABLE ("" = no equivalent)</summary>
    PUBLIC STATIC METHOD VfpType( f AS FieldDef ) AS STRING
        LOCAL cExtra := f:Extra AS STRING
        LOCAL lBinary := cExtra:Contains( "B" ) AS LOGIC
        LOCAL lAuto   := cExtra:Contains( "+" ) AS LOGIC
        LOCAL lNull   := cExtra:Contains( "N" ) AS LOGIC
        LOCAL cType := "" AS STRING
        SWITCH f:FieldType
        CASE "C"
            cType := "C(" + Convert.ToString( f:Length ) + ")" + IIF( lBinary, " NOCPTRANS", "" )
        CASE "N"
            cType := "N(" + Convert.ToString( f:Length ) + "," + Convert.ToString( f:Dec ) + ")"
        CASE "F"
            cType := "F(" + Convert.ToString( f:Length ) + "," + Convert.ToString( f:Dec ) + ")"
        CASE "D"
            cType := "D"
        CASE "T"
            cType := "T"
        CASE "L"
            cType := "L"
        CASE "M"
            cType := "M" + IIF( lBinary, " NOCPTRANS", "" )
        CASE "G"
            cType := "G"
        CASE "I"
            cType := "I" + IIF( lAuto, " AUTOINC", "" )
        CASE "B"
            cType := "B(" + Convert.ToString( f:Dec ) + ")"
        CASE "Y"
            cType := "Y"
        OTHERWISE
            RETURN ""
        END SWITCH
        RETURN cType + IIF( lNull, " NULL", "" )

    /// <summary>Name for the generated function: Create + the file name</summary>
    PUBLIC STATIC METHOD FunctionName( cFile AS STRING ) AS STRING
        LOCAL cAlias := DbfTable.MakeAlias( cFile ) AS STRING
        IF cAlias:StartsWith( "A_" ) .AND. cAlias:Length > 2 .AND. Char.IsDigit( cAlias[2] )
            cAlias := cAlias:Substring( 2 )
        ENDIF
        RETURN "Create" + cAlias:Substring( 0, 1 ) + cAlias:Substring( 1 ):ToLower()

    // =====================================================================
    // Generate Create PRG
    // =====================================================================
    /// <summary>Write the script. Returns the number of records written.</summary>
    PUBLIC STATIC METHOD WriteScript( w AS TextWriter, oTable AS DbfTable, o AS ScriptOptions ) AS INT
        LOCAL aFields := oTable:GetFieldDefs() AS List<FieldDef>
        LOCAL aOrders := IIF( o:Indexes, oTable:GetOrders(), List<STRING[]>{} ) AS List<STRING[]>
        LOCAL cName   := Path.GetFileName( oTable:FileName ) AS STRING
        LOCAL nCount  := 0 AS INT
        DO CASE
        CASE o:Style == ScriptOptions.StyleVisualFoxPro
            nCount := ScriptGenerator.WriteVfp( w, oTable, o, aFields, aOrders, cName )
        CASE o:Style == ScriptOptions.StyleRddFieldInfo
            nCount := ScriptGenerator.WriteXs( w, oTable, o, aFields, aOrders, cName, FALSE )
        OTHERWISE
            nCount := ScriptGenerator.WriteXs( w, oTable, o, aFields, aOrders, cName, TRUE )
        ENDCASE
        RETURN nCount

    PRIVATE STATIC METHOD Header( w AS TextWriter, oTable AS DbfTable, cName AS STRING, cComment AS STRING, o AS ScriptOptions ) AS VOID
        w:WriteLine( cComment + " Generated by FabDBFEdEnh from " + cName + " on " + DateTime.Now:ToString( "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture ) )
        w:WriteLine( cComment + " Driver " + oTable:Driver + ", " + Convert.ToString( oTable:FieldCount ) + " fields, " + ;
            Convert.ToString( oTable:RecordCount() ) + " records in the file" )
        IF o:Records
            w:WriteLine( cComment + " Records: " + IIF( o:ViewOnly, "only those of the current view", "all" ) + ;
                " (records marked as deleted and binary memo / binary character values are not exported)" )
            FOREACH f AS FieldDef IN oTable:GetFieldDefs()
                IF f:Extra:Contains( "+" )
                    w:WriteLine( cComment + " AutoIncrement field " + f:Name + ": the values are assigned again when the records are appended" )
                ENDIF
            NEXT
        ENDIF
        RETURN

    /// <summary>The records to export: record numbers in natural order, or the current view</summary>
    PRIVATE STATIC METHOD RecordNumbers( oTable AS DbfTable, o AS ScriptOptions ) AS List<LONG>
        IF o:ViewOnly
            RETURN List<LONG>{ oTable:Recs }
        ENDIF
        LOCAL aAll := List<LONG>{} AS List<LONG>
        FOR VAR nRec := 1 TO oTable:RecordCount()
            aAll:Add( nRec )
        NEXT
        RETURN aAll

    PRIVATE STATIC METHOD WriteXs( w AS TextWriter, oTable AS DbfTable, o AS ScriptOptions, aFields AS List<FieldDef>, ;
                                   aOrders AS List<STRING[]>, cName AS STRING, lVo AS LOGIC ) AS INT
        LOCAL cFunc  := ScriptGenerator.FunctionName( oTable:FileName ) AS STRING
        LOCAL cAlias := DbfTable.MakeAlias( oTable:FileName ) AS STRING
        LOCAL cNil   := IIF( lVo, "NIL", "NULL" ) AS STRING
        LOCAL nCount := 0 AS INT
        ScriptGenerator.Header( w, oTable, cName, "//", o )
        w:WriteLine( "// Dialect: " + IIF( lVo, "VO / Vulcan (array literals, SToD)", "Core (RddFieldInfo, DateTime{})" ) )
        w:WriteLine( "" )
        // --- structure ---
        w:WriteLine( "FUNCTION " + cFunc + "( cFile AS STRING ) AS LOGIC" )
        IF lVo
            w:WriteLine( "    LOCAL aStruct AS ARRAY" )
            w:WriteLine( "    aStruct := { ;" )
        ELSE
            w:WriteLine( "    LOCAL aFields := <RddFieldInfo>{ ;" )
        ENDIF
        FOR VAR i := 0 TO aFields:Count - 1
            LOCAL f := aFields[i] AS FieldDef
            // last element closes the array; in the Core style a line continuation leads to "AS RddFieldInfo[]"
            LOCAL cSep := IIF( i < aFields:Count - 1, ", ;", IIF( lVo, " }", " } ;" ) ) AS STRING
            IF lVo
                w:WriteLine( "        { " + ScriptGenerator.XsString( f:Name ) + ", " + ScriptGenerator.XsString( f:TypeFull ) + ", " + ;
                    Convert.ToString( f:Length ) + ", " + Convert.ToString( f:Dec ) + " }" + cSep )
            ELSE
                w:WriteLine( "        RddFieldInfo{ " + ScriptGenerator.XsString( f:Name ) + ", " + ScriptGenerator.XsString( f:TypeFull ) + ", " + ;
                    Convert.ToString( f:Length ) + ", " + Convert.ToString( f:Dec ) + " }" + cSep )
            ENDIF
        NEXT
        IF ! lVo
            w:WriteLine( "        AS RddFieldInfo[]" )
        ENDIF
        w:WriteLine( "" )
        // IF aFields is empty the lines above would be incomplete: a table needs at least one field
        IF lVo
            w:WriteLine( "    IF ! DbCreate( cFile, aStruct, " + ScriptGenerator.XsString( oTable:Driver ) + " )" )
        ELSE
            w:WriteLine( "    IF ! CoreDb.Create( cFile, aFields, " + ScriptGenerator.XsString( oTable:Driver ) + ", TRUE, " + ;
                ScriptGenerator.XsString( cAlias ) + ", " + ScriptGenerator.XsString( "" ) + ", FALSE, FALSE )" )
        ENDIF
        w:WriteLine( "        RETURN FALSE" )
        w:WriteLine( "    ENDIF" )
        IF aOrders:Count > 0 .OR. o:Records
            w:WriteLine( "    IF ! DbUseArea( TRUE, " + ScriptGenerator.XsString( oTable:Driver ) + ", cFile, " + ;
                ScriptGenerator.XsString( cAlias ) + ", FALSE, FALSE )" )
            w:WriteLine( "        RETURN FALSE" )
            w:WriteLine( "    ENDIF" )
        ENDIF
        // --- records first (faster than maintaining the indexes while appending) ---
        IF o:Records
            w:WriteLine( "" )
            w:WriteLine( "    // --- records ---" )
            LOCAL aNumbers := ScriptGenerator.RecordNumbers( oTable, o ) AS List<LONG>
            FOREACH nRec AS LONG IN aNumbers
                LOCAL lDel := FALSE AS LOGIC
                LOCAL aRow := oTable:ReadRow( nRec, TRUE, REF lDel ) AS List<OBJECT>
                IF lDel
                    LOOP
                ENDIF
                LOCAL oLine := StringBuilder{} AS StringBuilder
                FOR VAR i := 0 TO aRow:Count - 1
                    IF i > 0
                        oLine:Append( ", " )
                    ENDIF
                    // AutoIncrement fields are assigned by the RDD when the record is appended (FieldPut would raise an error)
                    IF aFields[i]:Extra:Contains( "+" )
                        oLine:Append( cNil )
                    ELSE
                        oLine:Append( ScriptGenerator.XsValue( aRow[i], aFields[i]:FieldType, lVo ) )
                    ENDIF
                NEXT
                IF lVo
                    w:WriteLine( "    " + cFunc + "Row( { " + oLine:ToString() + " } )" )
                ELSE
                    w:WriteLine( "    " + cFunc + "Row( <OBJECT>{ " + oLine:ToString() + " } )" )
                ENDIF
                nCount++
            NEXT
        ENDIF
        // --- indexes ---
        IF aOrders:Count > 0
            w:WriteLine( "" )
            w:WriteLine( "    // --- indexes ---" )
            FOREACH aOrd AS STRING[] IN aOrders
                LOCAL cTag := (STRING) aOrd:GetValue( 0 ) AS STRING
                LOCAL cKey := (STRING) aOrd:GetValue( 1 ) AS STRING
                LOCAL cFor := (STRING) aOrd:GetValue( 2 ) AS STRING
                LOCAL lUnique := oTable:IsUniqueOrder( cTag, (STRING) aOrd:GetValue( 3 ) ) AS LOGIC
                IF cFor:Length > 0
                    w:WriteLine( "    OrdCondSet( " + ScriptGenerator.XsString( cFor ) + ", {|| " + cFor + " } )" )
                ENDIF
                w:WriteLine( "    OrdCreate( cFile, " + ScriptGenerator.XsString( cTag ) + ", " + ScriptGenerator.XsString( cKey ) + ;
                    ", {|| " + cKey + " }" + IIF( lUnique, ", TRUE", "" ) + " )" )
            NEXT
        ENDIF
        IF aOrders:Count > 0 .OR. o:Records
            w:WriteLine( "    DbCloseArea()" )
        ENDIF
        w:WriteLine( "    RETURN TRUE" )
        // --- helper for the records ---
        IF o:Records
            w:WriteLine( "" )
            w:WriteLine( "// Appends one record; " + cNil + " values are left empty" )
            IF lVo
                w:WriteLine( "STATIC FUNCTION " + cFunc + "Row( aValues AS ARRAY ) AS VOID" )
                w:WriteLine( "    LOCAL i AS DWORD" )
                w:WriteLine( "    DbAppend()" )
                w:WriteLine( "    FOR i := 1 UPTO ALen( aValues )" )
                w:WriteLine( "        IF aValues[i] != NIL" )
                w:WriteLine( "            FieldPut( i, aValues[i] )" )
                w:WriteLine( "        ENDIF" )
                w:WriteLine( "    NEXT" )
                w:WriteLine( "    RETURN" )
            ELSE
                w:WriteLine( "STATIC FUNCTION " + cFunc + "Row( aValues AS OBJECT[] ) AS VOID" )
                w:WriteLine( "    LOCAL nField := 0 AS DWORD" )
                w:WriteLine( "    DbAppend()" )
                w:WriteLine( "    FOREACH oValue AS OBJECT IN aValues" )
                w:WriteLine( "        nField++" )
                w:WriteLine( "        IF oValue != NULL" )
                w:WriteLine( "            FieldPut( nField, oValue )" )
                w:WriteLine( "        ENDIF" )
                w:WriteLine( "    NEXT" )
                w:WriteLine( "    RETURN" )
            ENDIF
        ENDIF
        RETURN nCount

    PRIVATE STATIC METHOD WriteVfp( w AS TextWriter, oTable AS DbfTable, o AS ScriptOptions, aFields AS List<FieldDef>, ;
                                    aOrders AS List<STRING[]>, cName AS STRING ) AS INT
        LOCAL cTable := Path.GetFileNameWithoutExtension( oTable:FileName ):ToLower() AS STRING
        LOCAL nCount := 0 AS INT
        ScriptGenerator.Header( w, oTable, cName, "*", o )
        w:WriteLine( "" )
        w:WriteLine( "CREATE TABLE " + cTable + " ( ;" )
        FOR VAR i := 0 TO aFields:Count - 1
            LOCAL f := aFields[i] AS FieldDef
            LOCAL cType := ScriptGenerator.VfpType( f ) AS STRING
            LOCAL cSep := IIF( i < aFields:Count - 1, ", ;", " )" ) AS STRING
            IF cType:Length == 0
                w:WriteLine( "    * unsupported field type " + f:TypeFull + ": " + f:Name + " is not created" )
            ELSE
                w:WriteLine( "    " + f:Name + " " + cType + cSep )
            ENDIF
        NEXT
        IF o:Records
            w:WriteLine( "" )
            LOCAL aNames := List<STRING>{} AS List<STRING>
            FOREACH f AS FieldDef IN aFields
                IF ScriptGenerator.VfpType( f ):Length > 0 .AND. ! f:Extra:Contains( "+" )
                    aNames:Add( f:Name )
                ENDIF
            NEXT
            LOCAL cList := String.Join( ", ", aNames:ToArray() ) AS STRING
            FOREACH nRec AS LONG IN ScriptGenerator.RecordNumbers( oTable, o )
                LOCAL lDel := FALSE AS LOGIC
                LOCAL aRow := oTable:ReadRow( nRec, TRUE, REF lDel ) AS List<OBJECT>
                IF lDel
                    LOOP
                ENDIF
                LOCAL aValues := List<STRING>{} AS List<STRING>
                FOR VAR i := 0 TO aRow:Count - 1
                    IF ScriptGenerator.VfpType( aFields[i] ):Length > 0 .AND. ! aFields[i]:Extra:Contains( "+" )
                        aValues:Add( ScriptGenerator.VfpValue( aRow[i], aFields[i]:FieldType ) )
                    ENDIF
                NEXT
                w:WriteLine( "INSERT INTO " + cTable + " ( " + cList + " ) VALUES ( " + String.Join( ", ", aValues:ToArray() ) + " )" )
                nCount++
            NEXT
        ENDIF
        IF aOrders:Count > 0
            w:WriteLine( "" )
            FOREACH aOrd AS STRING[] IN aOrders
                LOCAL cTag := (STRING) aOrd:GetValue( 0 ) AS STRING
                LOCAL cKey := (STRING) aOrd:GetValue( 1 ) AS STRING
                LOCAL cFor := (STRING) aOrd:GetValue( 2 ) AS STRING
                LOCAL lUnique := oTable:IsUniqueOrder( cTag, (STRING) aOrd:GetValue( 3 ) ) AS LOGIC
                w:WriteLine( "INDEX ON " + cKey + " TAG " + cTag + IIF( cFor:Length > 0, " FOR " + cFor, "" ) + IIF( lUnique, " UNIQUE", "" ) )
            NEXT
        ENDIF
        RETURN nCount

    // =====================================================================
    // Generate DBF Desc File
    // =====================================================================
    /// <summary>Plain text description: file facts, field list with offsets, indexes</summary>
    PUBLIC STATIC METHOD WriteDescription( w AS TextWriter, oTable AS DbfTable ) AS VOID
        LOCAL aFields := oTable:GetFieldDefs() AS List<FieldDef>
        LOCAL nHdrLen := 0 AS INT
        LOCAL nRecLen := 0 AS INT
        LOCAL cChanged := "" AS STRING
        LOCAL aHeader := oTable:ReadHeader() AS BYTE[]
        IF aHeader != NULL
            nHdrLen := BitConverter.ToUInt16( aHeader, 8 )
            nRecLen := BitConverter.ToUInt16( aHeader, 10 )
            cChanged := String.Format( CultureInfo.InvariantCulture, "{0:0000}-{1:00}-{2:00}", ;
                1900 + Convert.ToInt32( aHeader:GetValue( 1 ) ), aHeader:GetValue( 2 ), aHeader:GetValue( 3 ) )
        ELSE
            // the file is held exclusively (cannot be read from disk): derive what we can from the fields
            nRecLen := 1
            FOREACH f AS FieldDef IN aFields
                nRecLen += f:Length
            NEXT
            cChanged := "n/a (file opened exclusively)"
        ENDIF
        w:WriteLine( "DBF description" )
        w:WriteLine( String{ (CHAR) 61, 70 } )
        w:WriteLine( "File          : " + oTable:FileName )
        w:WriteLine( "Driver        : " + oTable:Driver )
        w:WriteLine( "Records       : " + Convert.ToString( oTable:RecordCount() ) )
        w:WriteLine( "Record length : " + Convert.ToString( nRecLen ) + " bytes" )
        w:WriteLine( "Header length : " + IIF( nHdrLen > 0, Convert.ToString( nHdrLen ) + " bytes", "n/a" ) )
        w:WriteLine( "Last change   : " + cChanged )
        w:WriteLine( "Fields        : " + Convert.ToString( aFields:Count ) )
        w:WriteLine( "Generated     : " + DateTime.Now:ToString( "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture ) + " by FabDBFEdEnh" )
        w:WriteLine( "" )
        w:WriteLine( "Nr  Field name   Type  Len  Dec  Offset  Flags" )
        w:WriteLine( String{ (CHAR) 45, 70 } )
        LOCAL nOffset := 1 AS INT
        FOR VAR i := 0 TO aFields:Count - 1
            LOCAL f := aFields[i] AS FieldDef
            LOCAL aFlags := List<STRING>{} AS List<STRING>
            IF f:Extra:Contains( "+" )
                aFlags:Add( "AutoIncrement" )
            ENDIF
            IF f:Extra:Contains( "B" )
                aFlags:Add( "Binary" )
            ENDIF
            IF f:Extra:Contains( "N" )
                aFlags:Add( "Nullable" )
            ENDIF
            w:WriteLine( Convert.ToString( i + 1 ):PadLeft( 2 ) + "  " + f:Name:PadRight( 11 ) + "  " + f:FieldType:PadRight( 4 ) + "  " + ;
                Convert.ToString( f:Length ):PadLeft( 3 ) + "  " + Convert.ToString( f:Dec ):PadLeft( 3 ) + "  " + ;
                Convert.ToString( nOffset ):PadLeft( 6 ) + "  " + String.Join( ", ", aFlags:ToArray() ) )
            nOffset += f:Length
        NEXT
        w:WriteLine( "" )
        LOCAL aOrders := oTable:GetOrders() AS List<STRING[]>
        w:WriteLine( "Indexes: " + Convert.ToString( aOrders:Count ) )
        IF aOrders:Count > 0
            w:WriteLine( String{ (CHAR) 45, 70 } )
            FOREACH aOrd AS STRING[] IN aOrders
                LOCAL cTag := (STRING) aOrd:GetValue( 0 ) AS STRING
                LOCAL cFor := (STRING) aOrd:GetValue( 2 ) AS STRING
                LOCAL cBag := (STRING) aOrd:GetValue( 3 ) AS STRING
                LOCAL cLine := cTag:PadRight( 12 ) + (STRING) aOrd:GetValue( 1 ) AS STRING
                IF cFor:Length > 0
                    cLine += "   FOR " + cFor
                ENDIF
                IF oTable:IsUniqueOrder( cTag, cBag )
                    cLine += "   UNIQUE"
                ENDIF
                IF cBag:Length > 0
                    cLine += "   [" + Path.GetFileName( cBag ) + "]"
                ENDIF
                w:WriteLine( cLine )
            NEXT
        ENDIF
        // the files that belong to the table
        LOCAL aSiblings := List<STRING>{} AS List<STRING>
        FOREACH cExt AS STRING IN <STRING>{ ".fpt", ".dbt", ".cdx" }
            IF File.Exists( Path.ChangeExtension( oTable:FileName, cExt ) )
                aSiblings:Add( Path.GetFileName( Path.ChangeExtension( oTable:FileName, cExt ) ) )
            ENDIF
        NEXT
        IF aSiblings:Count > 0
            w:WriteLine( "" )
            w:WriteLine( "Related files: " + String.Join( ", ", aSiblings:ToArray() ) )
        ENDIF
        RETURN
END CLASS


/// <summary>Options dialog of Generate Create PRG</summary>
PUBLIC CLASS ScriptDialog INHERIT System.Windows.Forms.Form
    PRIVATE rbDbCreate AS RadioButton
    PRIVATE rbRdd      AS RadioButton
    PRIVATE rbVfp      AS RadioButton
    PRIVATE chkIndexes AS CheckBox
    PRIVATE chkRecords AS CheckBox
    PRIVATE chkView    AS CheckBox
    // remembered for the next call in this session
    PRIVATE STATIC nLastStyle := 0 AS INT
    PRIVATE STATIC lLastRecords := FALSE AS LOGIC
    PUBLIC  Options AS ScriptOptions

    PUBLIC CONSTRUCTOR( cTable AS STRING, lHasOrders AS LOGIC, lRestricted AS LOGIC, nRecords AS LONG, nInView AS INT )
        SELF:Options := ScriptOptions{}
        SELF:Text            := "Generate Create PRG - " + cTable
        SELF:ClientSize      := Size{ 460, 300 }
        SELF:StartPosition   := FormStartPosition.CenterParent
        SELF:FormBorderStyle := FormBorderStyle.FixedDialog
        SELF:MaximizeBox     := FALSE
        SELF:MinimizeBox     := FALSE
        SELF:ShowInTaskbar   := FALSE
        SELF:Font            := Font{ "Microsoft Sans Serif", 8.25 }

        LOCAL gb := GroupBox{} AS GroupBox
        gb:Text     := "Output language"
        gb:Location := Point{ 12, 12 }
        gb:Size     := Size{ 436, 108 }
        SELF:rbDbCreate := SELF:MakeRadio( "X#  -  DbCreate() with an array (VO / Vulcan dialects)", 22 )
        SELF:rbRdd      := SELF:MakeRadio( "X#  -  RddFieldInfo and CoreDb.Create (Core dialect)", 50 )
        SELF:rbVfp      := SELF:MakeRadio( "Visual FoxPro  -  CREATE TABLE / INSERT INTO / INDEX ON", 78 )
        gb:Controls:Add( SELF:rbDbCreate )
        gb:Controls:Add( SELF:rbRdd )
        gb:Controls:Add( SELF:rbVfp )
        SELF:Controls:Add( gb )

        SELF:chkIndexes := CheckBox{}
        SELF:chkIndexes:Text     := "Include the index definitions"
        SELF:chkIndexes:Location := Point{ 20, 134 }
        SELF:chkIndexes:Size     := Size{ 420, 22 }
        SELF:chkIndexes:Checked  := lHasOrders
        SELF:chkIndexes:Enabled  := lHasOrders
        SELF:Controls:Add( SELF:chkIndexes )

        SELF:chkRecords := CheckBox{}
        SELF:chkRecords:Text     := "Include the existing records (like an export with data, " + Convert.ToString( nRecords ) + " in the file)"
        SELF:chkRecords:Location := Point{ 20, 162 }
        SELF:chkRecords:Size     := Size{ 430, 22 }
        SELF:chkRecords:Checked  := ScriptDialog.lLastRecords
        SELF:chkRecords:CheckedChanged += EventHandler{ SELF, @Records_Changed() }
        SELF:Controls:Add( SELF:chkRecords )

        SELF:chkView := CheckBox{}
        SELF:chkView:Text     := "Only the records of the current view (filter / scope): " + Convert.ToString( nInView )
        SELF:chkView:Location := Point{ 44, 188 }
        SELF:chkView:Size     := Size{ 400, 22 }
        SELF:chkView:Checked  := lRestricted
        SELF:chkView:Enabled  := lRestricted .AND. ScriptDialog.lLastRecords
        SELF:Controls:Add( SELF:chkView )
        SELF:lRestrictedView := lRestricted

        LOCAL lbl := Label{} AS Label
        lbl:Text     := "Records marked as deleted, and binary memo / binary character values, are not exported."
        lbl:Location := Point{ 20, 222 }
        lbl:Size     := Size{ 420, 32 }
        SELF:Controls:Add( lbl )

        LOCAL btnOk := Button{} AS Button
        btnOk:Text         := "Generate..."
        btnOk:Location     := Point{ 268, 262 }
        btnOk:Size         := Size{ 90, 26 }
        btnOk:DialogResult := DialogResult.OK
        btnOk:Click += EventHandler{ SELF, @Ok_Click() }
        SELF:Controls:Add( btnOk )

        LOCAL btnCancel := Button{} AS Button
        btnCancel:Text         := "Cancel"
        btnCancel:Location     := Point{ 364, 262 }
        btnCancel:Size         := Size{ 84, 26 }
        btnCancel:DialogResult := DialogResult.Cancel
        SELF:Controls:Add( btnCancel )

        SELF:AcceptButton := btnOk
        SELF:CancelButton := btnCancel
        DO CASE
        CASE ScriptDialog.nLastStyle == ScriptOptions.StyleRddFieldInfo
            SELF:rbRdd:Checked := TRUE
        CASE ScriptDialog.nLastStyle == ScriptOptions.StyleVisualFoxPro
            SELF:rbVfp:Checked := TRUE
        OTHERWISE
            SELF:rbDbCreate:Checked := TRUE
        ENDCASE
        RETURN

    PRIVATE lRestrictedView := FALSE AS LOGIC

    PRIVATE METHOD MakeRadio( cText AS STRING, nTop AS INT ) AS RadioButton
        LOCAL rb := RadioButton{} AS RadioButton
        rb:Text     := cText
        rb:Location := Point{ 16, nTop }
        rb:Size     := Size{ 410, 22 }
        RETURN rb

    PRIVATE METHOD Records_Changed( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:chkView:Enabled := SELF:chkRecords:Checked .AND. SELF:lRestrictedView
        RETURN

    PRIVATE METHOD Ok_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:rbVfp:Checked
            SELF:Options:Style := ScriptOptions.StyleVisualFoxPro
        ELSEIF SELF:rbRdd:Checked
            SELF:Options:Style := ScriptOptions.StyleRddFieldInfo
        ELSE
            SELF:Options:Style := ScriptOptions.StyleDbCreate
        ENDIF
        SELF:Options:Indexes  := SELF:chkIndexes:Checked
        SELF:Options:Records  := SELF:chkRecords:Checked
        SELF:Options:ViewOnly := SELF:chkRecords:Checked .AND. SELF:chkView:Checked .AND. SELF:chkView:Enabled
        ScriptDialog.nLastStyle   := SELF:Options:Style
        ScriptDialog.lLastRecords := SELF:Options:Records
        RETURN

    /// <summary>Default file extension / filter for the chosen style</summary>
    PUBLIC STATIC METHOD DefaultFileName( cTable AS STRING, nStyle AS INT ) AS STRING
        RETURN cTable + IIF( nStyle == ScriptOptions.StyleVisualFoxPro, "_create_vfp.prg", "_create.prg" )
END CLASS

END NAMESPACE
