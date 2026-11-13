namespace DefaultPublisher.POAIApproval;

using System.AI;

page 50100 "POAI Copilot Setup"
{
    AdditionalSearchTerms = 'PO Copilot, PO AI, Purchase Order Approval, Version Changes, PO Setup';
    ApplicationArea = All;
    Caption = 'Purchase Order Approval Copilot Setup';
    DeleteAllowed = false;
    InsertAllowed = false;
    PageType = Card;
    SourceTable = "POAI Copilot Setup";
    UsageCategory = Administration;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';

                field("Enable AI Summary"; Rec."Enable AI Summary")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies whether Azure OpenAI should generate executive change summaries when Purchase Orders are sent for approval. If disabled or unavailable, a deterministic summary is used automatically.';
                }
                field("Auto-Archive Policy"; Rec."Auto-Archive Policy")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies when Purchase Orders are automatically archived into Purchase Order Archive upon release so future revisions have a baseline to compare against.';
                }
                field("Include Comments in Diff"; Rec."Include Comments in Diff")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies whether changes in Purchase Order comments are included in the comparison and summary.';
                }
                field("Include Dimensions in Diff"; Rec."Include Dimensions in Diff")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies whether header and line dimension changes are included in the comparison and summary.';
                }
            }
            group(AzureOpenAI)
            {
                Caption = 'Azure OpenAI Configuration';

                field("Use Managed AI Resource"; Rec."Use Managed AI Resource")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies whether to use Microsoft-managed Azure OpenAI resources (when eligible) instead of your own Azure OpenAI endpoint and API key.';

                    trigger OnValidate()
                    begin
                        RefreshControlStates();
                        CurrPage.Update(false);
                    end;
                }
                field("AOAI Endpoint"; Rec."AOAI Endpoint")
                {
                    ApplicationArea = All;
                    Enabled = UseSelfManagedAI;
                    ExtendedDatatype = URL;
                    ToolTip = 'Specifies the Azure OpenAI resource endpoint URL (for example, https://your-resource.openai.azure.com/).';
                }
                field("AOAI Deployment"; Rec."AOAI Deployment")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the Azure OpenAI chat completion model deployment name.';
                }
                field(ApiKeyInput; ApiKeyInput)
                {
                    ApplicationArea = All;
                    Caption = 'API Key';
                    Enabled = UseSelfManagedAI;
                    ExtendedDatatype = Masked;
                    ToolTip = 'Enter an Azure OpenAI API key to store securely in company-scoped Isolated Storage. Leave blank to keep the existing stored key.';

                    trigger OnValidate()
                    begin
                        SaveApiKey(ApiKeyInput);
                        Clear(ApiKeyInput);
                        RefreshControlStates();
                        CurrPage.Update(false);
                    end;
                }
                field(ApiKeyStatus; ApiKeyStatusTxt)
                {
                    ApplicationArea = All;
                    Caption = 'API Key Status';
                    Editable = false;
                    Enabled = UseSelfManagedAI;
                    StyleExpr = ApiKeyStatusStyle;
                    ToolTip = 'Indicates whether an Azure OpenAI API key is currently stored in Isolated Storage for this company.';
                }
                field("Max Tokens"; Rec."Max Tokens")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the maximum tokens for chat completions (0 omits max_tokens and uses the model API default; required for GPT-5 / reasoning models).';
                }
                field(Temperature; Rec.Temperature)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the sampling temperature for Azure OpenAI responses (1 is required for GPT-5 / o-series reasoning models; 0 for deterministic GPT-4o output).';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RegisterCapability)
            {
                ApplicationArea = All;
                Caption = 'Register / Sync Copilot Capability';
                Image = Sparkle;
                ToolTip = 'Registers or updates the Purchase Order Approval Change Summary Copilot capability in Business Central.';

                trigger OnAction()
                var
                    CapabilitySetup: Codeunit "POAI Copilot Capability Setup";
                begin
                    CapabilitySetup.SyncCapabilityBillingType(Rec."Use Managed AI Resource");
                    Message(CapabilitySyncedMsg);
                end;
            }
            action(TestConnection)
            {
                ApplicationArea = All;
                Caption = 'Test AI Connection';
                Image = TestDatabase;
                ToolTip = 'Sends a lightweight test prompt to verify that the Copilot capability and Azure OpenAI configuration work.';

                trigger OnAction()
                var
                    AISummaryHelper: Codeunit "POAI AI Summary Helper";
                    ReplyText: Text;
                begin
                    ClearLastError();
                    if AISummaryHelper.TryTestConnection(ReplyText) then
                        Message(ConnectionSuccessMsg, ReplyText)
                    else
                        Error(ConnectionFailedErr, GetLastErrorText());
                end;
            }
            action(ClearStoredApiKey)
            {
                ApplicationArea = All;
                Caption = 'Clear Stored API Key';
                Enabled = CanClearApiKey;
                Image = ClearFilter;
                ToolTip = 'Deletes the stored Azure OpenAI API key from Isolated Storage for this company.';

                trigger OnAction()
                begin
                    if not Confirm(ConfirmClearKeyQst, false) then
                        exit;
                    Rec.ClearApiKey();
                    RefreshControlStates();
                    CurrPage.Update(false);
                end;
            }
            action(OpenCopilotCapabilities)
            {
                ApplicationArea = All;
                Caption = 'Copilot & Agent Capabilities';
                Image = Setup;
                RunObject = page "Copilot AI Capabilities";
                ToolTip = 'Opens the standard Copilot & agent capabilities setup page to review or activate capabilities.';
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                actionref(TestConnection_Promoted; TestConnection)
                {
                }
                actionref(RegisterCapability_Promoted; RegisterCapability)
                {
                }
                actionref(ClearStoredApiKey_Promoted; ClearStoredApiKey)
                {
                }
                actionref(OpenCopilotCapabilities_Promoted; OpenCopilotCapabilities)
                {
                }
            }
        }
    }

    trigger OnOpenPage()
    begin
        Rec.GetOrCreateSetup();
        RefreshControlStates();
    end;

    trigger OnAfterGetCurrRecord()
    begin
        RefreshControlStates();
    end;

    var
        [NonDebuggable]
        ApiKeyInput: Text;
        ApiKeyStatusTxt: Text[100];
        ApiKeyStatusStyle: Text[20];
        HasStoredApiKey: Boolean;
        UseSelfManagedAI: Boolean;
        CanClearApiKey: Boolean;
        ConfiguredKeyTxt: Label 'Configured (stored in Isolated Storage)';
        MissingKeyTxt: Label 'Not configured';
        CapabilitySyncedMsg: Label 'Purchase Order Approval Change Summary capability is registered and synced.';
        ConnectionSuccessMsg: Label 'Azure OpenAI connection succeeded. Model replied: %1', Comment = '%1 = model reply';
        ConnectionFailedErr: Label 'Azure OpenAI connection test failed: %1', Comment = '%1 = error text';
        ConfirmClearKeyQst: Label 'Do you want to remove the stored Azure OpenAI API key from Isolated Storage?';

    [NonDebuggable]
    local procedure SaveApiKey(NewKeyText: Text)
    var
        SecretKey: SecretText;
    begin
        SecretKey := NewKeyText;
        Rec.SetApiKey(SecretKey);
    end;

    local procedure RefreshControlStates()
    begin
        HasStoredApiKey := Rec.HasApiKey();
        UseSelfManagedAI := not Rec."Use Managed AI Resource";
        CanClearApiKey := HasStoredApiKey and UseSelfManagedAI;
        if HasStoredApiKey then begin
            ApiKeyStatusTxt := ConfiguredKeyTxt;
            ApiKeyStatusStyle := 'Favorable';
        end else begin
            ApiKeyStatusTxt := MissingKeyTxt;
            ApiKeyStatusStyle := 'Attention';
        end;
    end;
}

