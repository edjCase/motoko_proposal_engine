import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Bool "mo:base/Bool";
import Time "mo:base/Time";
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

    public type VotingMode = ExtendedProposal.VotingMode;

    public type AddMemberError = ExtendedProposal.AddMemberError;

    /// Retrieves a vote for a specific voter on a proposal.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent> = ...;
    /// let voterId : Principal = ...;
    /// let ?vote : ?Vote = getVote(proposal, voterId) else Debug.trap("Vote not found");
    /// ```
    public func getVote<TProposalContent>(
        proposal : Proposal<TProposalContent>,
        voterId : Principal,
    ) : ?Vote {
        ExtendedProposal.getVote(
            proposal,
            voterId,
        );
    };

    /// Casts a vote on a proposal for the specified voter.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent> = ...;
    /// let voterId : Principal = ...;
    /// let vote : Bool = true; // true for yes, false for no
    /// let allowVoteChange : Bool = false;
    /// switch (vote(proposal, voterId, vote, allowVoteChange)) {
    ///   case (#ok) { /* Vote successful */ };
    ///   case (#err(error)) { /* Handle error */ };
    /// };
    /// ```
    public func vote<TProposalContent>(
        proposal : Proposal<TProposalContent>,
        voterId : Principal,
        vote : Bool,
        allowVoteChange : Bool,
    ) : Result.Result<(), VoteError> {
        ExtendedProposal.vote(
            proposal,
            voterId,
            vote,
            allowVoteChange,
        );
    };

    /// Builds a voting summary for a proposal showing vote tallies.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent> = ...;
    /// let summary : VotingSummary = buildVotingSummary(proposal);
    /// Debug.print("Total voting power: " # Nat.toText(summary.totalVotingPower));
    /// ```
    public func buildVotingSummary<TProposalContent>(
        proposal : Proposal<TProposalContent>
    ) : VotingSummary {
        ExtendedProposal.buildVotingSummary(
            proposal,
            func(a : Bool, b : Bool) : Bool = a == b,
            func(a : Bool) : Nat32 = if (a) 1 else 0,
        );
    };

    /// Calculates the current status of voting for a proposal.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent> = ...;
    /// let votingThreshold : VotingThreshold = #percent({ percent = 50; quorum = ?25 });
    /// let forceEnd : Bool = false;
    /// switch (calculateVoteStatus(proposal, votingThreshold, forceEnd)) {
    ///   case (#determined(?choice)) { /* Proposal passed with choice */ };
    ///   case (#determined(null)) { /* Proposal rejected */ };
    ///   case (#undetermined) { /* Still voting */ };
    /// };
    /// ```
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

    /// Creates a new proposal with the specified parameters.
    ///
    /// ```motoko
    /// let id : Nat = 1;
    /// let proposerId : Principal = ...;
    /// let content = { /* Your proposal content */ };
    /// let members : [Member] = [{ id = ...; votingPower = 100 }];
    /// let timeStart : Time.Time = Time.now();
    /// let timeEnd : ?Time.Time = ?(timeStart + 24 * 60 * 60 * 1_000_000_000); // 24 hours
    /// let votingMode : VotingMode = #snapshot;
    /// let proposal : Proposal<MyContent> = create(id, proposerId, content, members, timeStart, timeEnd, votingMode);
    /// ```
    public func create<TProposalContent>(
        id : Nat,
        proposerId : Principal,
        content : TProposalContent,
        members : [Member],
        timeStart : Time.Time,
        timeEnd : ?Time.Time,
        votingMode : VotingMode,
    ) : Proposal<TProposalContent> {
        ExtendedProposal.create<TProposalContent, Bool>(
            id,
            proposerId,
            content,
            members,
            timeStart,
            timeEnd,
            votingMode,
        );
    };

    /// Adds a member to a dynamic proposal.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent> = ...;
    /// let member : Member = { id = Principal.fromText("..."); votingPower = 100 };
    /// switch (addMember(proposal, member)) {
    ///   case (#ok) { /* Member added successfully */ };
    ///   case (#err(error)) { /* Handle error */ };
    /// };
    /// ```
    public func addMember<TProposalContent>(
        proposal : Proposal<TProposalContent>,
        member : Member,
    ) : Result.Result<(), AddMemberError> {
        ExtendedProposal.addMember(proposal, member);
    };
};
