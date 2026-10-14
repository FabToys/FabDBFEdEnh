// FabModel.prg
// Created by    : fabri
// Creation Date : 2/11/2021 7:53:40 PM
// Created for   : 
// WorkStation   : FABPORTABLE


USING System
USING System.Collections.Generic
USING System.Text
USING XSharp.RDD.Support
USING System.IO
USING XSharp.RDD.Enums

BEGIN NAMESPACE FabDBFEdEnh
	
	FUNCTION ModelCreate( fileName AS STRING, rddInfo AS List<RddFieldInfo>, rdd AS STRING ) AS LOGIC
		LOCAL model AS FabModel
		//
model := FabModel{ rddInfo }
		RETURN model:Save( fileName )
	
	/// <summary>
	/// The FabModel class.
	/// </summary>
	CLASS FabModel
		
	PRIVATE fields AS List<RddFieldInfo>
		
CONSTRUCTOR(rddInfo AS List<RddFieldInfo> )
			SELF:fields := rddInfo
			RETURN
		
		METHOD Save( fileName AS STRING ) AS LOGIC
			LOCAL code AS StringBuilder
			LOCAL indent AS StringBuilder
			LOCAL dbName AS STRING
			//
dbName := SELF:SafeName( Path.GetFileNameWithoutExtension( fileName ) )
			code := StringBuilder{ }
			indent := StringBuilder{}
			//
			code:Append("USING System")
			code:Append( Environment.NewLine )
			code:Append("USING System.Collections.Generic")
			code:Append( Environment.NewLine )
			code:Append("USING System.Text")
			code:Append( Environment.NewLine )
			code:Append( Environment.NewLine )
			code:Append( Environment.NewLine )
			code:Append( "CLASS " )
			code:Append( dbName )
			code:Append( Environment.NewLine )
			//
			indent:Append( STRING{' ', 3} )
			VAR props := StringBuilder{}
			FOREACH fieldInfo AS RddFieldInfo IN fields
				//
				props:Append( indent )
				props:Append( "// " )
				props:Append( fieldInfo:Name )
				props:Append( "," )
				props:Append( fieldInfo:FieldTypeStr )
				props:Append( "," )
				props:Append( fieldInfo:Length )
				props:Append( "," )
				props:Append( fieldInfo:Decimals )
				props:Append( Environment.NewLine )
				props:Append( indent )
				props:Append( "PROPERTY " )
props:Append( SELF:SafeName( fieldInfo:Name ) )
				props:Append( " AS " )
props:Append( SELF:GetFieldType( fieldInfo ))
				props:Append( " AUTO" )
				props:Append( Environment.NewLine )
			NEXT
			code:Append( props )
			code:Append( Environment.NewLine )
			//
			code:Append( "CONSTRUCTOR()" )
			code:Append( Environment.NewLine )
			VAR inits := StringBuilder{}
			FOREACH fieldInfo AS RddFieldInfo IN fields
				//
				inits:Append( indent )
				inits:Append( "SELF:" )
inits:Append( SELF:SafeName( fieldInfo:Name ) )
				inits:Append( " := FieldGet(FieldPos(" )
				inits:Append( '"')
				inits:Append( fieldInfo:Name )
				inits:Append( '"')
				inits:Append( "))")
				inits:Append( Environment.NewLine )
			NEXT
			code:Append( inits )
			code:Append( "RETURN" )
			code:Append( Environment.NewLine )
			code:Append( Environment.NewLine )
			//
			code:Append( "CONSTRUCTOR( itemToCopy AS " )
			code:Append( dbName )
			code:Append( " )" )
			code:Append( Environment.NewLine )
			inits := StringBuilder{}
			FOREACH fieldInfo AS RddFieldInfo IN fields
				//
				inits:Append( indent )
				inits:Append( "SELF:" )
inits:Append( SELF:SafeName( fieldInfo:Name ) )
				inits:Append( " := itemToCopy:" )
inits:Append( SELF:SafeName( fieldInfo:Name ) )
				inits:Append( Environment.NewLine )
			NEXT
			code:Append( inits )
			code:Append( "RETURN" )
			code:Append( Environment.NewLine )
			code:Append( Environment.NewLine )
			//
			code:Append( "END CLASS" )
			code:Append( Environment.NewLine )
			//						
File.WriteAllText( fileName, code:ToString() )
			//
			RETURN TRUE
		
// Make sure the name can be used as an identifier
METHOD SafeName( name AS STRING ) AS STRING
LOCAL sb := StringBuilder{} AS StringBuilder
FOREACH c AS CHAR IN name
IF Char.IsLetterOrDigit( c ) .OR. c == '_'
sb:Append( c )
ELSE
sb:Append( '_' )
ENDIF
NEXT
IF sb:Length == 0 .OR. Char.IsDigit( sb[0] )
sb:Insert( 0, '_' )
ENDIF
RETURN sb:ToString()

METHOD GetFieldType( fieldInfo AS RddFieldInfo ) AS STRING
			// Commented out types are Harbour specific
			SWITCH fieldInfo:FieldType
				CASE DbFieldType.Character   // C
				CASE DbFieldType.VarChar     // 'V'
				CASE DbFieldType.VarBinary   // 'Q'
					RETURN "String"
				CASE DbFieldType.DateTime      // 'T'					
				CASE DbFieldType.Date        // D
					RETURN "DateTime"
				CASE DbFieldType.Number      // N
					IF fieldInfo:Decimals > 0
						RETURN "Double"
ENDIF
// More than 9 digits does not fit in an INT
IF fieldInfo:Length > 9
RETURN "INT64"
					ENDIF
					RETURN "INT"
				CASE DbFieldType.Memo        // M
					IF fieldInfo:IsBinary
						RETURN "OBJECT"
					ENDIF
					RETURN "STRING"
				CASE DbFieldType.Picture        // 'P'
				CASE DbFieldType.General        // 'G'
				CASE DbFieldType.Blob           // 'W'
					RETURN "OBJECT"
				CASE DbFieldType.Logic       // L
					RETURN "LOGIC"
				CASE DbFieldType.Integer    // 'I' 
					RETURN "INT"
				CASE DbFieldType.Float          // 'F'					
				CASE DbFieldType.Double         // 'B'
					RETURN "Double"
				CASE DbFieldType.VOObject       // 'O'
				CASE DbFieldType.Unknown        // 'O'
				OTHERWISE
					RETURN "OBJECT"
			END SWITCH		
			//RETURN "OBJECT"
			
			END CLASS
END NAMESPACE // FabDBFEdEnh