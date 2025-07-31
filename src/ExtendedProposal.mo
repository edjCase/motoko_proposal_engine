import Time "mo:base/Time";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Option "mo:base/Option";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Debug "mo:base/Debug";
import BTree "mo:stableheapbtreemap/BTree";

module {

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

    public type VotingMode = {
        #snapshot;
        #dynamic : {
            totalVotingPower : ?Nat;
        };
    };

    public type Proposal<TProposalContent, TChoice> = {
        id : Nat;
        proposerId : Principal;
        timeStart : Int;
        timeEnd : ?Int;
        votingMode : VotingMode;
        content : TProposalContent;
        votes : BTree.BTree<Principal, Vote<TChoice>>;
        status : ProposalStatus<TChoice>;
    };

    public type ProposalStatus<TChoice> = {
        #open;
        #executing : {
            executingTime : Time.Time;
            choice : ?TChoice;
        };
        #executed : {
            executingTime : Time.Time;
            executedTime : Time.Time;
            choice : ?TChoice;
        };
        #failedToExecute : {
            executingTime : Time.Time;
            failedTime : Time.Time;
            choice : ?TChoice;
            error : Text;
        };
    };

    public type Vote<TChoice> = {
        choice : ?TChoice;
        votingPower : Nat;
    };

    public type VotingSummary<TChoice> = {
        votingPowerByChoice : [ChoiceVotingPower<TChoice>];
        totalVotingPower : Nat;
        undecidedVotingPower : Nat;
    };

    public type ChoiceVotingPower<TChoice> = {
        choice : TChoice;
        votingPower : Nat;
    };

    public type VoteError = {
        #notEligible;
        #alreadyVoted;
        #votingClosed;
    };

    public type VoteOk<TProposalContent, TChoice> = {
        updatedProposal : Proposal<TProposalContent, TChoice>;
    };

    public type ChoiceStatus<TChoice> = {
        #determined : ?TChoice;
        #undetermined;
    };
    type MinProposal<TChoice> = {
        votes : BTree.BTree<Principal, Vote<TChoice>>;
        status : ProposalStatus<TChoice>;
    };

    public type AddMemberError = {
        #alreadyExists;
        #votingNotDynamic;
        #votingClosed;
    };

    /// Adds a member to a dynamic proposal.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent, MyChoice> = ...;
    /// let member : Member = { id = Principal.fromText("..."); votingPower = 100 };
    /// switch (addMember(proposal, member)) {
    ///   case (#ok) { /* Member added successfully */ };
    ///   case (#err(#alreadyExists)) { /* Member already exists */ };
    ///   case (#err(#votingNotDynamic)) { /* Proposal is not dynamic */ };
    ///   case (#err(#votingClosed)) { /* Voting is closed */ };
    /// };
    /// ```
    public func addMember<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        member : Member,
    ) : Result.Result<(), AddMemberError> {
        switch (proposal.votingMode) {
            case (#snapshot(_)) return #err(#votingNotDynamic);
            case (#dynamic(_)) ();
        };
        switch (proposal.status) {
            case (#open) ();
            case (_) return #err(#votingClosed);
        };
        switch (proposal.timeEnd) {
            case (?timeEnd) if (timeEnd <= Time.now()) {
                return #err(#votingClosed);
            };
            case (null) ();
        };

        if (BTree.has(proposal.votes, Principal.compare, member.id)) {
            return #err(#alreadyExists);
        };
        // Add vote entry with no vote
        ignore BTree.insert(
            proposal.votes,
            Principal.compare,
            member.id,
            { choice = null; votingPower = member.votingPower },
        );

        #ok;
    };

    /// Retrieves a vote for a specific voter on a proposal.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent, MyChoice> = ...;
    /// let voterId : Principal = ...;
    /// let ?vote : ?Vote<MyChoice> = getVote(proposal, voterId) else Debug.trap("Vote not found");
    /// ```
    public func getVote<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        voterId : Principal,
    ) : ?Vote<TChoice> {
        BTree.get(
            proposal.votes,
            Principal.compare,
            voterId,
        );
    };

    /// Casts a vote on a proposal for the specified voter.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent, MyChoice> = ...;
    /// let voterId : Principal = ...;
    /// let vote : MyChoice = ...;
    /// let allowVoteChange : Bool = false;
    /// switch (vote(proposal, voterId, vote, allowVoteChange)) {
    ///   case (#ok) { /* Vote successful */ };
    ///   case (#err(#notEligible)) { /* Voter not eligible */ };
    ///   case (#err(#alreadyVoted)) { /* Already voted and change not allowed */ };
    ///   case (#err(#votingClosed)) { /* Voting period closed */ };
    /// };
    /// ```
    public func vote<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        voterId : Principal,
        vote : TChoice,
        allowVoteChange : Bool,
    ) : Result.Result<(), VoteError> {
        let now = Time.now();
        if (proposal.timeStart > now) {
            return #err(#votingClosed);
        };
        switch (proposal.status) {
            case (#open) ();
            case (_) {
                return #err(#votingClosed);
            };
        };

        switch (proposal.timeEnd) {
            case (?timeEnd) if (timeEnd <= now) {
                return #err(#votingClosed);
            };
            case (null) ();
        };

        let ?existingVote = BTree.get(
            proposal.votes,
            Principal.compare,
            voterId,
        ) else return #err(#notEligible); // Only allow members to vote who existed when the proposal was created

        if (not allowVoteChange) {
            let null = existingVote.choice else return #err(#alreadyVoted);
        };

        ignore BTree.insert(
            proposal.votes,
            Principal.compare,
            voterId,
            { existingVote with choice = ?vote },
        );

        #ok;
    };

    /// Builds a voting summary for a proposal showing vote tallies by choice.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent, MyChoice> = ...;
    /// let equal : (MyChoice, MyChoice) -> Bool = ...;
    /// let hash : (MyChoice) -> Nat32 = ...;
    /// let summary : VotingSummary<MyChoice> = buildVotingSummary(proposal, equal, hash);
    /// Debug.print("Total voting power: " # Nat.toText(summary.totalVotingPower));
    /// ```
    public func buildVotingSummary<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        equal : (TChoice, TChoice) -> Bool,
        hash : (TChoice) -> Nat32,
    ) : VotingSummary<TChoice> {
        Debug.print("📊 SUMMARY: =======BUILDING VOTING SUMMARY=======");
        Debug.print("📊 SUMMARY: Proposal ID: " # debug_show(proposal.id));
        Debug.print("📊 SUMMARY: Voting mode: " # debug_show(proposal.votingMode));
        
        let choices = HashMap.HashMap<TChoice, Nat>(5, equal, hash);
        var undecidedVotingPower = 0;
        let totalVotingPower = switch (proposal.votingMode) {
            case (#dynamic({ totalVotingPower = ?totalVotingPower })) {
                Debug.print("📊 SUMMARY: Dynamic mode with fixed total: " # debug_show(totalVotingPower));
                totalVotingPower;
            };
            case (#snapshot(_) or #dynamic({ totalVotingPower = null })) {
                Debug.print("📊 SUMMARY: Snapshot mode or dynamic without fixed total");
                var totalVotingPower = 0;
                let voteCount = BTree.size(proposal.votes);
                Debug.print("📊 SUMMARY: Total vote entries: " # debug_show(voteCount));
                
                for ((voterId, vote) in BTree.entries(proposal.votes)) {
                    Debug.print("📊 SUMMARY: Processing vote from " # Principal.toText(voterId) # " with power " # debug_show(vote.votingPower));
                    switch (vote.choice) {
                        case (null) {
                            undecidedVotingPower += vote.votingPower;
                            Debug.print("📊 SUMMARY: Undecided vote, total undecided now: " # debug_show(undecidedVotingPower));
                        };
                        case (?choice) {
                            let currentVotingPower = Option.get(choices.get(choice), 0);
                            choices.put(choice, currentVotingPower + vote.votingPower);
                            Debug.print("📊 SUMMARY: Choice vote, new total for this choice: " # debug_show(currentVotingPower + vote.votingPower));
                        };
                    };
                    totalVotingPower += vote.votingPower;
                };
                Debug.print("📊 SUMMARY: Calculated total voting power: " # debug_show(totalVotingPower));
                totalVotingPower;
            };
        };

        Debug.print("📊 SUMMARY: Final total voting power: " # debug_show(totalVotingPower));
        Debug.print("📊 SUMMARY: Final undecided voting power: " # debug_show(undecidedVotingPower));
        Debug.print("📊 SUMMARY: Choice count: " # debug_show(choices.size()));

        let choiceArray = Iter.toArray(
            Iter.map(
                choices.entries(),
                func((choice, votingPower) : (TChoice, Nat)) : ChoiceVotingPower<TChoice> = {
                    choice = choice;
                    votingPower = votingPower;
                }
            )
        );

        {
            votingPowerByChoice = choiceArray;
            totalVotingPower = totalVotingPower;
            undecidedVotingPower = undecidedVotingPower;
        };
    };

    /// Calculates the current status of voting for a proposal.
    ///
    /// ```motoko
    /// let proposal : Proposal<MyContent, MyChoice> = ...;
    /// let votingThreshold : VotingThreshold = #percent({ percent = 50; quorum = ?25 });
    /// let equalChoice : (MyChoice, MyChoice) -> Bool = ...;
    /// let hashChoice : (MyChoice) -> Nat32 = ...;
    /// let forceEnd : Bool = false;
    /// switch (calculateVoteStatus(proposal, votingThreshold, equalChoice, hashChoice, forceEnd)) {
    ///   case (#determined(?choice)) { /* Proposal passed with choice */ };
    ///   case (#determined(null)) { /* Proposal rejected */ };
    ///   case (#undetermined) { /* Still voting */ };
    /// };
    /// ```
    public func calculateVoteStatus<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        votingThreshold : VotingThreshold,
        equalChoice : (TChoice, TChoice) -> Bool,
        hashChoice : (TChoice) -> Nat32,
        forceEnd : Bool,
    ) : ChoiceStatus<TChoice> {
        let { totalVotingPower; undecidedVotingPower; votingPowerByChoice } = buildVotingSummary(proposal, equalChoice, hashChoice);
        let votedVotingPower : Nat = totalVotingPower - undecidedVotingPower;

        // DEBUG: Add comprehensive logging
        Debug.print("🔍 VOTE_STATUS: =======CALCULATING VOTE STATUS=======");
        Debug.print("🔍 VOTE_STATUS: Proposal ID: " # debug_show(proposal.id));
        Debug.print("🔍 VOTE_STATUS: Total voting power: " # debug_show(totalVotingPower));
        Debug.print("🔍 VOTE_STATUS: Undecided voting power: " # debug_show(undecidedVotingPower));
        Debug.print("🔍 VOTE_STATUS: Voted voting power: " # debug_show(votedVotingPower));
        Debug.print("🔍 VOTE_STATUS: Force end: " # debug_show(forceEnd));
        Debug.print("🔍 VOTE_STATUS: Voting mode: " # debug_show(proposal.votingMode));
        Debug.print("🔍 VOTE_STATUS: Choice count: " # debug_show(votingPowerByChoice.size()));
        for (i in votingPowerByChoice.keys()) {
            Debug.print("🔍 VOTE_STATUS: Choice " # debug_show(i) # " power: " # debug_show(votingPowerByChoice[i].votingPower));
        };

        switch (votingThreshold) {
            case (#percent({ percent; quorum })) {
                Debug.print("🔍 VOTE_STATUS: Threshold percent: " # debug_show(percent));
                Debug.print("🔍 VOTE_STATUS: Quorum percent: " # debug_show(quorum));
                
                let quorumThreshold = switch (quorum) {
                    case (null) 0;
                    case (?q) calculateFromPercent(q, totalVotingPower, false);
                };
                Debug.print("🔍 VOTE_STATUS: Quorum threshold: " # debug_show(quorumThreshold));

                // The proposal must reach the quorum threshold in any case
                if (votedVotingPower >= quorumThreshold) {
                    Debug.print("🔍 VOTE_STATUS: ✅ Quorum threshold met");
                    
                    let hasEnded = forceEnd or (
                        switch (proposal.timeEnd) {
                            case (?timeEnd) timeEnd <= Time.now();
                            case (null) false; // No end time means it hasn't ended
                        }
                    );
                    Debug.print("🔍 VOTE_STATUS: Has ended: " # debug_show(hasEnded));

                    let voteThreshold = if (hasEnded) {
                        // If the proposal has reached the end time, it passes if the votes are above the threshold of the VOTED voting power
                        let threshold = calculateFromPercent(percent, votedVotingPower, true);
                        Debug.print("🔍 VOTE_STATUS: Using VOTED voting power for threshold: " # debug_show(threshold));
                        threshold;
                    } else {
                        // If the proposal has not reached the end time, it passes if votes are above the threshold (+1) of the TOTAL voting power
                        let votingThreshold = calculateFromPercent(percent, totalVotingPower, true);
                        let finalThreshold = if (votingThreshold >= totalVotingPower) {
                            // Safety with low total voting power to make sure the proposal can pass
                            totalVotingPower;
                        } else {
                            votingThreshold;
                        };
                        Debug.print("🔍 VOTE_STATUS: Using TOTAL voting power for threshold: " # debug_show(finalThreshold));
                        finalThreshold;
                    };
                    Debug.print("🔍 VOTE_STATUS: Final vote threshold: " # debug_show(voteThreshold));

                    let pluralityChoices = {
                        var votingPower = 0;
                        choices = Buffer.Buffer<TChoice>(1);
                    };
                    for (choice in votingPowerByChoice.vals()) {
                        Debug.print("🔍 VOTE_STATUS: Processing choice with power: " # debug_show(choice.votingPower));
                        if (choice.votingPower > pluralityChoices.votingPower) {
                            pluralityChoices.votingPower := choice.votingPower;
                            pluralityChoices.choices.clear();
                            pluralityChoices.choices.add(choice.choice);
                            Debug.print("🔍 VOTE_STATUS: New leading choice with power: " # debug_show(choice.votingPower));
                        } else if (choice.votingPower == pluralityChoices.votingPower) {
                            pluralityChoices.choices.add(choice.choice);
                            Debug.print("🔍 VOTE_STATUS: Tied choice with power: " # debug_show(choice.votingPower));
                        };
                    };
                    
                    Debug.print("🔍 VOTE_STATUS: Winning choice count: " # debug_show(pluralityChoices.choices.size()));
                    Debug.print("🔍 VOTE_STATUS: Winning choice power: " # debug_show(pluralityChoices.votingPower));

                    if (pluralityChoices.choices.size() == 1) {
                        if (pluralityChoices.votingPower >= voteThreshold) {
                            Debug.print("🔍 VOTE_STATUS: ✅ Threshold met with single choice");
                            // Real-time proposals should NOT auto-execute, even when threshold is reached
                            switch (proposal.votingMode) {
                                case (#dynamic(_)) {

                                  if(hasEnded) {
                                    Debug.print("🔍 VOTE_STATUS: Dynamic proposal - returning determined with choice");
                                    let winningChoice = Buffer.toArray(pluralityChoices.choices)[0];
                                    
                                    return #determined(?winningChoice);
                                  } else {
                                        Debug.print("🔍 VOTE_STATUS: Dynamic proposal - returning undetermined for manual execution");
                                    return #undetermined; // Stay undetermined for manual execution
                                  };
                                };
                                case (#snapshot(_)) {
                                    let winningChoice = Buffer.toArray(pluralityChoices.choices)[0];
                                    Debug.print("🔍 VOTE_STATUS: Snapshot proposal - returning determined with choice");
                                    return #determined(?winningChoice);
                                };
                            };
                        } else {
                            Debug.print("🔍 VOTE_STATUS: ❌ Threshold not met: " # debug_show(pluralityChoices.votingPower) # " < " # debug_show(voteThreshold));
                        };
                    } else if (pluralityChoices.choices.size() > 1) {
                        Debug.print("🔍 VOTE_STATUS: Multiple tied choices");
                        // If everyone has voted and there is a tie -> undetermined
                        if (undecidedVotingPower <= 0) {
                            Debug.print("🔍 VOTE_STATUS: Everyone voted, tie result -> null");
                            return #determined(null);
                        };
                    } else {
                        Debug.print("🔍 VOTE_STATUS: No choices found");
                    };
                } else {
                    Debug.print("🔍 VOTE_STATUS: ❌ Quorum not met: " # debug_show(votedVotingPower) # " < " # debug_show(quorumThreshold));
                };
            };
        };
        Debug.print("🔍 VOTE_STATUS: Returning undetermined");
        return #undetermined;
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
    /// let proposal : Proposal<MyContent, MyChoice> = create(id, proposerId, content, members, timeStart, timeEnd, votingMode);
    /// ```
    public func create<TProposalContent, TChoice>(
        id : Nat,
        proposerId : Principal,
        content : TProposalContent,
        members : [Member],
        timeStart : Time.Time,
        timeEnd : ?Time.Time,
        votingMode : VotingMode,
    ) : Proposal<TProposalContent, TChoice> {
        let votes = BTree.init<Principal, Vote<TChoice>>(null);
        for (member in members.vals()) {
            ignore BTree.insert(
                votes,
                Principal.compare,
                member.id,
                { choice = null; votingPower = member.votingPower },
            );
        };
        {
            id = id;
            proposerId = proposerId;
            content = content;
            timeStart = timeStart;
            timeEnd = timeEnd;
            votes = votes;
            status = #open;
            votingMode = votingMode;
        };
    };

    private func calculateFromPercent(percent : Nat, total : Nat, greaterThan : Bool) : Nat {
        let threshold = Float.fromInt(percent) / 100.0 * Float.fromInt(total);
        // If the threshold is an integer, add 1 to make sure the proposal passes
        let ceilThreshold = Float.toInt(Float.ceil(threshold));
        let fixedThreshold : Int = if (greaterThan and ceilThreshold == Float.toInt(Float.floor(threshold))) {
            // If the threshold is an integer, add 1 to make sure the proposal passes
            ceilThreshold + 1;
        } else {
            ceilThreshold;
        };
        Int.abs(fixedThreshold);
    };
};
