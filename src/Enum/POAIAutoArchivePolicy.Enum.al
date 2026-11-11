namespace DefaultPublisher.POAIApproval;

enum 50102 "POAI Auto-Archive Policy"
{
    Caption = 'PO Auto-Archive Policy';
    Extensible = false;

    value(0; "On Any Release")
    {
        Caption = 'On Any Release';
    }
    value(1; "On Approval Release")
    {
        Caption = 'On Approval Release Only';
    }
    value(2; "Disabled")
    {
        Caption = 'Disabled';
    }
}

