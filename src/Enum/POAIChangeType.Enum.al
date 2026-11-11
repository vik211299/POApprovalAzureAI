namespace DefaultPublisher.POAIApproval;

enum 50100 "POAI Change Type"
{
    Caption = 'PO Approval Change Type';
    Extensible = true;

    value(0; "Header Modified")
    {
        Caption = 'Header Modified';
    }
    value(1; "Line Added")
    {
        Caption = 'Line Added';
    }
    value(2; "Line Modified")
    {
        Caption = 'Line Modified';
    }
    value(3; "Line Deleted")
    {
        Caption = 'Line Deleted';
    }
    value(4; "Comment Changed")
    {
        Caption = 'Comment Changed';
    }
}

