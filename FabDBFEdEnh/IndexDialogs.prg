USING System
USING System.Drawing
USING System.Collections.Generic
USING System.Windows.Forms

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>Simple input dialog with several labelled text boxes and an optional check box</summary>
PUBLIC CLASS InputDialog INHERIT System.Windows.Forms.Form
    PRIVATE aBox := List<TextBox>{} AS List<TextBox>
    PRIVATE chk  AS CheckBox

    PUBLIC CONSTRUCTOR( cTitle AS STRING, cHint AS STRING, aLabel AS STRING[], aValue AS STRING[], cCheckText AS STRING, lCheck AS LOGIC )
        LOCAL nY := 12 AS INT
        SELF:Text            := cTitle
        SELF:FormBorderStyle := FormBorderStyle.FixedDialog
        SELF:StartPosition   := FormStartPosition.CenterParent
        SELF:MaximizeBox     := FALSE
        SELF:MinimizeBox     := FALSE
        SELF:ShowInTaskbar   := FALSE
        SELF:Font            := Font{ "Microsoft Sans Serif", 8.25 }

        IF cHint:Length > 0
            LOCAL lblH := Label{} AS Label
            lblH:Text     := cHint
            lblH:Location := Point{ 12, nY }
            lblH:Size     := Size{ 440, 30 }
            lblH:ForeColor := Color.DimGray
            SELF:Controls:Add( lblH )
            nY += 34
        ENDIF

        FOR VAR i := 0 TO aLabel:Length - 1
            LOCAL lbl := Label{} AS Label
            lbl:Text     := (STRING) aLabel:GetValue( i )
            lbl:Location := Point{ 12, nY + 3 }
            lbl:Size     := Size{ 90, 16 }
            LOCAL txt := TextBox{} AS TextBox
            txt:Location := Point{ 105, nY }
            txt:Size     := Size{ 345, 20 }
            IF i < aValue:Length
                txt:Text := (STRING) aValue:GetValue( i )
            ENDIF
            SELF:Controls:Add( lbl )
            SELF:Controls:Add( txt )
            SELF:aBox:Add( txt )
            nY += 26
        NEXT

        IF cCheckText:Length > 0
            SELF:chk := CheckBox{}
            SELF:chk:Text     := cCheckText
            SELF:chk:Location := Point{ 105, nY }
            SELF:chk:AutoSize := TRUE
            SELF:chk:Checked  := lCheck
            SELF:Controls:Add( SELF:chk )
            nY += 26
        ENDIF

        LOCAL btnOk := Button{} AS Button
        btnOk:Text := "OK"
        btnOk:Location := Point{ 290, nY + 6 }
        btnOk:Size := Size{ 75, 24 }
        btnOk:DialogResult := System.Windows.Forms.DialogResult.OK
        LOCAL btnCancelPick := Button{} AS Button
        btnCancelPick:Text := "Cancel"
        btnCancelPick:Location := Point{ 375, nY + 6 }
        btnCancelPick:Size := Size{ 75, 24 }
        btnCancelPick:DialogResult := System.Windows.Forms.DialogResult.Cancel
        SELF:Controls:Add( btnOk )
        SELF:Controls:Add( btnCancelPick )
        SELF:AcceptButton := btnOk
        SELF:CancelButton := btnCancelPick
        SELF:ClientSize := Size{ 464, nY + 42 }
        RETURN

    PUBLIC METHOD InputValue( nIdx AS INT ) AS STRING
        RETURN SELF:aBox[nIdx]:Text:Trim()

    PUBLIC PROPERTY MakeCheckBox AS LOGIC GET IIF( SELF:chk == NULL, FALSE, SELF:chk:Checked )
END CLASS


