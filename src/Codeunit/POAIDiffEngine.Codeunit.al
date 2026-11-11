namespace DefaultPublisher.POAIApproval;

using Microsoft.Finance.Dimension;
using Microsoft.Purchases.Archive;
using Microsoft.Purchases.Comment;
using Microsoft.Purchases.Document;
using System.Reflection;

codeunit 50102 "POAI Diff Engine"
{
    Access = Public;
    Permissions = tabledata "POAI Copilot Setup" = ri,
                  tabledata "Purchase Header" = r,
                  tabledata "Purchase Line" = r,
                  tabledata "Purch. Comment Line" = r,
                  tabledata "Purchase Header Archive" = r,
                  tabledata "Purchase Line Archive" = r,
                  tabledata "Purch. Comment Line Archive" = r,
                  tabledata "Dimension Set Entry" = r,
                  tabledata "Field" = r,
                  tabledata "POAI Approval Change Summary" = rimd,
                  tabledata "POAI Approval Change Detail" = rimd;

    var
        VersionComparisonLbl: Label 'v%1 vs v%2', Comment = '%1 = New version, %2 = Previous version';
        LineSnapshotLbl: Label '%1 %2 (%3) | Qty: %4 %5 | Cost: %6 | Amt: %7', Comment = '%1 = Type, %2 = No., %3 = Description, %4 = Qty, %5 = UoM, %6 = Unit Cost, %7 = Line Amount';
        NoChangesDetectedLbl: Label 'No changes detected compared to Version %1.', Comment = '%1 = Previous Version No.';
        PctDetailLbl: Label ', %1%2%', Locked = true;
        PctGridLbl: Label ' (%1%2%)', Locked = true;
        SummaryHeaderLineLbl: Label 'Comparison: %1 | Net Amount: %2 -> %3 (%4%5%6)', Comment = '%1 = Version, %2 = Old Amt, %3 = New Amt, %4 = Sign, %5 = Variance, %6 = Percent';
        SummaryCountsLineLbl: Label 'Counts: Header %1 | Lines Added %2 | Modified %3 | Deleted %4', Comment = '%1 = Header, %2 = Added, %3 = Modified, %4 = Deleted';
        DetailLineChangeLbl: Label '- Line %1 (%2) %3: "%4" -> "%5"', Comment = '%1 = Line No., %2 = Item No., %3 = Field, %4 = Old, %5 = New';
        DetailHeaderChangeLbl: Label '- %1: "%2" -> "%3"', Comment = '%1 = Field, %2 = Old, %3 = New';
        MoreChangesLbl: Label '... and %1 more change(s). Open View Detailed Changes to see all.', Comment = '%1 = Count';
        GridNoChangesLbl: Label '%1: No changes detected', Comment = '%1 = Version label';
        GridAmtLbl: Label 'Amt %1%2%3', Comment = '%1 = Sign, %2 = Variance, %3 = Percent';
        GridHeaderCntLbl: Label '%1 header', Comment = '%1 = Count';
        GridAddedCntLbl: Label '%1 added', Comment = '%1 = Count';
        GridModifiedCntLbl: Label '%1 modified', Comment = '%1 = Count';
        GridDeletedCntLbl: Label '%1 deleted', Comment = '%1 = Count';
        GridCommentCntLbl: Label '%1 comment', Comment = '%1 = Count';

    procedure ComputeAndStoreDiff(
        WorkflowStepInstanceId: Guid;
        PurchaseHeader: Record "Purchase Header";
        BaselineArchHeader: Record "Purchase Header Archive";
        HasBaseline: Boolean;
        var SummaryRec: Record "POAI Approval Change Summary")
    var
        Setup: Record "POAI Copilot Setup";
        ChangeDetail: Record "POAI Approval Change Detail";
        LiveHeader: Record "Purchase Header";
        ArchHeader: Record "Purchase Header Archive";
        EntryNo: Integer;
        HeaderChangesCount: Integer;
        LinesAddedCount: Integer;
        LinesModifiedCount: Integer;
        LinesDeletedCount: Integer;
        CommentsChangedCount: Integer;
        RootJson: JsonObject;
        HeaderChangesJson: JsonArray;
        LineChangesJson: JsonArray;
        CommentChangesJson: JsonArray;
        DeterministicText: Text;
        GridSummaryText: Text[250];
        DiffJsonText: Text;
        VersionLabel: Text[50];
    begin
        Setup.GetOrCreateSetup();

        LiveHeader := PurchaseHeader;
        LiveHeader.CalcFields(Amount, "Amount Including VAT");

        // Reset existing details for idempotency
        ChangeDetail.SetRange("Workflow Step Instance ID", WorkflowStepInstanceId);
        if not ChangeDetail.IsEmpty() then
            ChangeDetail.DeleteAll();

        if SummaryRec.Get(WorkflowStepInstanceId) then
            SummaryRec.Delete(true);

        SummaryRec.Init();
        SummaryRec."Workflow Step Instance ID" := WorkflowStepInstanceId;
        SummaryRec."Record ID to Approve" := LiveHeader.RecordId;
        SummaryRec."Document Type" := LiveHeader."Document Type";
        SummaryRec."Document No." := LiveHeader."No.";
        SummaryRec."Doc. No. Occurrence" := LiveHeader."Doc. No. Occurrence";
        SummaryRec."Buy-from Vendor No." := LiveHeader."Buy-from Vendor No.";
        SummaryRec."Buy-from Vendor Name" := LiveHeader."Buy-from Vendor Name";
        SummaryRec."Currency Code" := LiveHeader."Currency Code";
        SummaryRec."New Amount" := LiveHeader.Amount;
        SummaryRec."New Amount Incl. VAT" := LiveHeader."Amount Including VAT";
        SummaryRec."Generated DateTime" := CurrentDateTime();

        if not HasBaseline then begin
            SummaryRec."Previous Version No." := 0;
            SummaryRec."Current Version Label" := 'Version 1 (Initial)';
            SummaryRec."Old Amount" := 0;
            SummaryRec."Old Amount Incl. VAT" := 0;
            SummaryRec."Amount Variance" := LiveHeader.Amount;
            SummaryRec."Has Differences" := false;
            SummaryRec."AI Status" := SummaryRec."AI Status"::"Initial Version";
            SummaryRec."Grid Summary" := 'Initial version (no previous archived version)';
            SummaryRec.SetDeterministicSummaryText('Initial submission for Purchase Order ' + LiveHeader."No." + '. No previous version exists to compare against.');
            SummaryRec.Insert(true);
            exit;
        end;

        ArchHeader := BaselineArchHeader;
        ArchHeader.CalcFields(Amount, "Amount Including VAT");

        VersionLabel := StrSubstNo(VersionComparisonLbl, ArchHeader."Version No." + 1, ArchHeader."Version No.");
        SummaryRec."Previous Version No." := ArchHeader."Version No.";
        SummaryRec."Current Version Label" := VersionLabel;
        SummaryRec."Baseline Date Archived" := ArchHeader."Date Archived";
        SummaryRec."Baseline Archived By" := ArchHeader."Archived By";
        SummaryRec."Old Amount" := ArchHeader.Amount;
        SummaryRec."Old Amount Incl. VAT" := ArchHeader."Amount Including VAT";
        SummaryRec."Amount Variance" := LiveHeader.Amount - ArchHeader.Amount;

        CompareHeaderFields(
            WorkflowStepInstanceId, LiveHeader, ArchHeader, Setup."Include Dimensions in Diff",
            EntryNo, HeaderChangesCount, HeaderChangesJson);

        CompareLines(
            WorkflowStepInstanceId, LiveHeader, ArchHeader, Setup."Include Dimensions in Diff",
            EntryNo, LinesAddedCount, LinesModifiedCount, LinesDeletedCount, LineChangesJson);

        if Setup."Include Comments in Diff" then
            CompareComments(
                WorkflowStepInstanceId, LiveHeader, ArchHeader,
                EntryNo, CommentsChangedCount, CommentChangesJson);

        SummaryRec."Header Changes Count" := HeaderChangesCount;
        SummaryRec."Lines Added Count" := LinesAddedCount;
        SummaryRec."Lines Modified Count" := LinesModifiedCount;
        SummaryRec."Lines Deleted Count" := LinesDeletedCount;
        SummaryRec."Comments Changed Count" := CommentsChangedCount;
        SummaryRec."Has Differences" :=
            (HeaderChangesCount > 0) or (LinesAddedCount > 0) or (LinesModifiedCount > 0) or
            (LinesDeletedCount > 0) or (CommentsChangedCount > 0) or
            (SummaryRec."Amount Variance" <> 0);

        BuildDiffJsonPayload(
            SummaryRec, HeaderChangesJson, LineChangesJson, CommentChangesJson, RootJson);
        RootJson.WriteTo(DiffJsonText);

        DeterministicText := BuildDeterministicSummaryText(WorkflowStepInstanceId, SummaryRec);
        GridSummaryText := BuildDeterministicGridSummary(SummaryRec);

        SummaryRec."Grid Summary" := GridSummaryText;
        SummaryRec."AI Status" := SummaryRec."AI Status"::"Fallback Deterministic";
        SummaryRec.SetDeterministicSummaryText(DeterministicText);
        SummaryRec.SetDiffPayloadJson(DiffJsonText);
        SummaryRec.Insert(true);
    end;

    procedure HasHeaderFieldDifferences(LiveHeader: Record "Purchase Header"; ArchHeader: Record "Purchase Header Archive"; IncludeDimensions: Boolean): Boolean
    var
        LiveRecRef: RecordRef;
        ArchRecRef: RecordRef;
        LiveFldRef: FieldRef;
        ArchFldRef: FieldRef;
        HeaderFieldNos: List of [Integer];
        FieldNo: Integer;
    begin
        LiveRecRef.GetTable(LiveHeader);
        ArchRecRef.GetTable(ArchHeader);
        BuildComparableFieldList(Database::"Purchase Header", LiveRecRef, ArchRecRef, true, HeaderFieldNos);

        foreach FieldNo in HeaderFieldNos do begin
            LiveFldRef := LiveRecRef.Field(FieldNo);
            ArchFldRef := ArchRecRef.Field(FieldNo);
            if not AreFieldValuesEqual(LiveFldRef, ArchFldRef) then
                exit(true);
        end;

        if IncludeDimensions and (ArchHeader."Dimension Set ID" <> LiveHeader."Dimension Set ID") then
            if GetDimensionSummaryText(ArchHeader."Dimension Set ID") <> GetDimensionSummaryText(LiveHeader."Dimension Set ID") then
                exit(true);

        exit(false);
    end;

    procedure HasLinesDifferences(LiveHeader: Record "Purchase Header"; ArchHeader: Record "Purchase Header Archive"; IncludeDimensions: Boolean): Boolean
    var
        LiveLine: Record "Purchase Line";
        ArchLine: Record "Purchase Line Archive";
        LiveRecRef: RecordRef;
        ArchRecRef: RecordRef;
        SampleLiveRecRef: RecordRef;
        SampleArchRecRef: RecordRef;
        LiveFldRef: FieldRef;
        ArchFldRef: FieldRef;
        LineFieldNos: List of [Integer];
        FieldNo: Integer;
    begin
        LiveLine.SetRange("Document Type", LiveHeader."Document Type");
        LiveLine.SetRange("Document No.", LiveHeader."No.");

        ArchLine.SetRange("Document Type", ArchHeader."Document Type");
        ArchLine.SetRange("Document No.", ArchHeader."No.");
        ArchLine.SetRange("Doc. No. Occurrence", ArchHeader."Doc. No. Occurrence");
        ArchLine.SetRange("Version No.", ArchHeader."Version No.");

        if LiveLine.Count() <> ArchLine.Count() then
            exit(true);

        if LiveLine.FindSet() then begin
            SampleLiveRecRef.GetTable(LiveLine);
            SampleArchRecRef.Open(Database::"Purchase Line Archive");
            BuildComparableFieldList(Database::"Purchase Line", SampleLiveRecRef, SampleArchRecRef, false, LineFieldNos);
            SampleArchRecRef.Close();

            repeat
                if not ArchLine.Get(
                    ArchHeader."Document Type", ArchHeader."No.", ArchHeader."Doc. No. Occurrence",
                    ArchHeader."Version No.", LiveLine."Line No.")
                then
                    exit(true);

                LiveRecRef.GetTable(LiveLine);
                ArchRecRef.GetTable(ArchLine);
                foreach FieldNo in LineFieldNos do begin
                    LiveFldRef := LiveRecRef.Field(FieldNo);
                    ArchFldRef := ArchRecRef.Field(FieldNo);
                    if not AreFieldValuesEqual(LiveFldRef, ArchFldRef) then
                        exit(true);
                end;

                if IncludeDimensions and (LiveLine."Dimension Set ID" <> ArchLine."Dimension Set ID") then
                    if GetDimensionSummaryText(ArchLine."Dimension Set ID") <> GetDimensionSummaryText(LiveLine."Dimension Set ID") then
                        exit(true);
            until LiveLine.Next() = 0;
        end;

        exit(false);
    end;

    local procedure CompareHeaderFields(
        WorkflowStepInstanceId: Guid;
        LiveHeader: Record "Purchase Header";
        ArchHeader: Record "Purchase Header Archive";
        IncludeDimensions: Boolean;
        var EntryNo: Integer;
        var HeaderChangesCount: Integer;
        var HeaderChangesJson: JsonArray)
    var
        LiveRecRef: RecordRef;
        ArchRecRef: RecordRef;
        LiveFldRef: FieldRef;
        ArchFldRef: FieldRef;
        HeaderFieldNos: List of [Integer];
        FieldNo: Integer;
        OldDimText: Text;
        NewDimText: Text;
    begin
        LiveRecRef.GetTable(LiveHeader);
        ArchRecRef.GetTable(ArchHeader);
        BuildComparableFieldList(Database::"Purchase Header", LiveRecRef, ArchRecRef, true, HeaderFieldNos);

        foreach FieldNo in HeaderFieldNos do begin
            LiveFldRef := LiveRecRef.Field(FieldNo);
            ArchFldRef := ArchRecRef.Field(FieldNo);
            if not AreFieldValuesEqual(LiveFldRef, ArchFldRef) then
                CheckHeaderField(
                    WorkflowStepInstanceId, LiveFldRef.Caption(),
                    FormatFieldValueForDisplay(ArchFldRef), FormatFieldValueForDisplay(LiveFldRef),
                    EntryNo, HeaderChangesCount, HeaderChangesJson);
        end;

        if IncludeDimensions and (ArchHeader."Dimension Set ID" <> LiveHeader."Dimension Set ID") then begin
            OldDimText := GetDimensionSummaryText(ArchHeader."Dimension Set ID");
            NewDimText := GetDimensionSummaryText(LiveHeader."Dimension Set ID");
            if OldDimText <> NewDimText then
                CheckHeaderField(WorkflowStepInstanceId, 'Header Dimensions', OldDimText, NewDimText, EntryNo, HeaderChangesCount, HeaderChangesJson);
        end;
    end;

    local procedure CheckHeaderField(
        WorkflowStepInstanceId: Guid;
        FieldLabel: Text;
        OldVal: Text;
        NewVal: Text;
        var EntryNo: Integer;
        var HeaderChangesCount: Integer;
        var HeaderChangesJson: JsonArray)
    var
        JObj: JsonObject;
    begin
        if OldVal = NewVal then
            exit;

        HeaderChangesCount += 1;
        InsertDetail(
            WorkflowStepInstanceId, EntryNo, Enum::"POAI Change Type"::"Header Modified",
            0, '', '', FieldLabel, OldVal, NewVal, 0);

        JObj.Add('field', FieldLabel);
        JObj.Add('oldValue', OldVal);
        JObj.Add('newValue', NewVal);
        HeaderChangesJson.Add(JObj);
    end;

    local procedure CompareLines(
        WorkflowStepInstanceId: Guid;
        LiveHeader: Record "Purchase Header";
        ArchHeader: Record "Purchase Header Archive";
        IncludeDimensions: Boolean;
        var EntryNo: Integer;
        var LinesAddedCount: Integer;
        var LinesModifiedCount: Integer;
        var LinesDeletedCount: Integer;
        var LineChangesJson: JsonArray)
    var
        LiveLine: Record "Purchase Line";
        ArchLine: Record "Purchase Line Archive";
        LiveRecRef: RecordRef;
        ArchRecRef: RecordRef;
        SampleLiveRecRef: RecordRef;
        SampleArchRecRef: RecordRef;
        LiveFldRef: FieldRef;
        ArchFldRef: FieldRef;
        LineFieldNos: List of [Integer];
        FieldNo: Integer;
        LineAmountFieldNo: Integer;
        FieldAmountImpact: Decimal;
        LineDelta: Decimal;
        LineChanged: Boolean;
        FieldArray: JsonArray;
        LineJson: JsonObject;
        OldLineSummary: Text;
        NewLineSummary: Text;
        OldDimText: Text;
        NewDimText: Text;
    begin
        // Check Added and Modified lines
        LiveLine.SetRange("Document Type", LiveHeader."Document Type");
        LiveLine.SetRange("Document No.", LiveHeader."No.");
        if LiveLine.FindSet() then begin
            SampleLiveRecRef.GetTable(LiveLine);
            SampleArchRecRef.Open(Database::"Purchase Line Archive");
            BuildComparableFieldList(Database::"Purchase Line", SampleLiveRecRef, SampleArchRecRef, false, LineFieldNos);
            SampleArchRecRef.Close();
            LineAmountFieldNo := LiveLine.FieldNo("Line Amount");

            repeat
                if not ArchLine.Get(
                    ArchHeader."Document Type", ArchHeader."No.", ArchHeader."Doc. No. Occurrence",
                    ArchHeader."Version No.", LiveLine."Line No.")
                then begin
                    LinesAddedCount += 1;
                    NewLineSummary := FormatLineSnapshot(LiveLine.Type, LiveLine."No.", LiveLine.Description, LiveLine.Quantity, LiveLine."Unit of Measure Code", LiveLine."Direct Unit Cost", LiveLine."Line Amount");
                    InsertDetail(
                        WorkflowStepInstanceId, EntryNo, Enum::"POAI Change Type"::"Line Added",
                        LiveLine."Line No.", LiveLine."No.", LiveLine.Description,
                        'Line Added', '(Not present)', NewLineSummary, LiveLine."Line Amount");

                    Clear(LineJson);
                    LineJson.Add('changeType', 'Line Added');
                    LineJson.Add('lineNo', LiveLine."Line No.");
                    LineJson.Add('type', Format(LiveLine.Type));
                    LineJson.Add('no', LiveLine."No.");
                    LineJson.Add('description', LiveLine.Description);
                    LineJson.Add('quantity', LiveLine.Quantity);
                    LineJson.Add('unitCost', LiveLine."Direct Unit Cost");
                    LineJson.Add('lineAmount', LiveLine."Line Amount");
                    LineJson.Add('amountImpact', LiveLine."Line Amount");
                    LineChangesJson.Add(LineJson);
                end else begin
                    LineChanged := false;
                    Clear(FieldArray);
                    LineDelta := LiveLine."Line Amount" - ArchLine."Line Amount";
                    LiveRecRef.GetTable(LiveLine);
                    ArchRecRef.GetTable(ArchLine);

                    foreach FieldNo in LineFieldNos do begin
                        LiveFldRef := LiveRecRef.Field(FieldNo);
                        ArchFldRef := ArchRecRef.Field(FieldNo);
                        if not AreFieldValuesEqual(LiveFldRef, ArchFldRef) then begin
                            if FieldNo = LineAmountFieldNo then
                                FieldAmountImpact := LineDelta
                            else
                                FieldAmountImpact := 0;

                            RecordLineFieldChange(
                                WorkflowStepInstanceId, LiveLine."Line No.", LiveLine."No.", LiveLine.Description,
                                LiveFldRef.Caption(), FormatFieldValueForDisplay(ArchFldRef), FormatFieldValueForDisplay(LiveFldRef),
                                FieldAmountImpact, EntryNo, LineChanged, FieldArray);
                        end;
                    end;

                    if IncludeDimensions and (LiveLine."Dimension Set ID" <> ArchLine."Dimension Set ID") then begin
                        OldDimText := GetDimensionSummaryText(ArchLine."Dimension Set ID");
                        NewDimText := GetDimensionSummaryText(LiveLine."Dimension Set ID");
                        if OldDimText <> NewDimText then
                            RecordLineFieldChange(WorkflowStepInstanceId, LiveLine."Line No.", LiveLine."No.", LiveLine.Description, 'Line Dimensions', OldDimText, NewDimText, 0, EntryNo, LineChanged, FieldArray);
                    end;

                    if LineChanged then begin
                        LinesModifiedCount += 1;
                        Clear(LineJson);
                        LineJson.Add('changeType', 'Line Modified');
                        LineJson.Add('lineNo', LiveLine."Line No.");
                        LineJson.Add('no', LiveLine."No.");
                        LineJson.Add('description', LiveLine.Description);
                        LineJson.Add('amountImpact', LineDelta);
                        LineJson.Add('fieldChanges', FieldArray);
                        LineChangesJson.Add(LineJson);
                    end;
                end;
            until LiveLine.Next() = 0;
        end;

        // Check Deleted lines
        ArchLine.SetRange("Document Type", ArchHeader."Document Type");
        ArchLine.SetRange("Document No.", ArchHeader."No.");
        ArchLine.SetRange("Doc. No. Occurrence", ArchHeader."Doc. No. Occurrence");
        ArchLine.SetRange("Version No.", ArchHeader."Version No.");
        if ArchLine.FindSet() then
            repeat
                if not LiveLine.Get(ArchLine."Document Type", ArchLine."Document No.", ArchLine."Line No.") then begin
                    LinesDeletedCount += 1;
                    OldLineSummary := FormatLineSnapshot(ArchLine.Type, ArchLine."No.", ArchLine.Description, ArchLine.Quantity, ArchLine."Unit of Measure Code", ArchLine."Direct Unit Cost", ArchLine."Line Amount");
                    InsertDetail(
                        WorkflowStepInstanceId, EntryNo, Enum::"POAI Change Type"::"Line Deleted",
                        ArchLine."Line No.", ArchLine."No.", ArchLine.Description,
                        'Line Deleted', OldLineSummary, '(Deleted)', -ArchLine."Line Amount");

                    Clear(LineJson);
                    LineJson.Add('changeType', 'Line Deleted');
                    LineJson.Add('lineNo', ArchLine."Line No.");
                    LineJson.Add('type', Format(ArchLine.Type));
                    LineJson.Add('no', ArchLine."No.");
                    LineJson.Add('description', ArchLine.Description);
                    LineJson.Add('oldQuantity', ArchLine.Quantity);
                    LineJson.Add('oldUnitCost', ArchLine."Direct Unit Cost");
                    LineJson.Add('oldLineAmount', ArchLine."Line Amount");
                    LineJson.Add('amountImpact', -ArchLine."Line Amount");
                    LineChangesJson.Add(LineJson);
                end;
            until ArchLine.Next() = 0;
    end;

    local procedure BuildComparableFieldList(
        LiveTableNo: Integer;
        var LiveRecRef: RecordRef;
        var ArchRecRef: RecordRef;
        IsHeader: Boolean;
        var FieldNos: List of [Integer])
    var
        FieldRec: Record "Field";
        ArchFieldRec: Record "Field";
        LiveFldRef: FieldRef;
        ArchFldRef: FieldRef;
    begin
        Clear(FieldNos);
        FieldRec.SetRange(TableNo, LiveTableNo);
        FieldRec.SetFilter("No.", '%1..%2', 1, 1999999999);
        FieldRec.SetRange(Class, FieldRec.Class::Normal);
        FieldRec.SetRange(Enabled, true);
        FieldRec.SetFilter(ObsoleteState, '<>%1', FieldRec.ObsoleteState::Removed);
        if FieldRec.FindSet() then
            repeat
                if IsComparableFieldCandidate(FieldRec, LiveRecRef, ArchRecRef, IsHeader) then
                    if ArchFieldRec.Get(ArchRecRef.Number(), FieldRec."No.") then
                        if ArchFieldRec.Enabled and
                           (ArchFieldRec.ObsoleteState <> ArchFieldRec.ObsoleteState::Removed) and
                           (ArchFieldRec."Type Name" = FieldRec."Type Name")
                        then begin
                            LiveFldRef := LiveRecRef.Field(FieldRec."No.");
                            ArchFldRef := ArchRecRef.Field(FieldRec."No.");
                            if (ArchFldRef.Class() = FieldClass::Normal) and (LiveFldRef.Type() = ArchFldRef.Type()) then
                                FieldNos.Add(FieldRec."No.");
                        end;
            until FieldRec.Next() = 0;
    end;

    local procedure IsComparableFieldCandidate(
        FieldRec: Record "Field";
        var LiveRecRef: RecordRef;
        var ArchRecRef: RecordRef;
        IsHeader: Boolean): Boolean
    begin
        if FieldRec.IsPartOfPrimaryKey then
            exit(false);

        if FieldRec.Type in [
            FieldRec.Type::BLOB,
            FieldRec.Type::Binary,
            FieldRec.Type::Media,
            FieldRec.Type::MediaSet,
            FieldRec.Type::TableFilter]
        then
            exit(false);

        if IsExcludedField(FieldRec."No.", IsHeader, LiveRecRef) then
            exit(false);

        exit(ArchRecRef.FieldExist(FieldRec."No."));
    end;

    local procedure IsExcludedField(FieldNo: Integer; IsHeader: Boolean; var LiveRecRef: RecordRef): Boolean
    var
        PurchHeader: Record "Purchase Header";
        PurchLine: Record "Purchase Line";
    begin
        if (FieldNo <= 0) or (FieldNo >= 2000000000) then
            exit(true);

        if FieldNo in [
            LiveRecRef.SystemIdNo(),
            LiveRecRef.SystemCreatedAtNo(),
            LiveRecRef.SystemCreatedByNo(),
            LiveRecRef.SystemModifiedAtNo(),
            LiveRecRef.SystemModifiedByNo()]
        then
            exit(true);

        if IsHeader then
            exit(FieldNo in [
                PurchHeader.FieldNo("Document Type"),
                PurchHeader.FieldNo("No."),
                PurchHeader.FieldNo(Status),
                PurchHeader.FieldNo("Dimension Set ID"),
                5043, // No. of Archived Versions / Interaction Exist
                5044, // Time Archived
                5045, // Date Archived
                5046, // Archived By
                5047, // Version No.
                PurchHeader.FieldNo("Doc. No. Occurrence")]);

        exit(FieldNo in [
            PurchLine.FieldNo("Document Type"),
            PurchLine.FieldNo("Document No."),
            PurchLine.FieldNo("Line No."),
            PurchLine.FieldNo("Dimension Set ID"),
            5047, // Version No.
            5048]); // Doc. No. Occurrence
    end;

    local procedure AreFieldValuesEqual(LiveFldRef: FieldRef; ArchFldRef: FieldRef): Boolean
    var
        Int1: Integer;
        Int2: Integer;
        Big1: BigInteger;
        Big2: BigInteger;
        Dec1: Decimal;
        Dec2: Decimal;
        Bool1: Boolean;
        Bool2: Boolean;
        Date1: Date;
        Date2: Date;
        Time1: Time;
        Time2: Time;
        Dt1: DateTime;
        Dt2: DateTime;
        Dur1: Duration;
        Dur2: Duration;
        Guid1: Guid;
        Guid2: Guid;
        Txt1: Text;
        Txt2: Text;
    begin
        case LiveFldRef.Type() of
            FieldType::Text, FieldType::Code:
                begin
                    Txt1 := Format(LiveFldRef.Value());
                    Txt2 := Format(ArchFldRef.Value());
                    exit(Txt1 = Txt2);
                end;
            FieldType::Integer:
                begin
                    Int1 := LiveFldRef.Value();
                    Int2 := ArchFldRef.Value();
                    exit(Int1 = Int2);
                end;
            FieldType::BigInteger:
                begin
                    Big1 := LiveFldRef.Value();
                    Big2 := ArchFldRef.Value();
                    exit(Big1 = Big2);
                end;
            FieldType::Decimal:
                begin
                    Dec1 := LiveFldRef.Value();
                    Dec2 := ArchFldRef.Value();
                    exit(Dec1 = Dec2);
                end;
            FieldType::Boolean:
                begin
                    Bool1 := LiveFldRef.Value();
                    Bool2 := ArchFldRef.Value();
                    exit(Bool1 = Bool2);
                end;
            FieldType::Date:
                begin
                    Date1 := LiveFldRef.Value();
                    Date2 := ArchFldRef.Value();
                    exit(Date1 = Date2);
                end;
            FieldType::Time:
                begin
                    Time1 := LiveFldRef.Value();
                    Time2 := ArchFldRef.Value();
                    exit(Time1 = Time2);
                end;
            FieldType::DateTime:
                begin
                    Dt1 := LiveFldRef.Value();
                    Dt2 := ArchFldRef.Value();
                    exit(Dt1 = Dt2);
                end;
            FieldType::Duration:
                begin
                    Dur1 := LiveFldRef.Value();
                    Dur2 := ArchFldRef.Value();
                    exit(Dur1 = Dur2);
                end;
            FieldType::GUID:
                begin
                    Guid1 := LiveFldRef.Value();
                    Guid2 := ArchFldRef.Value();
                    exit(Guid1 = Guid2);
                end;
            FieldType::Option, FieldType::DateFormula, FieldType::RecordID:
                exit(Format(LiveFldRef.Value(), 0, 9) = Format(ArchFldRef.Value(), 0, 9));
            else
                exit(LiveFldRef.Value() = ArchFldRef.Value());
        end;
    end;

    local procedure FormatFieldValueForDisplay(FldRef: FieldRef): Text
    begin
        exit(Format(FldRef.Value()));
    end;

    local procedure RecordLineFieldChange(
        WorkflowStepInstanceId: Guid;
        LineNo: Integer;
        ItemNo: Code[20];
        LineDesc: Text[100];
        FieldLabel: Text;
        OldVal: Text;
        NewVal: Text;
        AmountImpact: Decimal;
        var EntryNo: Integer;
        var LineChanged: Boolean;
        var FieldArray: JsonArray)
    var
        FieldObj: JsonObject;
    begin
        LineChanged := true;
        InsertDetail(
            WorkflowStepInstanceId, EntryNo, Enum::"POAI Change Type"::"Line Modified",
            LineNo, ItemNo, LineDesc, FieldLabel, OldVal, NewVal, AmountImpact);

        FieldObj.Add('field', FieldLabel);
        FieldObj.Add('oldValue', OldVal);
        FieldObj.Add('newValue', NewVal);
        FieldArray.Add(FieldObj);
    end;

    local procedure CompareComments(
        WorkflowStepInstanceId: Guid;
        LiveHeader: Record "Purchase Header";
        ArchHeader: Record "Purchase Header Archive";
        var EntryNo: Integer;
        var CommentsChangedCount: Integer;
        var CommentChangesJson: JsonArray)
    var
        LiveComment: Record "Purch. Comment Line";
        ArchComment: Record "Purch. Comment Line Archive";
        CommentObj: JsonObject;
        CommentType: Enum "Purchase Comment Document Type";
    begin
        CommentType := Enum::"Purchase Comment Document Type"::Order;

        LiveComment.SetRange("Document Type", CommentType);
        LiveComment.SetRange("No.", LiveHeader."No.");
        if LiveComment.FindSet() then
            repeat
                if not ArchComment.Get(
                    CommentType, LiveComment."No.", ArchHeader."Doc. No. Occurrence", ArchHeader."Version No.",
                    LiveComment."Document Line No.", LiveComment."Line No.")
                then begin
                    CommentsChangedCount += 1;
                    InsertDetail(
                        WorkflowStepInstanceId, EntryNo, Enum::"POAI Change Type"::"Comment Changed",
                        LiveComment."Document Line No.", '', '', 'Comment Added', '', LiveComment.Comment, 0);
                    Clear(CommentObj);
                    CommentObj.Add('action', 'Added');
                    CommentObj.Add('documentLineNo', LiveComment."Document Line No.");
                    CommentObj.Add('comment', LiveComment.Comment);
                    CommentChangesJson.Add(CommentObj);
                end else
                    if LiveComment.Comment <> ArchComment.Comment then begin
                        CommentsChangedCount += 1;
                        InsertDetail(
                            WorkflowStepInstanceId, EntryNo, Enum::"POAI Change Type"::"Comment Changed",
                            LiveComment."Document Line No.", '', '', 'Comment Modified', ArchComment.Comment, LiveComment.Comment, 0);
                        Clear(CommentObj);
                        CommentObj.Add('action', 'Modified');
                        CommentObj.Add('documentLineNo', LiveComment."Document Line No.");
                        CommentObj.Add('oldComment', ArchComment.Comment);
                        CommentObj.Add('newComment', LiveComment.Comment);
                        CommentChangesJson.Add(CommentObj);
                    end;
            until LiveComment.Next() = 0;

        ArchComment.SetRange("Document Type", CommentType);
        ArchComment.SetRange("No.", ArchHeader."No.");
        ArchComment.SetRange("Doc. No. Occurrence", ArchHeader."Doc. No. Occurrence");
        ArchComment.SetRange("Version No.", ArchHeader."Version No.");
        if ArchComment.FindSet() then
            repeat
                if not LiveComment.Get(CommentType, ArchComment."No.", ArchComment."Document Line No.", ArchComment."Line No.") then begin
                    CommentsChangedCount += 1;
                    InsertDetail(
                        WorkflowStepInstanceId, EntryNo, Enum::"POAI Change Type"::"Comment Changed",
                        ArchComment."Document Line No.", '', '', 'Comment Deleted', ArchComment.Comment, '', 0);
                    Clear(CommentObj);
                    CommentObj.Add('action', 'Deleted');
                    CommentObj.Add('documentLineNo', ArchComment."Document Line No.");
                    CommentObj.Add('comment', ArchComment.Comment);
                    CommentChangesJson.Add(CommentObj);
                end;
            until ArchComment.Next() = 0;
    end;

    local procedure InsertDetail(
        WorkflowStepInstanceId: Guid;
        var EntryNo: Integer;
        ChangeType: Enum "POAI Change Type";
        LineNo: Integer;
        ItemNo: Code[20];
        LineDesc: Text[100];
        FieldLabel: Text;
        OldVal: Text;
        NewVal: Text;
        AmountImpact: Decimal)
    var
        ChangeDetail: Record "POAI Approval Change Detail";
    begin
        EntryNo += 1;
        ChangeDetail.Init();
        ChangeDetail."Workflow Step Instance ID" := WorkflowStepInstanceId;
        ChangeDetail."Entry No." := EntryNo;
        ChangeDetail."Change Type" := ChangeType;
        ChangeDetail."Line No." := LineNo;
        ChangeDetail."Item / Account No." := ItemNo;
        ChangeDetail."Line Description" := LineDesc;
        ChangeDetail."Field Caption" := CopyStr(FieldLabel, 1, MaxStrLen(ChangeDetail."Field Caption"));
        ChangeDetail."Old Value" := CopyStr(OldVal, 1, MaxStrLen(ChangeDetail."Old Value"));
        ChangeDetail."New Value" := CopyStr(NewVal, 1, MaxStrLen(ChangeDetail."New Value"));
        ChangeDetail."Amount Impact" := AmountImpact;
        ChangeDetail.Insert(true);
    end;

    local procedure FormatLineSnapshot(
        LineType: Enum "Purchase Line Type";
        NoCode: Code[20];
        Desc: Text[100];
        Qty: Decimal;
        UoM: Code[10];
        UnitCost: Decimal;
        LineAmt: Decimal): Text
    begin
        exit(StrSubstNo(LineSnapshotLbl, LineType, NoCode, Desc, Qty, UoM, UnitCost, LineAmt));
    end;

    local procedure GetDimensionSummaryText(DimSetId: Integer): Text
    var
        DimSetEntry: Record "Dimension Set Entry";
        Builder: TextBuilder;
    begin
        if DimSetId = 0 then
            exit('');
        DimSetEntry.SetRange("Dimension Set ID", DimSetId);
        if DimSetEntry.FindSet() then
            repeat
                if Builder.Length > 0 then
                    Builder.Append(', ');
                Builder.Append(DimSetEntry."Dimension Code");
                Builder.Append('=');
                Builder.Append(DimSetEntry."Dimension Value Code");
            until DimSetEntry.Next() = 0;
        exit(Builder.ToText());
    end;

    local procedure BuildDiffJsonPayload(
        SummaryRec: Record "POAI Approval Change Summary";
        HeaderChangesJson: JsonArray;
        LineChangesJson: JsonArray;
        CommentChangesJson: JsonArray;
        var RootJson: JsonObject)
    var
        TotalsJson: JsonObject;
        CountsJson: JsonObject;
        PercentChange: Decimal;
    begin
        RootJson.Add('documentNo', SummaryRec."Document No.");
        RootJson.Add('vendorNo', SummaryRec."Buy-from Vendor No.");
        RootJson.Add('vendorName', SummaryRec."Buy-from Vendor Name");
        RootJson.Add('currencyCode', SummaryRec."Currency Code");
        RootJson.Add('previousVersionNo', SummaryRec."Previous Version No.");
        RootJson.Add('versionComparison', SummaryRec."Current Version Label");

        if SummaryRec."Old Amount" <> 0 then
            PercentChange := Round((SummaryRec."Amount Variance" / SummaryRec."Old Amount") * 100, 0.01);

        TotalsJson.Add('oldAmount', SummaryRec."Old Amount");
        TotalsJson.Add('newAmount', SummaryRec."New Amount");
        TotalsJson.Add('variance', SummaryRec."Amount Variance");
        TotalsJson.Add('percentChange', PercentChange);
        TotalsJson.Add('oldAmountInclVat', SummaryRec."Old Amount Incl. VAT");
        TotalsJson.Add('newAmountInclVat', SummaryRec."New Amount Incl. VAT");
        RootJson.Add('totals', TotalsJson);

        CountsJson.Add('headerFieldsChanged', SummaryRec."Header Changes Count");
        CountsJson.Add('linesAdded', SummaryRec."Lines Added Count");
        CountsJson.Add('linesModified', SummaryRec."Lines Modified Count");
        CountsJson.Add('linesDeleted', SummaryRec."Lines Deleted Count");
        CountsJson.Add('commentsChanged', SummaryRec."Comments Changed Count");
        RootJson.Add('counts', CountsJson);

        RootJson.Add('headerChanges', HeaderChangesJson);
        RootJson.Add('lineChanges', LineChangesJson);
        RootJson.Add('commentChanges', CommentChangesJson);
    end;

    procedure BuildDeterministicSummaryText(WorkflowStepInstanceId: Guid; SummaryRec: Record "POAI Approval Change Summary"): Text
    var
        ChangeDetail: Record "POAI Approval Change Detail";
        Builder: TextBuilder;
        PctText: Text;
        SignPrefix: Text;
        MaxDetails: Integer;
        ShownCount: Integer;
    begin
        if not SummaryRec."Has Differences" then
            exit(StrSubstNo(NoChangesDetectedLbl, SummaryRec."Previous Version No."));

        if SummaryRec."Amount Variance" > 0 then
            SignPrefix := '+';
        if SummaryRec."Old Amount" <> 0 then
            PctText := StrSubstNo(PctDetailLbl, SignPrefix, Round((SummaryRec."Amount Variance" / SummaryRec."Old Amount") * 100, 0.1));

        Builder.AppendLine(StrSubstNo(SummaryHeaderLineLbl,
            SummaryRec."Current Version Label",
            Format(SummaryRec."Old Amount", 0, '<Precision,2:2><Standard Format,0>'),
            Format(SummaryRec."New Amount", 0, '<Precision,2:2><Standard Format,0>'),
            SignPrefix,
            Format(SummaryRec."Amount Variance", 0, '<Precision,2:2><Standard Format,0>'),
            PctText));

        Builder.AppendLine(StrSubstNo(SummaryCountsLineLbl,
            SummaryRec."Header Changes Count",
            SummaryRec."Lines Added Count",
            SummaryRec."Lines Modified Count",
            SummaryRec."Lines Deleted Count"));

        MaxDetails := 15;
        ChangeDetail.SetRange("Workflow Step Instance ID", WorkflowStepInstanceId);
        if ChangeDetail.FindSet() then begin
            Builder.AppendLine('Key Changes:');
            repeat
                ShownCount += 1;
                if ShownCount <= MaxDetails then
                    if ChangeDetail."Line No." > 0 then
                        Builder.AppendLine(StrSubstNo(DetailLineChangeLbl,
                            ChangeDetail."Line No.", ChangeDetail."Item / Account No.", ChangeDetail."Field Caption",
                            ChangeDetail."Old Value", ChangeDetail."New Value"))
                    else
                        Builder.AppendLine(StrSubstNo(DetailHeaderChangeLbl,
                            ChangeDetail."Field Caption", ChangeDetail."Old Value", ChangeDetail."New Value"));
            until ChangeDetail.Next() = 0;

            if ShownCount > MaxDetails then
                Builder.AppendLine(StrSubstNo(MoreChangesLbl, ShownCount - MaxDetails));
        end;

        exit(Builder.ToText());
    end;

    procedure BuildDeterministicGridSummary(SummaryRec: Record "POAI Approval Change Summary"): Text[250]
    var
        Parts: TextBuilder;
        SignPrefix: Text;
        PctText: Text;
    begin
        if not SummaryRec."Has Differences" then
            exit(CopyStr(StrSubstNo(GridNoChangesLbl, SummaryRec."Current Version Label"), 1, 250));

        if SummaryRec."Amount Variance" <> 0 then begin
            if SummaryRec."Amount Variance" > 0 then
                SignPrefix := '+';
            if SummaryRec."Old Amount" <> 0 then
                PctText := StrSubstNo(PctGridLbl, SignPrefix, Round((SummaryRec."Amount Variance" / SummaryRec."Old Amount") * 100, 0.1));
            Parts.Append(StrSubstNo(GridAmtLbl, SignPrefix, Format(SummaryRec."Amount Variance", 0, '<Precision,2:2><Standard Format,0>'), PctText));
        end;

        if SummaryRec."Header Changes Count" > 0 then begin
            if Parts.Length > 0 then
                Parts.Append(' | ');
            Parts.Append(StrSubstNo(GridHeaderCntLbl, SummaryRec."Header Changes Count"));
        end;
        if SummaryRec."Lines Added Count" > 0 then begin
            if Parts.Length > 0 then
                Parts.Append(' | ');
            Parts.Append(StrSubstNo(GridAddedCntLbl, SummaryRec."Lines Added Count"));
        end;
        if SummaryRec."Lines Modified Count" > 0 then begin
            if Parts.Length > 0 then
                Parts.Append(' | ');
            Parts.Append(StrSubstNo(GridModifiedCntLbl, SummaryRec."Lines Modified Count"));
        end;
        if SummaryRec."Lines Deleted Count" > 0 then begin
            if Parts.Length > 0 then
                Parts.Append(' | ');
            Parts.Append(StrSubstNo(GridDeletedCntLbl, SummaryRec."Lines Deleted Count"));
        end;
        if SummaryRec."Comments Changed Count" > 0 then begin
            if Parts.Length > 0 then
                Parts.Append(' | ');
            Parts.Append(StrSubstNo(GridCommentCntLbl, SummaryRec."Comments Changed Count"));
        end;

        exit(CopyStr(Parts.ToText(), 1, 250));
    end;
}
