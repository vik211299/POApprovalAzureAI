namespace DefaultPublisher.POAIApproval;

using Microsoft.Finance.Dimension;
using Microsoft.Purchases.Archive;
using Microsoft.Purchases.Comment;
using Microsoft.Purchases.Document;
using System.Automation;
using System.Reflection;

permissionset 50100 "POAIApprovalSummary"
{
    Assignable = true;
    Caption = 'PO Approval Change Summary';

    Permissions =
        tabledata "POAI Copilot Setup" = RIMD,
        tabledata "POAI Approval Change Summary" = RIMD,
        tabledata "POAI Approval Change Detail" = RIMD,
        tabledata "Purchase Header" = R,
        tabledata "Purchase Line" = R,
        tabledata "Purch. Comment Line" = R,
        tabledata "Purchase Header Archive" = RIM,
        tabledata "Purchase Line Archive" = RIM,
        tabledata "Purch. Comment Line Archive" = RIM,
        tabledata "Approval Entry" = R,
        tabledata "Dimension Set Entry" = R,
        tabledata "Field" = R,
        table "POAI Copilot Setup" = X,
        table "POAI Approval Change Summary" = X,
        table "POAI Approval Change Detail" = X,
        codeunit "POAI Copilot Capability Setup" = X,
        codeunit "POAI Version Archive Handler" = X,
        codeunit "POAI Diff Engine" = X,
        codeunit "POAI AI Summary Helper" = X,
        codeunit "POAI Approval Subscribers" = X,
        page "POAI Copilot Setup" = X,
        page "POAI Version Change FactBox" = X,
        page "POAI Version Change Details" = X,
        page "POAI Change Summary Prompt" = X,
        page "POAI Change Detail Subform" = X;
}
