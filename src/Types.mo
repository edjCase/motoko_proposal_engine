import Time "mo:base/Time";
module {

    public type StableData<TProposalContent> = {
        proposals : [Proposal<TProposalContent>];
        proposalDuration : Duration;
        votingThreshold : VotingThreshold;
    };

    public type PagedResult<T> = {
        data : [T];
        offset : Nat;
        count : Nat;
        total : Nat;
    };

    public type VotingThreshold = {
        #percent : { percent : Percent; quorum : ?Percent };
    };
    public type Percent = Nat; // 0-100

    public type Duration = {
        #days : Nat;
        #nanoseconds : Nat;
    };

    public type Member = {
        votingPower : Nat;
        id : Principal;
    };

    public type Proposal<TProposalContent> = {
        id : Nat;
        proposerId : Principal;
        timeStart : Int;
        timeEnd : Int;
        endTimerId : ?Nat;
        content : TProposalContent;
        votes : [(Principal, Vote)];
        statusLog : [ProposalStatusLogEntry];
    };

    public type ProposalStatusLogEntry = {
        #executing : {
            time : Time.Time;
        };
        #executed : {
            time : Time.Time;
        };
        #failedToExecute : {
            time : Time.Time;
            error : Text;
        };
        #rejected : {
            time : Time.Time;
        };
    };

    public type Vote = {
        value : ?Bool;
        votingPower : Nat;
    };

    public type AddMemberResult = {
        #ok;
        #alreadyExists;
    };

    public type CreateProposalError = {
        #notAuthorized;
        #invalid : [Text];
    };

    public type VoteError = {
        #notAuthorized;
        #alreadyVoted;
        #votingClosed;
        #proposalNotFound;
    };

};
