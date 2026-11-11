namespace DefaultPublisher.POAIApproval;

using System.AI;

codeunit 50100 "POAI Copilot Capability Setup"
{
    Subtype = Install;
    Access = Public;
    Permissions = tabledata "POAI Copilot Setup" = ri;

    var
        LearnMoreUrlTxt: Label 'https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-copilot-overview', Locked = true;

    trigger OnInstallAppPerCompany()
    begin
        Register();
    end;

    procedure Register()
    var
        Setup: Record "POAI Copilot Setup";
        CopilotCap: Codeunit "Copilot Capability";
        Cap: Enum "Copilot Capability";
        BillingType: Enum "Copilot Billing Type";
    begin
        Setup.GetOrCreateSetup();
        Cap := Cap::"PO Approval Change Summary";
        BillingType := GetBillingType(Setup."Use Managed AI Resource");

        if not CopilotCap.IsCapabilityRegistered(Cap) then
            CopilotCap.RegisterCapability(
                Cap,
                Enum::"Copilot Availability"::Preview,
                BillingType,
                LearnMoreUrlTxt);
    end;

    procedure SyncCapabilityBillingType(UseManagedResource: Boolean)
    var
        CopilotCap: Codeunit "Copilot Capability";
        Cap: Enum "Copilot Capability";
        BillingType: Enum "Copilot Billing Type";
    begin
        Cap := Cap::"PO Approval Change Summary";
        BillingType := GetBillingType(UseManagedResource);

        if not CopilotCap.IsCapabilityRegistered(Cap) then
            CopilotCap.RegisterCapability(
                Cap,
                Enum::"Copilot Availability"::Preview,
                BillingType,
                LearnMoreUrlTxt)
        else
            CopilotCap.ModifyCapability(
                Cap,
                Enum::"Copilot Availability"::Preview,
                BillingType,
                LearnMoreUrlTxt);
    end;

    local procedure GetBillingType(UseManagedResource: Boolean): Enum "Copilot Billing Type"
    begin
        if UseManagedResource then
            exit(Enum::"Copilot Billing Type"::"Microsoft Billed");
        exit(Enum::"Copilot Billing Type"::"Not Billed");
    end;
}

