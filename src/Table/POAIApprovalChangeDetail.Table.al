namespace DefaultPublisher.POAIApproval;

table 50102 "POAI Approval Change Detail"
{
    Caption = 'Purchase Order Approval Change Detail';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Workflow Step Instance ID"; Guid)
        {
            Caption = 'Workflow Step Instance ID';
            DataClassification = SystemMetadata;
        }
        field(2; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            DataClassification = SystemMetadata;
        }
        field(3; "Change Type"; Enum "POAI Change Type")
        {
            Caption = 'Change Type';
            DataClassification = SystemMetadata;
        }
        field(4; "Line No."; Integer)
        {
            Caption = 'Line No.';
            DataClassification = CustomerContent;
            BlankZero = true;
        }
        field(5; "Item / Account No."; Code[20])
        {
            Caption = 'No.';
            DataClassification = CustomerContent;
        }
        field(6; "Line Description"; Text[100])
        {
            Caption = 'Line Description';
            DataClassification = CustomerContent;
        }
        field(7; "Field Caption"; Text[100])
        {
            Caption = 'Field';
            DataClassification = CustomerContent;
        }
        field(8; "Old Value"; Text[250])
        {
            Caption = 'Previous Value';
            DataClassification = CustomerContent;
        }
        field(9; "New Value"; Text[250])
        {
            Caption = 'New Value';
            DataClassification = CustomerContent;
        }
        field(10; "Amount Impact"; Decimal)
        {
            Caption = 'Amount Impact';
            AutoFormatType = 1;
            AutoFormatExpression = '';
            DataClassification = CustomerContent;
            BlankZero = true;
        }
    }

    keys
    {
        key(PK; "Workflow Step Instance ID", "Entry No.")
        {
            Clustered = true;
        }
        key(TypeKey; "Workflow Step Instance ID", "Change Type", "Line No.")
        {
        }
    }

    procedure GetChangeStyle(): Text
    begin
        case Rec."Change Type" of
            Rec."Change Type"::"Line Added":
                exit('Favorable');
            Rec."Change Type"::"Line Deleted":
                exit('Attention');
            Rec."Change Type"::"Line Modified", Rec."Change Type"::"Header Modified":
                exit('StrongAccent');
            else
                exit('Standard');
        end;
    end;
}

