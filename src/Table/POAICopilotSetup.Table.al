namespace DefaultPublisher.POAIApproval;

table 50100 "POAI Copilot Setup"
{
    Caption = 'Purchase Order Approval Copilot Setup';
    DataClassification = SystemMetadata;
    Access = Public;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
            DataClassification = SystemMetadata;
        }
        field(2; "Enable AI Summary"; Boolean)
        {
            Caption = 'Enable AI Summary';
            DataClassification = SystemMetadata;
            InitValue = true;
        }
        field(3; "Auto-Archive Policy"; Enum "POAI Auto-Archive Policy")
        {
            Caption = 'Auto-Archive Policy';
            DataClassification = SystemMetadata;
            InitValue = "On Any Release";
        }
        field(4; "Use Managed AI Resource"; Boolean)
        {
            Caption = 'Use Managed AI Resource';
            DataClassification = SystemMetadata;
            InitValue = false;

            trigger OnValidate()
            var
                CapabilitySetup: Codeunit "POAI Copilot Capability Setup";
            begin
                CapabilitySetup.SyncCapabilityBillingType(Rec."Use Managed AI Resource");
            end;
        }
        field(5; "AOAI Endpoint"; Text[250])
        {
            Caption = 'Azure OpenAI Endpoint';
            DataClassification = CustomerContent;
        }
        field(6; "AOAI Deployment"; Text[100])
        {
            Caption = 'Deployment Name';
            DataClassification = CustomerContent;
        }
        field(7; "Max Tokens"; Integer)
        {
            Caption = 'Max Tokens';
            DataClassification = SystemMetadata;
            InitValue = 0;
            MinValue = 0;
            MaxValue = 16384;
        }
        field(8; Temperature; Decimal)
        {
            Caption = 'Temperature';
            DataClassification = SystemMetadata;
            InitValue = 1;
            MinValue = 0;
            MaxValue = 2;
            DecimalPlaces = 0 : 2;
        }
        field(9; "Include Comments in Diff"; Boolean)
        {
            Caption = 'Include Comments in Comparison';
            DataClassification = SystemMetadata;
            InitValue = true;
        }
        field(10; "Include Dimensions in Diff"; Boolean)
        {
            Caption = 'Include Dimensions in Comparison';
            DataClassification = SystemMetadata;
            InitValue = true;
        }
    }

    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }

    var
        ApiKeyStorageKeyTok: Label 'POAI-AOAI-API-KEY', Locked = true;

    procedure GetOrCreateSetup()
    begin
        Rec.Reset();
        if not Rec.Get() then begin
            Rec.Init();
            Rec."Enable AI Summary" := true;
            Rec."Auto-Archive Policy" := Rec."Auto-Archive Policy"::"On Any Release";
            Rec."Max Tokens" := 0;
            Rec.Temperature := 1;
            Rec."Include Comments in Diff" := true;
            Rec."Include Dimensions in Diff" := true;
            Rec.Insert();
        end;
    end;

    [NonDebuggable]
    procedure SetApiKey(NewApiKey: SecretText)
    begin
        if NewApiKey.IsEmpty() then begin
            ClearApiKey();
            exit;
        end;

        IsolatedStorage.Set(ApiKeyStorageKeyTok, NewApiKey, DataScope::Company);
    end;

    [NonDebuggable]
    procedure GetApiKey(): SecretText
    var
        StoredKey: SecretText;
    begin
        if IsolatedStorage.Get(ApiKeyStorageKeyTok, DataScope::Company, StoredKey) then
            exit(StoredKey);
    end;

    procedure HasApiKey(): Boolean
    begin
        exit(IsolatedStorage.Contains(ApiKeyStorageKeyTok, DataScope::Company));
    end;

    procedure ClearApiKey()
    begin
        if IsolatedStorage.Contains(ApiKeyStorageKeyTok, DataScope::Company) then
            IsolatedStorage.Delete(ApiKeyStorageKeyTok, DataScope::Company);
    end;
}

