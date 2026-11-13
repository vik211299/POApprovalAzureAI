namespace DefaultPublisher.POAIApproval;

using Microsoft.Purchases.Document;

pageextension 50101 "POAI Purchase Order Ext" extends "Purchase Order"
{
    layout
    {
        addafter(Control23)
        {
            part(POAIVersionChangeFactBox; "POAI Version Change FactBox")
            {
                ApplicationArea = Suite;
                Caption = 'Purchase Order Version Changes';
                Visible = ShowPOVersionFactBox;
            }
        }
    }

    trigger OnAfterGetCurrRecord()
    begin
        ShowPOVersionFactBox := CurrPage.POAIVersionChangeFactBox.Page.LoadFromPurchaseHeader(Rec);
    end;

    var
        ShowPOVersionFactBox: Boolean;
}
