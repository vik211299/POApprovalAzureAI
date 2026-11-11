namespace DefaultPublisher.POAIApproval;

using System.AI;

codeunit 50103 "POAI AI Summary Helper"
{
    Access = Public;
    Permissions = tabledata "POAI Copilot Setup" = ri;

    var
        NotConfiguredErr: Label 'Azure OpenAI endpoint, deployment, or API key is not configured in PO Approval Copilot Setup.';
        CapabilityNotActiveErr: Label 'Copilot capability "PO Approval Change Summary" is not active.';
        InvalidAIJsonErr: Label 'Azure OpenAI returned invalid JSON payload.';

    procedure IsAIReady(Setup: Record "POAI Copilot Setup"): Boolean
    var
        CopilotCap: Codeunit "Copilot Capability";
        Cap: Enum "Copilot Capability";
    begin
        if not Setup."Enable AI Summary" then
            exit(false);

        Cap := Cap::"PO Approval Change Summary";
        if not CopilotCap.IsCapabilityRegistered(Cap) then
            exit(false);
        if not CopilotCap.IsCapabilityActive(Cap) then
            exit(false);

        if Setup."Use Managed AI Resource" then
            exit(Setup."AOAI Deployment" <> '');

        exit((Setup."AOAI Endpoint" <> '') and (Setup."AOAI Deployment" <> '') and Setup.HasApiKey());
    end;

    [TryFunction]
    [NonDebuggable]
    procedure TryGenerateSummary(
        DiffJsonText: Text;
        var ShortSummary: Text[250];
        var DetailedSummary: Text)
    var
        Setup: Record "POAI Copilot Setup";
        Msg: Codeunit "AOAI Chat Messages";
        PromptBuilder: TextBuilder;
        SystemPrompt: Text;
        UserPrompt: Text;
        RawResponse: Text;
    begin
        Setup.GetOrCreateSetup();
        if not IsAIReady(Setup) then
            Error(NotConfiguredErr);

        SystemPrompt :=
            'You are a procurement approval assistant in Dynamics 365 Business Central. ' +
            'Summarize the changes between the previous version and the current Purchase Order version based strictly on the provided JSON diff. ' +
            'Do not invent numbers or fields not present in the JSON. ' +
            'Return strict json only with keys: ' +
            'shortSummary (concise single line under 200 chars for a list column), ' +
            'executiveSummary (2-3 clear sentences covering overall financial and business impact), ' +
            'keyChanges (array of concise bullet strings highlighting top header and line changes), ' +
            'riskNotes (short note on price increases, quantity spikes, vendor/terms/date shifts, or "None" if low risk).';

        PromptBuilder.AppendLine('Purchase Order Version Diff JSON:');
        PromptBuilder.Append(DiffJsonText);
        UserPrompt := PromptBuilder.ToText();
        Msg.AddXPIADetectionTags(UserPrompt);

        Msg.AddSystemMessage(SystemPrompt);
        Msg.AddUserMessage(UserPrompt);

        ExecuteChatCompletion(Setup, Msg, true);

        RawResponse := Msg.GetLastMessage();
        ParseSummaryJson(RawResponse, ShortSummary, DetailedSummary);
    end;

    [TryFunction]
    [NonDebuggable]
    procedure TryAskAboutChanges(
        DiffJsonText: Text;
        ExistingSummary: Text;
        UserQuestion: Text;
        var AnswerText: Text)
    var
        Setup: Record "POAI Copilot Setup";
        Msg: Codeunit "AOAI Chat Messages";
        PromptBuilder: TextBuilder;
        SystemPrompt: Text;
        UserPayload: Text;
    begin
        Setup.GetOrCreateSetup();
        if not IsAIReady(Setup) then
            Error(NotConfiguredErr);

        SystemPrompt :=
            'You are a procurement approval Copilot in Dynamics 365 Business Central. ' +
            'Answer the approver''s question accurately using only the provided Purchase Order version diff JSON and summary. ' +
            'Be concise, quantitative, and cite line numbers, item numbers, and old vs new values when applicable.';

        PromptBuilder.AppendLine('Purchase Order Diff JSON:');
        PromptBuilder.AppendLine(DiffJsonText);
        PromptBuilder.AppendLine();
        PromptBuilder.AppendLine('Current Summary:');
        PromptBuilder.AppendLine(ExistingSummary);
        PromptBuilder.AppendLine();
        PromptBuilder.AppendLine('Approver Question:');
        PromptBuilder.Append(UserQuestion);
        UserPayload := PromptBuilder.ToText();
        Msg.AddXPIADetectionTags(UserPayload);

        Msg.AddSystemMessage(SystemPrompt);
        Msg.AddUserMessage(UserPayload);

        ExecuteChatCompletion(Setup, Msg, false);

        AnswerText := Msg.GetLastMessage();
    end;

    [TryFunction]
    [NonDebuggable]
    procedure TryTestConnection(var ReplyText: Text)
    var
        Setup: Record "POAI Copilot Setup";
        CopilotCap: Codeunit "Copilot Capability";
        Msg: Codeunit "AOAI Chat Messages";
        Cap: Enum "Copilot Capability";
    begin
        Setup.GetOrCreateSetup();
        Cap := Cap::"PO Approval Change Summary";
        if not CopilotCap.IsCapabilityActive(Cap) then
            Error(CapabilityNotActiveErr);

        if Setup."Use Managed AI Resource" then begin
            if Setup."AOAI Deployment" = '' then
                Error(NotConfiguredErr);
        end else
            if (Setup."AOAI Endpoint" = '') or (Setup."AOAI Deployment" = '') or (not Setup.HasApiKey()) then
                Error(NotConfiguredErr);

        Msg.AddSystemMessage('Reply with the word OK in plain text.');
        Msg.AddUserMessage('Connection test');

        ExecuteChatCompletion(Setup, Msg, false);

        ReplyText := Msg.GetLastMessage();
    end;

    [NonDebuggable]
    local procedure ExecuteChatCompletion(Setup: Record "POAI Copilot Setup"; var Msg: Codeunit "AOAI Chat Messages"; JsonMode: Boolean)
    var
        AzureOpenAI: Codeunit "Azure OpenAI";
        Params: Codeunit "AOAI Chat Completion Params";
        FallbackParams: Codeunit "AOAI Chat Completion Params";
        Resp: Codeunit "AOAI Operation Response";
        ErrText: Text;
    begin
        ConfigureParams(Params, Setup, JsonMode);
        ConfigureAuthorization(AzureOpenAI, Setup);
        AzureOpenAI.SetCopilotCapability(Enum::"Copilot Capability"::"PO Approval Change Summary");
        AzureOpenAI.GenerateChatCompletion(Msg, Params, Resp);

        if Resp.IsSuccess() then
            exit;

        ErrText := Resp.GetError();
        if ErrText.Contains('max_tokens') or ErrText.Contains('temperature') then begin
            FallbackParams.SetJsonMode(JsonMode);
            FallbackParams.SetMaxTokens(0);
            FallbackParams.SetTemperature(1);
            Clear(Resp);
            AzureOpenAI.GenerateChatCompletion(Msg, FallbackParams, Resp);
            if Resp.IsSuccess() then
                exit;
            Error(Resp.GetError());
        end;

        Error(ErrText);
    end;

    local procedure ConfigureParams(var Params: Codeunit "AOAI Chat Completion Params"; Setup: Record "POAI Copilot Setup"; JsonMode: Boolean)
    begin
        Params.SetJsonMode(JsonMode);
        if IsReasoningModelDeployment(Setup."AOAI Deployment") then begin
            // GPT-5 and o-series reasoning models reject max_tokens and require temperature = 1.
            Params.SetTemperature(1);
            Params.SetMaxTokens(0);
        end else begin
            Params.SetTemperature(Setup.Temperature);
            if Setup."Max Tokens" > 0 then
                Params.SetMaxTokens(Setup."Max Tokens")
            else
                Params.SetMaxTokens(0);
        end;
    end;

    local procedure IsReasoningModelDeployment(DeploymentName: Text): Boolean
    var
        LowerName: Text;
    begin
        LowerName := LowerCase(DelChr(DeploymentName, '<>', ' '));
        exit(
            LowerName.Contains('gpt-5') or
            LowerName.Contains('gpt5') or
            LowerName.StartsWith('o1') or
            LowerName.StartsWith('o3') or
            LowerName.StartsWith('o4') or
            LowerName.Contains('-o1') or
            LowerName.Contains('-o3') or
            LowerName.Contains('-o4'));
    end;

    [NonDebuggable]
    local procedure ConfigureAuthorization(var AzureOpenAI: Codeunit "Azure OpenAI"; Setup: Record "POAI Copilot Setup")
    begin
        if Setup."Use Managed AI Resource" then
            AzureOpenAI.SetManagedResourceAuthorization(
                Enum::"AOAI Model Type"::"Chat Completions",
                Setup."AOAI Deployment")
        else
            AzureOpenAI.SetAuthorization(
                Enum::"AOAI Model Type"::"Chat Completions",
                Setup."AOAI Endpoint",
                Setup."AOAI Deployment",
                Setup.GetApiKey());
    end;

    local procedure ParseSummaryJson(JsonText: Text; var ShortSummary: Text[250]; var DetailedSummary: Text)
    var
        JObject: JsonObject;
        Token: JsonToken;
        JArray: JsonArray;
        ItemToken: JsonToken;
        Builder: TextBuilder;
        CleanJson: Text;
        ExecSummary: Text;
        RiskNotes: Text;
    begin
        CleanJson := SanitizeJsonPayload(JsonText);
        if not JObject.ReadFrom(CleanJson) then
            Error(InvalidAIJsonErr);

        if JObject.Get('shortSummary', Token) then
            ShortSummary := CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(ShortSummary));

        if JObject.Get('executiveSummary', Token) then begin
            ExecSummary := Token.AsValue().AsText();
            if ExecSummary <> '' then
                Builder.AppendLine(ExecSummary);
        end;

        if JObject.Get('keyChanges', Token) and Token.IsArray() then begin
            JArray := Token.AsArray();
            if JArray.Count() > 0 then begin
                if Builder.Length > 0 then
                    Builder.AppendLine();
                Builder.AppendLine('Key Changes:');
                foreach ItemToken in JArray do
                    Builder.AppendLine('- ' + ItemToken.AsValue().AsText());
            end;
        end;

        if JObject.Get('riskNotes', Token) then begin
            RiskNotes := Token.AsValue().AsText();
            if (RiskNotes <> '') and (LowerCase(RiskNotes) <> 'none') then begin
                if Builder.Length > 0 then
                    Builder.AppendLine();
                Builder.AppendLine('Risk / Impact: ' + RiskNotes);
            end;
        end;

        DetailedSummary := Builder.ToText();
        if (ShortSummary = '') and (DetailedSummary <> '') then
            ShortSummary := CopyStr(DetailedSummary, 1, MaxStrLen(ShortSummary));
    end;

    local procedure SanitizeJsonPayload(RawText: Text): Text
    var
        Trimmed: Text;
        StartIdx: Integer;
        EndIdx: Integer;
    begin
        Trimmed := RawText.Trim();
        StartIdx := Trimmed.IndexOf('{');
        EndIdx := Trimmed.LastIndexOf('}');
        if (StartIdx > 0) and (EndIdx >= StartIdx) then
            exit(Trimmed.Substring(StartIdx, EndIdx - StartIdx + 1));
        exit(Trimmed);
    end;
}

