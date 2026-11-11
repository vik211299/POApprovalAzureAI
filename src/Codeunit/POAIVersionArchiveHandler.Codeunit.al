namespace DefaultPublisher.POAIApproval;

using Microsoft.Purchases.Archive;
using Microsoft.Purchases.Comment;
using Microsoft.Purchases.Document;
using Microsoft.Utilities;
using System.Automation;

codeunit 50101 "POAI Version Archive Handler"
{
    Access = Public;
    Permissions = tabledata "POAI Copilot Setup" = ri,
                  tabledata "Purchase Header" = r,
                  tabledata "Purchase Line" = r,
                  tabledata "Purch. Comment Line" = r,
                  tabledata "Purchase Header Archive" = r,
                  tabledata "Purchase Line Archive" = r,
                  tabledata "Purch. Comment Line Archive" = r,
                  tabledata "Approval Entry" = r;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Release Purchase Document", 'OnAfterReleasePurchaseDoc', '', false, false)]
    local procedure OnAfterReleasePurchaseDoc(var PurchaseHeader: Record "Purchase Header"; PreviewMode: Boolean; var LinesWereModified: Boolean; SkipWhseRequestOperations: Boolean)
    var
        Setup: Record "POAI Copilot Setup";
        LatestArchHeader: Record "Purchase Header Archive";
        ArchiveManagement: Codeunit ArchiveManagement;
    begin
        if PreviewMode then
            exit;
        if PurchaseHeader."Document Type" <> PurchaseHeader."Document Type"::Order then
            exit;
        if PurchaseHeader.Status <> PurchaseHeader.Status::Released then
            exit;

        Setup.GetOrCreateSetup();
        if Setup."Auto-Archive Policy" = Setup."Auto-Archive Policy"::Disabled then
            exit;

        if Setup."Auto-Archive Policy" = Setup."Auto-Archive Policy"::"On Approval Release" then
            if not WasReleasedViaApproval(PurchaseHeader) then
                exit;

        if FindLatestArchivedVersion(PurchaseHeader, LatestArchHeader) then
            if not HasDifferencesFromArchive(PurchaseHeader, LatestArchHeader, Setup."Include Comments in Diff", Setup."Include Dimensions in Diff") then
                exit;

        ArchiveManagement.StorePurchDocument(PurchaseHeader, false);
    end;

    procedure ResolveBaselineVersion(PurchaseHeader: Record "Purchase Header"; var BaselineArchHeader: Record "Purchase Header Archive"): Boolean
    var
        Setup: Record "POAI Copilot Setup";
        LatestArchHeader: Record "Purchase Header Archive";
        PrevArchHeader: Record "Purchase Header Archive";
    begin
        Setup.GetOrCreateSetup();
        if not FindLatestArchivedVersion(PurchaseHeader, LatestArchHeader) then
            exit(false);

        if HasDifferencesFromArchive(PurchaseHeader, LatestArchHeader, Setup."Include Comments in Diff", Setup."Include Dimensions in Diff") then begin
            BaselineArchHeader := LatestArchHeader;
            exit(true);
        end;

        // If the user manually archived the current version right before sending for approval,
        // compare against the version immediately preceding it when available.
        if LatestArchHeader."Version No." > 1 then begin
            PrevArchHeader.SetRange("Document Type", PurchaseHeader."Document Type");
            PrevArchHeader.SetRange("No.", PurchaseHeader."No.");
            PrevArchHeader.SetRange("Doc. No. Occurrence", PurchaseHeader."Doc. No. Occurrence");
            PrevArchHeader.SetFilter("Version No.", '<%1', LatestArchHeader."Version No.");
            if PrevArchHeader.FindLast() then begin
                BaselineArchHeader := PrevArchHeader;
                exit(true);
            end;
        end;

        BaselineArchHeader := LatestArchHeader;
        exit(true);
    end;

    procedure FindLatestArchivedVersion(PurchaseHeader: Record "Purchase Header"; var ArchHeader: Record "Purchase Header Archive"): Boolean
    begin
        ArchHeader.Reset();
        ArchHeader.SetRange("Document Type", PurchaseHeader."Document Type");
        ArchHeader.SetRange("No.", PurchaseHeader."No.");
        ArchHeader.SetRange("Doc. No. Occurrence", PurchaseHeader."Doc. No. Occurrence");
        exit(ArchHeader.FindLast());
    end;

    procedure HasDifferencesFromArchive(PurchaseHeader: Record "Purchase Header"; ArchHeader: Record "Purchase Header Archive"; CheckComments: Boolean; CheckDimensions: Boolean): Boolean
    var
        PurchComment: Record "Purch. Comment Line";
        PurchCommentArch: Record "Purch. Comment Line Archive";
        DiffEngine: Codeunit "POAI Diff Engine";
    begin
        if DiffEngine.HasHeaderFieldDifferences(PurchaseHeader, ArchHeader, CheckDimensions) then
            exit(true);

        if DiffEngine.HasLinesDifferences(PurchaseHeader, ArchHeader, CheckDimensions) then
            exit(true);

        if CheckComments then begin
            PurchComment.SetRange("Document Type", Enum::"Purchase Comment Document Type"::Order);
            PurchComment.SetRange("No.", PurchaseHeader."No.");

            PurchCommentArch.SetRange("Document Type", Enum::"Purchase Comment Document Type"::Order);
            PurchCommentArch.SetRange("No.", ArchHeader."No.");
            PurchCommentArch.SetRange("Doc. No. Occurrence", ArchHeader."Doc. No. Occurrence");
            PurchCommentArch.SetRange("Version No.", ArchHeader."Version No.");

            if PurchComment.Count() <> PurchCommentArch.Count() then
                exit(true);

            if PurchComment.FindSet() then
                repeat
                    if not PurchCommentArch.Get(
                        PurchComment."Document Type", PurchComment."No.",
                        ArchHeader."Doc. No. Occurrence", ArchHeader."Version No.",
                        PurchComment."Document Line No.", PurchComment."Line No.")
                    then
                        exit(true);

                    if (PurchComment.Comment <> PurchCommentArch.Comment) or
                       (PurchComment.Code <> PurchCommentArch.Code)
                    then
                        exit(true);
                until PurchComment.Next() = 0;
        end;

        exit(false);
    end;

    local procedure WasReleasedViaApproval(PurchaseHeader: Record "Purchase Header"): Boolean
    var
        ApprovalEntry: Record "Approval Entry";
        ArchHeader: Record "Purchase Header Archive";
        LatestArchCreatedAt: DateTime;
    begin
        ApprovalEntry.SetRange("Record ID to Approve", PurchaseHeader.RecordId);
        ApprovalEntry.SetRange(Status, ApprovalEntry.Status::Approved);
        if not ApprovalEntry.FindLast() then
            exit(false);

        if FindLatestArchivedVersion(PurchaseHeader, ArchHeader) then begin
            LatestArchCreatedAt := ArchHeader.SystemCreatedAt;
            if (LatestArchCreatedAt <> 0DT) and (ApprovalEntry."Last Date-Time Modified" <= LatestArchCreatedAt) then
                exit(false);
        end;

        exit(true);
    end;
}

