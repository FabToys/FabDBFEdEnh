USING System
USING System.Drawing
USING System.Windows.Forms

BEGIN NAMESPACE FabDBFEdEnh

/// <summary>Open dialog like in the dBAdministrator: Driver, Locking, Exclusive, Read Only, Show Recno, Show Deleted</summary>
PUBLIC CLASS OpenDialog INHERIT System.Windows.Forms.Form

    PRIVATE cmbDriver   AS ComboBox
    PRIVATE cmbLocking  AS ComboBox
    PRIVATE chkExcl     AS CheckBox
    PRIVATE chkOnlyRead AS CheckBox
    PRIVATE chkRecno    AS CheckBox
    PRIVATE chkDeleted  AS CheckBox

    // Display text  ->  RDD name (same order)
    PRIVATE STATIC aDriverText := <STRING>{ "FoxPro - DBFCDX/FPT", "Clipper - DBFNTX/DBT", "Visual FoxPro - DBFVFP" } AS STRING[]
    PRIVATE STATIC aDriverRdd  := <STRING>{ "DBFCDX", "DBFNTX", "DBFVFP" } AS STRING[]

    PUBLIC CONSTRUCTOR(cFile AS STRING, cRdd AS STRING, lReadOnly AS LOGIC)
        LOCAL lblDriver, lblLocking AS Label
        LOCAL btnOk, btnCancel AS Button

        SELF:Text            := cFile
        SELF:FormBorderStyle := FormBorderStyle.FixedDialog
        SELF:StartPosition   := FormStartPosition.CenterParent
        SELF:MaximizeBox     := FALSE
        SELF:MinimizeBox     := FALSE
        SELF:ShowInTaskbar   := FALSE
        SELF:ClientSize      := Size{250, 200}

        lblDriver := Label{}
        lblDriver:Text     := "Driver"
        lblDriver:Location := Point{12, 12}
        lblDriver:AutoSize := TRUE

        SELF:cmbDriver := ComboBox{}
        SELF:cmbDriver:DropDownStyle := ComboBoxStyle.DropDownList
        SELF:cmbDriver:Location := Point{12, 30}
        SELF:cmbDriver:Size     := Size{226, 21}
        SELF:cmbDriver:Items:AddRange( <OBJECT>{ aDriverText[1], aDriverText[2], aDriverText[3] } )
        SELF:cmbDriver:SelectedIndex := 0
        FOR VAR i := 1 TO aDriverRdd:Length
            IF String.Compare( aDriverRdd[i], cRdd, TRUE ) == 0
                SELF:cmbDriver:SelectedIndex := i - 1
            ENDIF
        NEXT

        lblLocking := Label{}
        lblLocking:Text     := "Locking"
        lblLocking:Location := Point{12, 62}
        lblLocking:AutoSize := TRUE

        SELF:cmbLocking := ComboBox{}
        SELF:cmbLocking:DropDownStyle := ComboBoxStyle.DropDownList
        SELF:cmbLocking:Location := Point{12, 80}
        SELF:cmbLocking:Size     := Size{226, 21}
        SELF:cmbLocking:Items:AddRange( <OBJECT>{ "Automatic", "Manual" } )
        SELF:cmbLocking:SelectedIndex := 0

        SELF:chkExcl := CheckBox{}
        SELF:chkExcl:Text     := "Exclusive"
        SELF:chkExcl:Location := Point{12, 112}
        SELF:chkExcl:AutoSize := TRUE

        SELF:chkOnlyRead := CheckBox{}
        SELF:chkOnlyRead:Text     := "Read Only"
        SELF:chkOnlyRead:Location := Point{130, 112}
        SELF:chkOnlyRead:AutoSize := TRUE
        SELF:chkOnlyRead:Checked  := lReadOnly

        SELF:chkRecno := CheckBox{}
        SELF:chkRecno:Text     := "Show Recno"
        SELF:chkRecno:Location := Point{12, 136}
        SELF:chkRecno:AutoSize := TRUE
        SELF:chkRecno:Checked  := TRUE

        SELF:chkDeleted := CheckBox{}
        SELF:chkDeleted:Text     := "Show Deleted"
        SELF:chkDeleted:Location := Point{130, 136}
        SELF:chkDeleted:AutoSize := TRUE
        SELF:chkDeleted:Checked  := TRUE

        btnOk := Button{}
        btnOk:Text         := "OK"
        btnOk:Location     := Point{40, 166}
        btnOk:Size         := Size{80, 24}
        btnOk:DialogResult := System.Windows.Forms.DialogResult.OK

        btnCancel := Button{}
        btnCancel:Text         := "Cancel"
        btnCancel:Location     := Point{130, 166}
        btnCancel:Size         := Size{80, 24}
        btnCancel:DialogResult := System.Windows.Forms.DialogResult.Cancel

        SELF:AcceptButton := btnOk
        SELF:CancelButton := btnCancel

        SELF:Controls:AddRange( <Control>{ lblDriver, SELF:cmbDriver, lblLocking, SELF:cmbLocking, ;
            SELF:chkExcl, SELF:chkOnlyRead, SELF:chkRecno, SELF:chkDeleted, btnOk, btnCancel } )
        RETURN

    // Variant with the saved default values (Options / Set Defaults)
    PUBLIC CONSTRUCTOR(cFile AS STRING, oSettings AS AppSettings)
        SELF(cFile, oSettings:Driver, oSettings:ReadOnly)
        SELF:chkExcl:Checked    := oSettings:Exclusive
        SELF:chkRecno:Checked   := oSettings:ShowRecno
        SELF:chkDeleted:Checked := oSettings:ShowDeleted
        SELF:cmbLocking:SelectedIndex := IIF( oSettings:Locking == 1, 1, 0 )
        RETURN

    PUBLIC PROPERTY Driver          AS STRING GET aDriverRdd[ SELF:cmbDriver:SelectedIndex + 1 ]
    PUBLIC PROPERTY Exclusive        AS LOGIC  GET SELF:chkExcl:Checked
    PUBLIC PROPERTY ReadOnly        AS LOGIC  GET SELF:chkOnlyRead:Checked
    PUBLIC PROPERTY ShowRecno      AS LOGIC  GET SELF:chkRecno:Checked
    PUBLIC PROPERTY ShowDeleted AS LOGIC  GET SELF:chkDeleted:Checked
    PUBLIC PROPERTY ManualLocking AS LOGIC GET SELF:cmbLocking:SelectedIndex == 1

END CLASS

END NAMESPACE