/// <summary>Index Manager: edit the orders as a list; "Create all" rebuilds the production CDX</summary>
PUBLIC CLASS IndexManagerDialog INHERIT System.Windows.Forms.Form
    PRIVATE oWindow  AS DataWindow
    PRIVATE lv        AS ListView
    PRIVATE lChanged := FALSE AS LOGIC

    PUBLIC CONSTRUCTOR( oF AS DataWindow )
        SELF:oWindow := oF
        SELF:Text          := "Index Manager - " + oF:Text
        SELF:Size          := Size{ 820, 400 }
        SELF:StartPosition := FormStartPosition.CenterParent
        SELF:ShowInTaskbar := FALSE
        SELF:MinimizeBox   := FALSE
        SELF:Font          := Font{ "Microsoft Sans Serif", 8.25 }

        SELF:lv := ListView{}
        SELF:lv:View          := View.Details
        SELF:lv:FullRowSelect := TRUE
        SELF:lv:GridLines     := TRUE
        SELF:lv:MultiSelect   := FALSE
        SELF:lv:HideSelection := FALSE
        SELF:lv:Dock          := DockStyle.Fill
        SELF:lv:Columns:Add( "Order", 110 )
        SELF:lv:Columns:Add( "Expression (Key)", 280 )
        SELF:lv:Columns:Add( "Condition (For)", 150 )
        SELF:lv:Columns:Add( "Unique", 50 )
        SELF:lv:Columns:Add( "Status", 100 )
        SELF:lv:DoubleClick += EventHandler{ SELF, @Edit_Click() }

        LOCAL pnl := FlowLayoutPanel{} AS FlowLayoutPanel
        pnl:Dock          := DockStyle.Right
        pnl:Width         := 125
        pnl:FlowDirection := FlowDirection.TopDown
        pnl:Padding       := Padding{ 6 }
        pnl:Controls:Add( SELF:MakeButton( "New order...",  EventHandler{ SELF, @New_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Edit...",  EventHandler{ SELF, @Edit_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Delete",       EventHandler{ SELF, @DeleteRecord_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "From file...",   EventHandler{ SELF, @FromFile_Click() } ) )
        LOCAL lblEmpty := Label{} AS Label
        lblEmpty:Height := 16
        pnl:Controls:Add( lblEmpty )
        pnl:Controls:Add( SELF:MakeButton( "Create all", EventHandler{ SELF, @CreateAll_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "ReIndex",        EventHandler{ SELF, @ReIndex_Click() } ) )
        pnl:Controls:Add( SELF:MakeButton( "Close",     EventHandler{ SELF, @Close_Click() } ) )

        SELF:Controls:Add( SELF:lv )
        SELF:Controls:Add( pnl )
        SELF:FormClosing += FormClosingEventHandler{ SELF, @Dialog_Closing() }
        SELF:Populate()
        RETURN

    PRIVATE METHOD MakeButton( cText AS STRING, oHandler AS EventHandler ) AS Button
        LOCAL b := Button{} AS Button
        b:Text   := cText
        b:Width  := 108
        b:Height := 26
        b:Click += oHandler
        RETURN b

    // load the existing orders of the production CDX into the list
    PRIVATE METHOD Populate() AS VOID
        LOCAL cBase := System.IO.Path.GetFileNameWithoutExtension( SELF:oWindow:FileName ) AS STRING
        SELF:lv:Items:Clear()
        FOREACH aOrder AS STRING[] IN SELF:oWindow:GetOrders()
            LOCAL cBag := (STRING) aOrder:GetValue( 3 ) AS STRING
            IF cBag:Length == 0 .OR. String.Compare( System.IO.Path.GetFileNameWithoutExtension( cBag ), cBase, TRUE ) == 0
                SELF:MakeItem( (STRING) aOrder:GetValue( 0 ), (STRING) aOrder:GetValue( 1 ), (STRING) aOrder:GetValue( 2 ), FALSE, "" )
            ENDIF
        NEXT
        SELF:lChanged := FALSE
        RETURN

    PRIVATE METHOD MakeItem( cName AS STRING, cKey AS STRING, cFor AS STRING, lUnique AS LOGIC, cStatus AS STRING ) AS ListViewItem
        LOCAL oItem := ListViewItem{ cName } AS ListViewItem
        oItem:SubItems:Add( cKey )
        oItem:SubItems:Add( cFor )
        oItem:SubItems:Add( IIF( lUnique, "yes", "" ) )
        oItem:SubItems:Add( cStatus )
        SELF:lv:Items:Add( oItem )
        RETURN oItem

    PRIVATE METHOD NameExists( cName AS STRING, oExcept AS ListViewItem ) AS LOGIC
        FOREACH oItem AS ListViewItem IN SELF:lv:Items
            IF oItem != oExcept .AND. String.Compare( oItem:Text, cName, TRUE ) == 0
                RETURN TRUE
            ENDIF
        NEXT
        RETURN FALSE

    PRIVATE METHOD New_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL dlg := InputDialog{ "New order", ;
            "Expression and condition in X#/VO syntax, e.g.  Upper(LASTNAME)+Upper(FIRSTNAME)   or   ! Deleted()", ;
            <STRING>{ "Name", "Expression", "Condition" }, <STRING>{ "", "", "" }, "Unique", FALSE } AS InputDialog
        IF dlg:ShowDialog( SELF ) == DialogResult.OK
            IF dlg:InputValue( 0 ):Length == 0 .OR. dlg:InputValue( 1 ):Length == 0
                MessageBox.Show( "Name and expression are required.", "New order" )
                RETURN
            ENDIF
            IF SELF:NameExists( dlg:InputValue( 0 ), NULL )
                MessageBox.Show( "An order with this name already exists.", "New order" )
                RETURN
            ENDIF
            LOCAL oItem := SELF:MakeItem( dlg:InputValue( 0 ):ToUpper(), dlg:InputValue( 1 ), dlg:InputValue( 2 ), dlg:MakeCheckBox, "new" ) AS ListViewItem
            oItem:Selected := TRUE
            oItem:EnsureVisible()
            SELF:lChanged := TRUE
        ENDIF
        RETURN

    PRIVATE METHOD Edit_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:lv:SelectedItems:Count == 0
            RETURN
        ENDIF
        LOCAL oItem := SELF:lv:SelectedItems[0] AS ListViewItem
        LOCAL dlg := InputDialog{ "Edit order", "", <STRING>{ "Name", "Expression", "Condition" }, ;
            <STRING>{ oItem:Text, oItem:SubItems[1]:Text, oItem:SubItems[2]:Text }, "Unique", oItem:SubItems[3]:Text == "yes" } AS InputDialog
        IF dlg:ShowDialog( SELF ) == DialogResult.OK
            IF dlg:InputValue( 0 ):Length == 0 .OR. dlg:InputValue( 1 ):Length == 0 .OR. SELF:NameExists( dlg:InputValue( 0 ), oItem )
                MessageBox.Show( "Name missing, expression missing or duplicate name.", "Edit order" )
                RETURN
            ENDIF
            oItem:Text := dlg:InputValue( 0 ):ToUpper()
            oItem:SubItems[1]:Text := dlg:InputValue( 1 )
            oItem:SubItems[2]:Text := dlg:InputValue( 2 )
            oItem:SubItems[3]:Text := IIF( dlg:MakeCheckBox, "yes", "" )
            IF oItem:SubItems[4]:Text != "new"
                oItem:SubItems[4]:Text := "changed"
            ENDIF
            SELF:lChanged := TRUE
        ENDIF
        RETURN

    PRIVATE METHOD DeleteRecord_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF SELF:lv:SelectedItems:Count == 0
            RETURN
        ENDIF
        LOCAL n := SELF:lv:SelectedIndices[0] AS INT
        SELF:lv:Items:RemoveAt( n )
        IF SELF:lv:Items:Count > 0
            SELF:lv:Items[Math.Min( n, SELF:lv:Items:Count - 1 )]:Selected := TRUE
        ENDIF
        SELF:lChanged := TRUE
        RETURN

    // Take over the orders of another DBF (e.g. backup *_OLD_*.dbf) into the list
    PRIVATE METHOD FromFile_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        LOCAL ofd := OpenFileDialog{} AS OpenFileDialog
        ofd:Title := "Select the DBF whose indexes should be taken over"
        ofd:Filter := "DBF files (*.dbf)|*.dbf|All files (*.*)|*.*"
        ofd:InitialDirectory := System.IO.Path.GetDirectoryName( SELF:oWindow:FileName )
        IF ofd:ShowDialog( SELF ) != DialogResult.OK
            RETURN
        ENDIF
        LOCAL aOrders := StructureRebuild.ReadOrders( ofd:FileName, SELF:oWindow:Driver ) AS List<STRING[]>
        SELF:oWindow:SelectArea()
        LOCAL nNew := 0 AS INT
        FOREACH aOrd AS STRING[] IN aOrders
            IF ! SELF:NameExists( (STRING) aOrd:GetValue( 0 ), NULL )
                SELF:MakeItem( (STRING) aOrd:GetValue( 0 ), (STRING) aOrd:GetValue( 1 ), (STRING) aOrd:GetValue( 2 ), (STRING) aOrd:GetValue( 3 ) == "1", "new" )
                nNew++
            ENDIF
        NEXT
        IF nNew > 0
            SELF:lChanged := TRUE
        ENDIF
        MessageBox.Show( Convert.ToString( aOrders:Count ) + " orders found, " + Convert.ToString( nNew ) + " newly added to the list." + ;
            Environment.NewLine + "They are only created with 'Create all'.", SELF:Text )
        RETURN

    // Production CDX completely new: remove all existing orders, create all orders of the list
    PRIVATE METHOD CreateAll_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF ! SELF:oWindow:Exclusive .OR. SELF:oWindow:ReadOnly
            MessageBox.Show( "Creating indexes is only possible when the file is opened EXCLUSIVE and not read-only.", SELF:Text )
            RETURN
        ENDIF
        IF MessageBox.Show( "All indexes of the production CDX will now be removed and the " + Convert.ToString( SELF:lv:Items:Count ) + ;
                " orders of the list recreated." + Environment.NewLine + Environment.NewLine + "Continue?", SELF:Text, ;
                MessageBoxButtons.YesNo, MessageBoxIcon.Question ) != DialogResult.Yes
            RETURN
        ENDIF
        LOCAL aList := List<STRING[]>{} AS List<STRING[]>
        FOREACH oItem AS ListViewItem IN SELF:lv:Items
            aList:Add( <STRING>{ oItem:Text, oItem:SubItems[1]:Text, oItem:SubItems[2]:Text, IIF( oItem:SubItems[3]:Text == "yes", "1", "0" ) } )
        NEXT
        SELF:Cursor := Cursors.WaitCursor
        LOCAL aStatus := List<STRING>{} AS List<STRING>
        TRY
            aStatus := SELF:oWindow:CreateAllOrders( aList )
        FINALLY
            SELF:Cursor := Cursors.Default
        END TRY
        LOCAL nError := 0 AS INT
        FOR VAR i := 0 TO Math.Min( aStatus:Count, SELF:lv:Items:Count ) - 1
            SELF:lv:Items[i]:SubItems[4]:Text := IIF( aStatus[i]:Length == 0, "OK", "Error: " + aStatus[i] )
            IF aStatus[i]:Length > 0
                nError++
            ENDIF
        NEXT
        SELF:lChanged := FALSE
        MessageBox.Show( Convert.ToString( aList:Count - nError ) + " orders created" + ;
            IIF( nError > 0, ", " + Convert.ToString( nError ) + " with errors (see column Status)", "" ) + ".", SELF:Text )
        RETURN

    PRIVATE METHOD ReIndex_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        IF MessageBox.Show( "Rebuild all indexes of this file?", "ReIndex", MessageBoxButtons.YesNo, MessageBoxIcon.Question ) == DialogResult.Yes
            IF SELF:oWindow:ReIndex()
                MessageBox.Show( "ReIndex finished.", "ReIndex" )
            ENDIF
        ENDIF
        RETURN

    PRIVATE METHOD Close_Click( sender AS OBJECT, e AS EventArgs ) AS VOID
        SELF:Close()
        RETURN

    PRIVATE METHOD Dialog_Closing( sender AS OBJECT, e AS FormClosingEventArgs ) AS VOID
        IF SELF:lChanged
            IF MessageBox.Show( "The changes to the list have not been created yet." + Environment.NewLine + "Close anyway and discard the changes?", ;
                    SELF:Text, MessageBoxButtons.YesNo, MessageBoxIcon.Warning ) != DialogResult.Yes
                e:Cancel := TRUE
            ENDIF
        ENDIF
        RETURN
END CLASS

END NAMESPACE
