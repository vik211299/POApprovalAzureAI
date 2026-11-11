namespace DefaultPublisher.POAIApproval;

enum 50101 "POAI AI Status"
{
    Caption = 'PO Approval AI Status';
    Extensible = true;

    value(0; "Initial Version")
    {
        Caption = 'Initial Version';
    }
    value(1; "Generated")
    {
        Caption = 'AI Generated';
    }
    value(2; "Fallback Deterministic")
    {
        Caption = 'Deterministic Summary';
    }
    value(3; "Failed")
    {
        Caption = 'AI Failed (Fallback)';
    }
}

