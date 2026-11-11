namespace DefaultPublisher.POAIApproval;

using Microsoft.Finance.Currency;
using Microsoft.Purchases.Document;

table 50101 "POAI Approval Change Summary"
{
    Caption = 'PO Approval Change Summary';
    DataClassification = CustomerContent;
    LookupPageId = "POAI Version Change Details";
    DrillDownPageId = "POAI Version Change Details";

    fields
    {
        field(1; "Workflow Step Instance ID"; Guid)
        {
            Caption = 'Workflow Step Instance ID';
            DataClassification = SystemMetadata;
        }
        field(2; "Record ID to Approve"; RecordId)
        {
            Caption = 'Record ID to Approve';
            DataClassification = CustomerContent;
        }
        field(3; "Document Type"; Enum "Purchase Document Type")
        {
            Caption = 'Document Type';
            DataClassification = CustomerContent;
        }
        field(4; "Document No."; Code[20])
        {
            Caption = 'Document No.';
            DataClassification = CustomerContent;
        }
        field(5; "Doc. No. Occurrence"; Integer)
        {
            Caption = 'Doc. No. Occurrence';
            DataClassification = CustomerContent;
        }
        field(6; "Previous Version No."; Integer)
        {
            Caption = 'Previous Version No.';
            DataClassification = CustomerContent;
        }
        field(7; "Current Version Label"; Text[50])
        {
            Caption = 'Version Comparison';
            DataClassification = CustomerContent;
        }
        field(8; "Baseline Date Archived"; Date)
        {
            Caption = 'Previous Version Archived Date';
            DataClassification = CustomerContent;
        }
        field(9; "Baseline Archived By"; Code[50])
        {
            Caption = 'Previous Version Archived By';
            DataClassification = EndUserIdentifiableInformation;
        }
        field(10; "Buy-from Vendor No."; Code[20])
        {
            Caption = 'Buy-from Vendor No.';
            DataClassification = CustomerContent;
        }
        field(11; "Buy-from Vendor Name"; Text[100])
        {
            Caption = 'Buy-from Vendor Name';
            DataClassification = CustomerContent;
        }
        field(12; "Currency Code"; Code[10])
        {
            Caption = 'Currency Code';
            DataClassification = CustomerContent;
            TableRelation = Currency;
        }
        field(13; "Old Amount"; Decimal)
        {
            Caption = 'Previous Amount';
            AutoFormatType = 1;
            AutoFormatExpression = Rec."Currency Code";
            DataClassification = CustomerContent;
        }
        field(14; "New Amount"; Decimal)
        {
            Caption = 'Current Amount';
            AutoFormatType = 1;
            AutoFormatExpression = Rec."Currency Code";
            DataClassification = CustomerContent;
        }
        field(15; "Amount Variance"; Decimal)
        {
            Caption = 'Amount Variance';
            AutoFormatType = 1;
            AutoFormatExpression = Rec."Currency Code";
            DataClassification = CustomerContent;
        }
        field(16; "Old Amount Incl. VAT"; Decimal)
        {
            Caption = 'Previous Amount Incl. VAT';
            AutoFormatType = 1;
            AutoFormatExpression = Rec."Currency Code";
            DataClassification = CustomerContent;
        }
        field(17; "New Amount Incl. VAT"; Decimal)
        {
            Caption = 'Current Amount Incl. VAT';
            AutoFormatType = 1;
            AutoFormatExpression = Rec."Currency Code";
            DataClassification = CustomerContent;
        }
        field(18; "Header Changes Count"; Integer)
        {
            Caption = 'Header Fields Changed';
            DataClassification = SystemMetadata;
        }
        field(19; "Lines Added Count"; Integer)
        {
            Caption = 'Lines Added';
            DataClassification = SystemMetadata;
        }
        field(20; "Lines Modified Count"; Integer)
        {
            Caption = 'Lines Modified';
            DataClassification = SystemMetadata;
        }
        field(21; "Lines Deleted Count"; Integer)
        {
            Caption = 'Lines Deleted';
            DataClassification = SystemMetadata;
        }
        field(22; "Comments Changed Count"; Integer)
        {
            Caption = 'Comments Changed';
            DataClassification = SystemMetadata;
        }
        field(23; "Grid Summary"; Text[250])
        {
            Caption = 'Summary of Changes';
            DataClassification = CustomerContent;
        }
        field(24; "AI Summary"; Blob)
        {
            Caption = 'AI Summary';
            DataClassification = CustomerContent;
        }
        field(25; "Deterministic Summary"; Blob)
        {
            Caption = 'Deterministic Summary';
            DataClassification = CustomerContent;
        }
        field(26; "Diff Payload JSON"; Blob)
        {
            Caption = 'Diff Payload JSON';
            DataClassification = CustomerContent;
        }
        field(27; "AI Status"; Enum "POAI AI Status")
        {
            Caption = 'Summary Source';
            DataClassification = SystemMetadata;
        }
        field(28; "Last Error Message"; Text[250])
        {
            Caption = 'Last AI Error';
            DataClassification = SystemMetadata;
        }
        field(29; "Generated DateTime"; DateTime)
        {
            Caption = 'Generated DateTime';
            DataClassification = SystemMetadata;
        }
        field(30; "Has Differences"; Boolean)
        {
            Caption = 'Has Differences';
            DataClassification = SystemMetadata;
        }
    }

    keys
    {
        key(PK; "Workflow Step Instance ID")
        {
            Clustered = true;
        }
        key(DocKey; "Document Type", "Document No.", "Generated DateTime")
        {
        }
    }

    trigger OnDelete()
    var
        ChangeDetail: Record "POAI Approval Change Detail";
    begin
        ChangeDetail.SetRange("Workflow Step Instance ID", Rec."Workflow Step Instance ID");
        if not ChangeDetail.IsEmpty() then
            ChangeDetail.DeleteAll();
    end;

    procedure SetAISummaryText(SummaryText: Text)
    begin
        WriteBlobText(Rec.FieldNo("AI Summary"), SummaryText);
    end;

    procedure GetAISummaryText(): Text
    begin
        Rec.CalcFields("AI Summary");
        exit(ReadBlobText(Rec.FieldNo("AI Summary")));
    end;

    procedure SetDeterministicSummaryText(SummaryText: Text)
    begin
        WriteBlobText(Rec.FieldNo("Deterministic Summary"), SummaryText);
    end;

    procedure GetDeterministicSummaryText(): Text
    begin
        Rec.CalcFields("Deterministic Summary");
        exit(ReadBlobText(Rec.FieldNo("Deterministic Summary")));
    end;

    procedure SetDiffPayloadJson(JsonText: Text)
    begin
        WriteBlobText(Rec.FieldNo("Diff Payload JSON"), JsonText);
    end;

    procedure GetDiffPayloadJson(): Text
    begin
        Rec.CalcFields("Diff Payload JSON");
        exit(ReadBlobText(Rec.FieldNo("Diff Payload JSON")));
    end;

    procedure GetEffectiveSummaryText(): Text
    var
        AISummaryTxt: Text;
    begin
        AISummaryTxt := GetAISummaryText();
        if AISummaryTxt <> '' then
            exit(AISummaryTxt);
        exit(GetDeterministicSummaryText());
    end;

    local procedure WriteBlobText(FieldNumber: Integer; ContentText: Text)
    var
        OutStr: OutStream;
    begin
        case FieldNumber of
            Rec.FieldNo("AI Summary"):
                Rec."AI Summary".CreateOutStream(OutStr, TextEncoding::UTF8);
            Rec.FieldNo("Deterministic Summary"):
                Rec."Deterministic Summary".CreateOutStream(OutStr, TextEncoding::UTF8);
            Rec.FieldNo("Diff Payload JSON"):
                Rec."Diff Payload JSON".CreateOutStream(OutStr, TextEncoding::UTF8);
            else
                exit;
        end;
        OutStr.WriteText(ContentText);
    end;

    local procedure ReadBlobText(FieldNumber: Integer): Text
    var
        InStr: InStream;
        LineText: Text;
        Builder: TextBuilder;
        HasVal: Boolean;
    begin
        case FieldNumber of
            Rec.FieldNo("AI Summary"):
                begin
                    HasVal := Rec."AI Summary".HasValue();
                    if HasVal then
                        Rec."AI Summary".CreateInStream(InStr, TextEncoding::UTF8);
                end;
            Rec.FieldNo("Deterministic Summary"):
                begin
                    HasVal := Rec."Deterministic Summary".HasValue();
                    if HasVal then
                        Rec."Deterministic Summary".CreateInStream(InStr, TextEncoding::UTF8);
                end;
            Rec.FieldNo("Diff Payload JSON"):
                begin
                    HasVal := Rec."Diff Payload JSON".HasValue();
                    if HasVal then
                        Rec."Diff Payload JSON".CreateInStream(InStr, TextEncoding::UTF8);
                end;
        end;

        if not HasVal then
            exit('');

        while not InStr.EOS() do begin
            InStr.ReadText(LineText);
            if Builder.Length > 0 then
                Builder.AppendLine();
            Builder.Append(LineText);
        end;

        exit(Builder.ToText());
    end;
}
