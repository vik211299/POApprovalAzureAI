namespace DefaultPublisher.POAIApproval;

codeunit 50105 "POAI Approval Review State"
{
    Access = Public;
    SingleInstance = true;

    var
        FromRequestsToApprove: Boolean;
        MarkedAtDateTime: DateTime;

    procedure MarkRequestsToApproveContext()
    begin
        FromRequestsToApprove := true;
        MarkedAtDateTime := CurrentDateTime();
    end;

    procedure ConsumeRequestsToApproveContext(): Boolean
    var
        IsValidContext: Boolean;
    begin
        IsValidContext :=
            FromRequestsToApprove and
            (MarkedAtDateTime <> 0DT) and
            ((CurrentDateTime() - MarkedAtDateTime) <= 10000);

        ClearRequestsToApproveContext();
        exit(IsValidContext);
    end;

    procedure ClearRequestsToApproveContext()
    begin
        FromRequestsToApprove := false;
        MarkedAtDateTime := 0DT;
    end;
}
