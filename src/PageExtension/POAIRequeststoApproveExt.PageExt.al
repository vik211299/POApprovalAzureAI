namespace DefaultPublisher.POAIApproval;

using Microsoft.Purchases.Document;
using System.Automation;

pageextension 50100 "POAI Requests to Approve Ext" extends "Requests to Approve"
{
    layout
    {
        addafter(Details)
        {
            field(POAIVersionComparison; VersionComparisonText)
            {
                ApplicationArea = Suite;
                Caption = 'Version Comparison';
                Editable = false;
                ToolTip = 'Specifies the Purchase Order version comparison for this approval request (for example, v2 vs v1).';
                Width = 18;
            }
            field(POAIChangeSummary; ChangeSummaryText)
            {
                ApplicationArea = Suite;
                Caption = 'Summary of Changes';
                Editable = false;
                StyleExpr = SummaryStyle;
                ToolTip = 'Specifies a summary of changes compared to the previous archived Purchase Order version. Choose to open the detailed version comparison.';
                Width = 55;

                trigger OnDrillDown()
                begin
                    OpenVersionChangeDetails();
                end;
            }
        }

        addafter(Change)
        {
            part(POAIVersionChangeFactBox; "POAI Version Change FactBox")
            {
                ApplicationArea = Suite;
                Visible = ShowPOVersionFactBox;
            }
        }
    }

    actions
    {
        addlast(Show)
        {
            action(POAIVersionChangeDetailsAction)
            {
                ApplicationArea = Suite;
                Caption = 'Version Changes';
                Enabled = IsPurchaseOrderSelected;
                Image = ViewDetails;
                Scope = Repeater;
                ToolTip = 'Opens a detailed comparison of all header, line, and comment changes against the previous Purchase Order version.';

                trigger OnAction()
                begin
                    OpenVersionChangeDetails();
                end;
            }
            action(POAIAskCopilotAction)
            {
                ApplicationArea = Suite;
                Caption = 'Ask Copilot About Changes';
                Enabled = HasDifferencesForCurrent;
                Image = Sparkle;
                Scope = Repeater;
                ToolTip = 'Opens an interactive Copilot dialog to ask follow-up questions about the changes in this Purchase Order version.';

                trigger OnAction()
                var
                    SummaryRec: Record "POAI Approval Change Summary";
                    PromptPage: Page "POAI Change Summary Prompt";
                begin
                    if not EnsureSummaryLoaded(SummaryRec) then
                        Error(NoSummaryForEntryErr);

                    PromptPage.LoadSummary(SummaryRec);
                    PromptPage.RunModal();
                end;
            }
        }

        addlast(Category_Process)
        {
            actionref(POAIVersionChangeDetailsAction_Promoted; POAIVersionChangeDetailsAction)
            {
            }
            actionref(POAIAskCopilotAction_Promoted; POAIAskCopilotAction)
            {
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        SummaryRec: Record "POAI Approval Change Summary";
        ApprovalSubscribers: Codeunit "POAI Approval Subscribers";
    begin
        Clear(VersionComparisonText);
        Clear(ChangeSummaryText);
        SummaryStyle := 'Standard';

        if not ApprovalSubscribers.TryGetSummaryForApprovalEntry(Rec, SummaryRec) then
            exit;

        VersionComparisonText := SummaryRec."Current Version Label";
        ChangeSummaryText := SummaryRec."Grid Summary";

        if SummaryRec."Has Differences" then
            SummaryStyle := 'StrongAccent'
        else
            if SummaryRec."Previous Version No." = 0 then
                SummaryStyle := 'Subordinate'
            else
                SummaryStyle := 'Favorable';
    end;

    trigger OnAfterGetCurrRecord()
    var
        SummaryRec: Record "POAI Approval Change Summary";
        ApprovalSubscribers: Codeunit "POAI Approval Subscribers";
    begin
        IsPurchaseOrderSelected :=
            (Rec."Table ID" = Database::"Purchase Header") and
            (Rec."Document Type" = Rec."Document Type"::Order) and
            (Rec."Document No." <> '');

        ShowPOVersionFactBox := CurrPage.POAIVersionChangeFactBox.Page.LoadFromApprovalEntry(Rec);

        HasDifferencesForCurrent := false;
        if IsPurchaseOrderSelected then
            if ApprovalSubscribers.TryGetSummaryForApprovalEntry(Rec, SummaryRec) then
                HasDifferencesForCurrent := SummaryRec."Has Differences" and (SummaryRec."Previous Version No." > 0);
    end;

    var
        VersionComparisonText: Text[50];
        ChangeSummaryText: Text[250];
        SummaryStyle: Text;
        ShowPOVersionFactBox: Boolean;
        IsPurchaseOrderSelected: Boolean;
        HasDifferencesForCurrent: Boolean;
        NoSummaryForEntryErr: Label 'No Purchase Order version comparison is available for the selected approval entry.';

    local procedure OpenVersionChangeDetails()
    var
        SummaryRec: Record "POAI Approval Change Summary";
    begin
        if not EnsureSummaryLoaded(SummaryRec) then begin
            Message(NoSummaryForEntryErr);
            exit;
        end;

        Page.Run(Page::"POAI Version Change Details", SummaryRec);
    end;

    local procedure EnsureSummaryLoaded(var SummaryRec: Record "POAI Approval Change Summary"): Boolean
    var
        PurchaseHeader: Record "Purchase Header";
        ApprovalSubscribers: Codeunit "POAI Approval Subscribers";
    begin
        if ApprovalSubscribers.TryGetSummaryForApprovalEntry(Rec, SummaryRec) then
            exit(true);

        if (Rec."Table ID" <> Database::"Purchase Header") or
           (Rec."Document Type" <> Rec."Document Type"::Order) or
           IsNullGuid(Rec."Workflow Step Instance ID")
        then
            exit(false);

        if not PurchaseHeader.Get(Enum::"Purchase Document Type"::Order, Rec."Document No.") then
            exit(false);

        ApprovalSubscribers.GenerateChangeSummaryForPurchaseOrder(Rec."Workflow Step Instance ID", PurchaseHeader);
        exit(SummaryRec.Get(Rec."Workflow Step Instance ID"));
    end;
}

