import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Bool "mo:base/Bool";
import ExtendedProposal "ExtendedProposal";

module {

    public type VotingThreshold = ExtendedProposal.VotingThreshold;

    public type Duration = ExtendedProposal.Duration;

    public type Member = ExtendedProposal.Member;

    public type Proposal<TProposalContent> = ExtendedProposal.Proposal<TProposalContent, Bool>;

    public type ProposalStatus = ExtendedProposal.ProposalStatus<Bool>;

    public type Vote = ExtendedProposal.Vote<Bool>;

    public type VotingSummary = ExtendedProposal.VotingSummary<Bool>;

    public type ChoiceVotingPower = ExtendedProposal.ChoiceVotingPower<Bool>;

    public type VoteError = ExtendedProposal.VoteError;

    public type VoteOk<TProposalContent> = ExtendedProposal.VoteOk<TProposalContent, Bool>;

    public type ChoiceStatus = ExtendedProposal.ChoiceStatus<Bool>;

    public func getVote<TProposalContent>(
        proposal : Proposal<TProposalContent>,
        voterId : Principal,
    ) : ?Vote {
        ExtendedProposal.getVote(
            proposal,
            voterId,
        );
    };

    public func vote<TProposalContent>(
        proposal : Proposal<TProposalContent>,
        voterId : Principal,
        vote : Bool,
        votingThreshold : VotingThreshold,
    ) : Result.Result<VoteOk<TProposalContent>, VoteError> {
        ExtendedProposal.vote(
            proposal,
            voterId,
            vote,
            votingThreshold,
            func(a : Bool, b : Bool) : Bool = a == b,
            func(a : Bool) : Nat32 = if (a) 1 else 0,
        );
    };

    public func buildVotingSummary(
        votes : [(Principal, Vote)]
    ) : VotingSummary {
        ExtendedProposal.buildVotingSummary(
            votes,
            func(a : Bool, b : Bool) : Bool = a == b,
            func(a : Bool) : Nat32 = if (a) 1 else 0,
        );
    };

    public func calculateVoteStatus<TProposalContent>(
        proposal : Proposal<TProposalContent>,
        votingThreshold : VotingThreshold,
        forceEnd : Bool,
    ) : ChoiceStatus {
        ExtendedProposal.calculateVoteStatus(
            proposal,
            votingThreshold,
            func(a : Bool, b : Bool) : Bool = a == b,
            func(a : Bool) : Nat32 = if (a) 1 else 0,
            forceEnd,
        );
    };
};
