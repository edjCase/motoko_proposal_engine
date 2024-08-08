import Time "mo:base/Time";
module {

    public type StableData<TProposalContent, TVote> = {
        proposals : [Proposal<TProposalContent, TVote>];
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

    public type Proposal<TProposalContent, TVote> = {
        id : Nat;
        proposerId : Principal;
        timeStart : Int;
        timeEnd : Int;
        endTimerId : ?Nat;
        content : TProposalContent;
        votes : [(Principal, Vote<TVote>)];
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

    public type Vote<T> = {
        value : ?T;
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
