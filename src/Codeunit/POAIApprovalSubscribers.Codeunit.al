namespace DefaultPublisher.POAIApproval;

using Microsoft.Purchases.Archive;
using Microsoft.Purchases.Document;
using System.Automation;

codeunit 50104 "POAI Approval Subscribers"
{
    Access = Public;
    Permissions = tabledata "POAI Copilot Setup" = ri,
                  tabledata "Purchase Header" = r,
                  tabledata "Purchase Header Archive" = r,
                  tabledata "POAI Approval Change Summary" = rimd,
                  tabledata "POAI Approval Change Detail" = rimd;

    var
        CompareChangesConfirmQst: Label 'Do you want to compare changes occurred from previous version?';

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Approvals Mgmt.", 'OnBeforeApproveApprovalRequests', '', false, false)]
    local procedure OnBeforeApproveApprovalRequests(var ApprovalEntry: Record "Approval Entry"; var IsHandled: Boolean)
    var
        ApprovalEntryFilter: Record "Approval Entry";
        PurchaseHeader: Record "Purchase Header";
        LatestArchHeader: Record "Purchase Header Archive";
        SummaryRec: Record "POAI Approval Change Summary";
        ApprovalReviewState: Codeunit "POAI Approval Review State";
        ArchiveHandler: Codeunit "POAI Version Archive Handler";
        PromptPage: Page "POAI Change Summary Prompt";
        HasSummary: Boolean;
        HasPreviousArchive: Boolean;
    begin
        if IsHandled then
            exit;

        if not ApprovalReviewState.ConsumeRequestsToApproveContext() then
            exit;

        if not GuiAllowed() then
            exit;

        ApprovalEntryFilter.Copy(ApprovalEntry);
        if ApprovalEntryFilter.Count() <> 1 then
            exit;
        if not ApprovalEntryFilter.FindFirst() then
            exit;
        if ApprovalEntryFilter."Table ID" <> Database::"Purchase Header" then
            exit;
        if ApprovalEntryFilter."Document Type" <> ApprovalEntryFilter."Document Type"::Order then
            exit;
        if ApprovalEntryFilter.Status <> ApprovalEntryFilter.Status::Open then
            exit;

        // Read-only check first so Confirm/RunModal never executes inside an open write transaction.
        HasSummary := TryGetSummaryForApprovalEntry(ApprovalEntryFilter, SummaryRec);
        if HasSummary then
            HasPreviousArchive := SummaryRec."Previous Version No." > 0
        else begin
            if not PurchaseHeader.Get(Enum::"Purchase Document Type"::Order, ApprovalEntryFilter."Document No.") then
                exit;
            HasPreviousArchive := ArchiveHandler.FindLatestArchivedVersion(PurchaseHeader, LatestArchHeader);
        end;

        if not HasPreviousArchive then
            exit;

        if not Confirm(CompareChangesConfirmQst, true) then
            exit;

        if not HasSummary then begin
            if IsNullGuid(ApprovalEntryFilter."Workflow Step Instance ID") then
                exit;
            if not PurchaseHeader.Get(Enum::"Purchase Document Type"::Order, ApprovalEntryFilter."Document No.") then
                exit;
            GenerateChangeSummaryForPurchaseOrder(ApprovalEntryFilter."Workflow Step Instance ID", PurchaseHeader);
            Commit();
            if not SummaryRec.Get(ApprovalEntryFilter."Workflow Step Instance ID") then
                exit;
        end;

        PromptPage.LoadSummaryForApprovalReview(SummaryRec);
        if PromptPage.RunModal() <> Action::OK then
            IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Approvals Mgmt.", 'OnCreateApprovalRequestsOnAfterCreateRequests', '', false, false)]
    local procedure OnCreateApprovalRequestsOnAfterCreateRequests(RecRef: RecordRef; WorkflowStepArgument: Record "Workflow Step Argument"; var ApprovalEntryArgument: Record "Approval Entry")
    var
        PurchaseHeader: Record "Purchase Header";
        SummaryRec: Record "POAI Approval Change Summary";
    begin
        if RecRef.Number() <> Database::"Purchase Header" then
            exit;

        RecRef.SetTable(PurchaseHeader);
        if PurchaseHeader."Document Type" <> PurchaseHeader."Document Type"::Order then
            exit;

        if IsNullGuid(ApprovalEntryArgument."Workflow Step Instance ID") then
            exit;

        // Multiple approvers in a sequence share the same Workflow Step Instance ID; generate once.
        if SummaryRec.Get(ApprovalEntryArgument."Workflow Step Instance ID") then
            exit;

        GenerateChangeSummaryForPurchaseOrder(ApprovalEntryArgument."Workflow Step Instance ID", PurchaseHeader);
    end;

    procedure GenerateChangeSummaryForPurchaseOrder(WorkflowStepInstanceId: Guid; PurchaseHeader: Record "Purchase Header")
    var
        Setup: Record "POAI Copilot Setup";
        BaselineArchHeader: Record "Purchase Header Archive";
        SummaryRec: Record "POAI Approval Change Summary";
        ArchiveHandler: Codeunit "POAI Version Archive Handler";
        DiffEngine: Codeunit "POAI Diff Engine";
        AISummaryHelper: Codeunit "POAI AI Summary Helper";
        HasBaseline: Boolean;
        DiffJsonText: Text;
        ShortSummary: Text[250];
        DetailedAISummary: Text;
    begin
        Setup.GetOrCreateSetup();
        HasBaseline := ArchiveHandler.ResolveBaselineVersion(PurchaseHeader, BaselineArchHeader);

        DiffEngine.ComputeAndStoreDiff(
            WorkflowStepInstanceId, PurchaseHeader, BaselineArchHeader, HasBaseline, SummaryRec);

        if (not HasBaseline) or (not SummaryRec."Has Differences") then
            exit;

        if not AISummaryHelper.IsAIReady(Setup) then
            exit;

        DiffJsonText := SummaryRec.GetDiffPayloadJson();
        if DiffJsonText = '' then
            exit;

        ClearLastError();
        if AISummaryHelper.TryGenerateSummary(DiffJsonText, ShortSummary, DetailedAISummary) then begin
            if ShortSummary <> '' then
                SummaryRec."Grid Summary" := ShortSummary;
            SummaryRec.SetAISummaryText(DetailedAISummary);
            SummaryRec."AI Status" := SummaryRec."AI Status"::Generated;
            SummaryRec."Last Error Message" := '';
        end else begin
            SummaryRec."AI Status" := SummaryRec."AI Status"::Failed;
            SummaryRec."Last Error Message" := CopyStr(GetLastErrorText(), 1, MaxStrLen(SummaryRec."Last Error Message"));
        end;
        SummaryRec."Generated DateTime" := CurrentDateTime();
        SummaryRec.Modify(true);
    end;

    procedure RegenerateAISummary(var SummaryRec: Record "POAI Approval Change Summary"): Boolean
    var
        Setup: Record "POAI Copilot Setup";
        PurchaseHeader: Record "Purchase Header";
        AISummaryHelper: Codeunit "POAI AI Summary Helper";
        DiffJsonText: Text;
        ShortSummary: Text[250];
        DetailedAISummary: Text;
    begin
        if PurchaseHeader.Get(SummaryRec."Document Type", SummaryRec."Document No.") and
           ((SummaryRec.GetDiffPayloadJson() = '') or
            (PurchaseHeader.Status = PurchaseHeader.Status::"Pending Approval") or
            ((PurchaseHeader.Status = PurchaseHeader.Status::Open) and
             (SummaryRec."Workflow Step Instance ID" = PurchaseHeader.SystemId)))
        then begin
            GenerateChangeSummaryForPurchaseOrder(SummaryRec."Workflow Step Instance ID", PurchaseHeader);
            SummaryRec.Get(SummaryRec."Workflow Step Instance ID");
            exit(SummaryRec."AI Status" = SummaryRec."AI Status"::Generated);
        end;

        Setup.GetOrCreateSetup();
        if not AISummaryHelper.IsAIReady(Setup) then
            exit(false);

        DiffJsonText := SummaryRec.GetDiffPayloadJson();
        if DiffJsonText = '' then
            exit(false);

        ClearLastError();
        if AISummaryHelper.TryGenerateSummary(DiffJsonText, ShortSummary, DetailedAISummary) then begin
            if ShortSummary <> '' then
                SummaryRec."Grid Summary" := ShortSummary;
            SummaryRec.SetAISummaryText(DetailedAISummary);
            SummaryRec."AI Status" := SummaryRec."AI Status"::Generated;
            SummaryRec."Last Error Message" := '';
            SummaryRec."Generated DateTime" := CurrentDateTime();
            SummaryRec.Modify(true);
            exit(true);
        end;

        SummaryRec."AI Status" := SummaryRec."AI Status"::Failed;
        SummaryRec."Last Error Message" := CopyStr(GetLastErrorText(), 1, MaxStrLen(SummaryRec."Last Error Message"));
        SummaryRec.Modify(true);
        exit(false);
    end;

    procedure TryGetSummaryForApprovalEntry(ApprovalEntry: Record "Approval Entry"; var SummaryRec: Record "POAI Approval Change Summary"): Boolean
    begin
        if ApprovalEntry."Table ID" <> Database::"Purchase Header" then
            exit(false);
        if ApprovalEntry."Document Type" <> ApprovalEntry."Document Type"::Order then
            exit(false);

        SummaryRec.ReadIsolation := IsolationLevel::ReadUncommitted;
        if not IsNullGuid(ApprovalEntry."Workflow Step Instance ID") then
            if SummaryRec.Get(ApprovalEntry."Workflow Step Instance ID") then
                exit(true);

        exit(false);
    end;
}
