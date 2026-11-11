namespace DefaultPublisher.POAIApproval;

page 50104 "POAI Change Detail Subform"
{
    ApplicationArea = All;
    Caption = 'Field & Line Change Breakdown';
    DeleteAllowed = false;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    PageType = ListPart;
    SourceTable = "POAI Approval Change Detail";

    layout
    {
        area(Content)
        {
            repeater(DetailsRepeater)
            {
                ShowCaption = false;

                field("Change Type"; Rec."Change Type")
                {
                    ApplicationArea = All;
                    StyleExpr = RowStyle;
                    ToolTip = 'Specifies the category of change between the previous version and the current Purchase Order.';
                }
                field("Line No."; Rec."Line No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the Purchase Order line number (0 for header-level changes).';
                }
                field("Item / Account No."; Rec."Item / Account No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the item, G/L account, or charge number on the changed line.';
                }
                field("Line Description"; Rec."Line Description")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the description on the changed line.';
                }
                field("Field Caption"; Rec."Field Caption")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies which field changed.';
                }
                field("Old Value"; Rec."Old Value")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the value from the previous archived version.';
                }
                field("New Value"; Rec."New Value")
                {
                    ApplicationArea = All;
                    StyleExpr = RowStyle;
                    ToolTip = 'Specifies the current value submitted for approval.';
                }
                field("Amount Impact"; Rec."Amount Impact")
                {
                    ApplicationArea = All;
                    StyleExpr = RowStyle;
                    ToolTip = 'Specifies the net line amount delta resulting from this change.';
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        RowStyle := Rec.GetChangeStyle();
    end;

    var
        RowStyle: Text;
}

