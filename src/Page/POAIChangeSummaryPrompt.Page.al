namespace DefaultPublisher.POAIApproval;

page 50103 "POAI Change Summary Prompt"
{
    ApplicationArea = All;
    Caption = 'Ask Copilot About PO Changes';
    DataCaptionExpression = DialogCaption;
    Extensible = false;
    IsPreview = true;
    PageType = PromptDialog;
    PromptMode = Prompt;

    layout
    {
        area(Prompt)
        {
            field(DocumentContext; DocumentContextTxt)
            {
                ApplicationArea = All;
                Editable = false;
                ShowCaption = false;
                ToolTip = 'Displays the Purchase Order and version comparison currently analyzed.';
            }
            field(UserQuestion; UserQuestion)
            {
                ApplicationArea = All;
                Caption = 'Ask a question about these PO changes';
                InstructionalText = 'Example: "Why did the total amount increase?" or "List all unit cost, quantity, or delivery date changes."';
                MultiLine = true;
                ToolTip = 'Enter a question about the differences between the previous archived version and this Purchase Order revision.';
            }
        }

        area(Content)
        {
            group(OverviewGroup)
            {
                Caption = 'Comparison Context';

                field(DocumentNoField; DocumentNoTxt)
                {
                    ApplicationArea = All;
                    Caption = 'Purchase Order No.';
                    Editable = false;
                    ToolTip = 'Specifies the Purchase Order number.';
                }
                field(VersionLabelField; VersionLabelTxt)
                {
                    ApplicationArea = All;
                    Caption = 'Version Comparison';
                    Editable = false;
                    ToolTip = 'Specifies the version comparison context.';
                }
                field(AmountImpactField; AmountImpactTxt)
                {
                    ApplicationArea = All;
                    Caption = 'Net Amount Impact';
                    Editable = false;
                    ToolTip = 'Specifies the net amount change compared to the previous archived version.';
                }
            }
            group(AnswerGroup)
            {
                Caption = 'Copilot Answer';

                field(CopilotAnswerField; CopilotAnswer)
                {
                    ApplicationArea = All;
                    Editable = false;
                    MultiLine = true;
                    ShowCaption = false;
                    ToolTip = 'Displays the AI answer grounded in the Purchase Order diff payload.';
                }
            }
            group(PrecomputedSummaryGroup)
            {
                Caption = 'Recorded Version Change Summary';

                field(ExistingSummaryField; ExistingSummaryText)
                {
                    ApplicationArea = All;
                    Editable = false;
                    MultiLine = true;
                    ShowCaption = false;
                    ToolTip = 'Displays the precomputed summary of changes for this approval request.';
                }
            }
        }
    }

    actions
    {
        area(PromptGuide)
        {
            group(QuickQuestions)
            {
                Caption = 'Suggested questions';

                action(AskAmountChange)
                {
                    ApplicationArea = All;
                    Caption = 'Why did the total amount change?';
                    ToolTip = 'Populate the prompt with a question about total amount variance.';

                    trigger OnAction()
                    begin
                        UserQuestion := 'Explain why the Purchase Order total amount changed compared to the previous version, listing the contributing line and price/quantity changes.';
                    end;
                }
                action(AskPriceAndQty)
                {
                    ApplicationArea = All;
                    Caption = 'Summarize all price, discount, and quantity changes';
                    ToolTip = 'Populate the prompt to list line cost and quantity edits.';

                    trigger OnAction()
                    begin
                        UserQuestion := 'List every line-level quantity, unit cost, and discount change with old vs new values and line amount impact.';
                    end;
                }
                action(AskDatesVendorTerms)
                {
                    ApplicationArea = All;
                    Caption = 'Highlight delivery date, vendor, terms, or risk impacts';
                    ToolTip = 'Populate the prompt to review header, schedule, and risk changes.';

                    trigger OnAction()
                    begin
                        UserQuestion := 'What delivery date, payment terms, vendor, dimension, or comment changes occurred, and are there any procurement risks an approver should verify?';
                    end;
                }
            }
        }

        area(SystemActions)
        {
            systemaction(Generate)
            {
                Caption = 'Ask Copilot';
                ToolTip = 'Ask Azure OpenAI Copilot to analyze the Purchase Order version differences.';

                trigger OnAction()
                begin
                    ExecuteQuestion();
                end;
            }
            systemaction(Regenerate)
            {
                Caption = 'Regenerate';
                ToolTip = 'Re-run the current question against Azure OpenAI.';

                trigger OnAction()
                begin
                    ExecuteQuestion();
                end;
            }
            systemaction(Ok)
            {
                Caption = 'Close';
                ToolTip = 'Close the Copilot dialog.';
            }
            systemaction(Cancel)
            {
                ToolTip = 'Dismiss the Copilot dialog.';
            }
        }
    }

    var
        CurrentSummary: Record "POAI Approval Change Summary";
        DocumentNoTxt: Code[20];
        VersionLabelTxt: Text[50];
        UserQuestion: Text;
        LastAskedQuestion: Text;
        CopilotAnswer: Text;
        ExistingSummaryText: Text;
        DiffJsonText: Text;
        DocumentContextTxt: Text;
        AmountImpactTxt: Text;
        DialogCaption: Text;
        NoSummaryLoadedErr: Label 'No Purchase Order version comparison record is loaded.';
        NoDiffAvailableErr: Label 'No version comparison differences exist for %1 (%2).', Comment = '%1 = PO No., %2 = Version Label';
        AnalyzingMsg: Label 'Analyzing Purchase Order version changes with Copilot...';
        DefaultQuestionTxt: Label 'Provide an executive approval briefing summarizing financial variance, top line changes, header/terms changes, and potential risks.';
        AINotReadyErr: Label 'Azure OpenAI is not configured or the Copilot capability is inactive. Configure PO Approval Copilot Setup first, or review the deterministic breakdown on Version Change Details.';
        DialogCaptionLbl: Label 'PO %1 - %2', Comment = '%1 = PO No., %2 = Version Label';
        AmountImpactLbl: Label '%1 -> %2 (%3%4)', Locked = true;
        DocumentContextLbl: Label 'PO %1 | %2 | Amount: %3', Comment = '%1 = PO No., %2 = Version Label, %3 = Amount Impact';

    procedure LoadSummary(SummaryRec: Record "POAI Approval Change Summary")
    var
        SignPrefix: Text;
    begin
        CurrentSummary := SummaryRec;
        DocumentNoTxt := CurrentSummary."Document No.";
        VersionLabelTxt := CurrentSummary."Current Version Label";
        ExistingSummaryText := CurrentSummary.GetEffectiveSummaryText();
        DiffJsonText := CurrentSummary.GetDiffPayloadJson();
        DialogCaption := StrSubstNo(DialogCaptionLbl, CurrentSummary."Document No.", CurrentSummary."Current Version Label");

        if CurrentSummary."Amount Variance" > 0 then
            SignPrefix := '+';

        AmountImpactTxt := StrSubstNo(AmountImpactLbl,
            Format(CurrentSummary."Old Amount", 0, '<Precision,2:2><Standard Format,0>'),
            Format(CurrentSummary."New Amount", 0, '<Precision,2:2><Standard Format,0>'),
            SignPrefix,
            Format(CurrentSummary."Amount Variance", 0, '<Precision,2:2><Standard Format,0>'));

        DocumentContextTxt := StrSubstNo(DocumentContextLbl,
            CurrentSummary."Document No.",
            CurrentSummary."Current Version Label",
            AmountImpactTxt);
    end;

    local procedure ExecuteQuestion()
    var
        Setup: Record "POAI Copilot Setup";
        AISummaryHelper: Codeunit "POAI AI Summary Helper";
        ProgressDialog: Dialog;
        QuestionToRun: Text;
        Answer: Text;
        Succeeded: Boolean;
        ErrText: Text;
    begin
        if IsNullGuid(CurrentSummary."Workflow Step Instance ID") then
            Error(NoSummaryLoadedErr);

        if DiffJsonText = '' then
            Error(NoDiffAvailableErr, CurrentSummary."Document No.", CurrentSummary."Current Version Label");

        Setup.GetOrCreateSetup();
        if not AISummaryHelper.IsAIReady(Setup) then
            Error(AINotReadyErr);

        QuestionToRun := DelChr(UserQuestion, '<>', ' ');
        if QuestionToRun = '' then
            QuestionToRun := LastAskedQuestion;
        if QuestionToRun = '' then
            QuestionToRun := DefaultQuestionTxt;

        LastAskedQuestion := QuestionToRun;

        ProgressDialog.Open(AnalyzingMsg);
        ClearLastError();
        Succeeded := AISummaryHelper.TryAskAboutChanges(DiffJsonText, ExistingSummaryText, QuestionToRun, Answer);
        if not Succeeded then
            ErrText := GetLastErrorText();
        ProgressDialog.Close();

        if not Succeeded then
            Error(ErrText);

        CopilotAnswer := Answer;
    end;
}
