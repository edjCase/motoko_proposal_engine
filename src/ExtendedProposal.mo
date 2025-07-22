import Time "mo:base/Time";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Option "mo:base/Option";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Float "mo:base/Float";
import Int "mo:base/Int";
import IterTools "mo:itertools/Iter";
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

    public type ProposalMode = {
        #fixedMembers; // Traditional mode with fixed member list
        #realTime; // Real-time mode with dynamic member addition
    };

    public type Proposal<TProposalContent, TChoice> = {
        id : Nat;
        proposerId : Principal;
        timeStart : Int;
        timeEnd : ?Int;
        content : TProposalContent;
        votes : [(Principal, Vote<TChoice>)];
        status : ProposalStatus<TChoice>;
        mode : ProposalMode;
        totalVotingPower : ?Nat; // For real-time proposals
        members : ?BTree.BTree<Principal, Member>; // For real-time proposals
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
        votes : [(Principal, Vote<TChoice>)];
        status : ProposalStatus<TChoice>;
    };

    public type AddMemberError = {
        #alreadyExists;
        #notRealTimeProposal;
        #votingClosed;
    };

    public func addMember<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        member : Member,
    ) : Result.Result<Proposal<TProposalContent, TChoice>, AddMemberError> {
        switch (proposal.mode) {
            case (#fixedMembers) {
                return #err(#notRealTimeProposal);
            };
            case (#realTime) {
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

                let ?membersMap = proposal.members else return #err(#notRealTimeProposal);
                
                // Check if member already exists
                switch (BTree.get(membersMap, Principal.compare, member.id)) {
                    case (?_) return #err(#alreadyExists);
                    case (null) ();
                };

                // Add member to BTree
                ignore BTree.insert(membersMap, Principal.compare, member.id, member);

                // Add vote entry
                let newVotes = Buffer.fromArray<(Principal, Vote<TChoice>)>(proposal.votes);
                newVotes.add((member.id, { choice = null; votingPower = member.votingPower }));

                let updatedProposal = {
                    proposal with
                    votes = Buffer.toArray(newVotes);
                };

                #ok(updatedProposal);
            };
        };
    };

    public func getVote<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        voterId : Principal,
    ) : ?Vote<TChoice> {
        let ?(_, vote) = IterTools.find(
            proposal.votes.vals(),
            func((id, _) : (Principal, Vote<TChoice>)) : Bool = id == voterId,
        ) else return null;
        ?vote;
    };

    public func vote<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        voterId : Principal,
        vote : TChoice,
        allowVoteChange : Bool,
    ) : Result.Result<VoteOk<TProposalContent, TChoice>, VoteError> {
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

        // For real-time proposals, check if voter is eligible by looking in the members BTree
        switch (proposal.mode) {
            case (#realTime) {
                let ?membersMap = proposal.members else return #err(#notEligible);
                switch (BTree.get(membersMap, Principal.compare, voterId)) {
                    case (null) return #err(#notEligible);
                    case (?_) (); // Member exists, proceed
                };
            };
            case (#fixedMembers) (); // Original eligibility check below will apply
        };

        let ?voteIndex = IterTools.findIndex(
            proposal.votes.vals(),
            func((id, _) : (Principal, Vote<TChoice>)) : Bool = id == voterId,
        ) else return #err(#notEligible); // Only allow members to vote who existed when the proposal was created

        let (_, existingVote) = proposal.votes[voteIndex];
        if (not allowVoteChange) {
            let null = existingVote.choice else return #err(#alreadyVoted);
        };

        let newVotes = Buffer.fromArray<(Principal, Vote<TChoice>)>(proposal.votes);
        newVotes.put(voteIndex, (voterId, { existingVote with choice = ?vote }));

        let updatedProposal = {
            proposal with
            votes = Buffer.toArray(newVotes);
        };

        #ok({
            updatedProposal = updatedProposal;
        });
    };

    public func buildVotingSummary<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        equal : (TChoice, TChoice) -> Bool,
        hash : (TChoice) -> Nat32,
    ) : VotingSummary<TChoice> {
        let choices = HashMap.HashMap<TChoice, Nat>(5, equal, hash);
        var undecidedVotingPower = 0;
        var totalVotingPower = 0;
        for ((voterId, vote) in proposal.votes.vals()) {
            switch (vote.choice) {
                case (null) {
                    undecidedVotingPower += vote.votingPower;
                };
                case (?choice) {
                    let currentVotingPower = Option.get(choices.get(choice), 0);
                    choices.put(choice, currentVotingPower + vote.votingPower);
                };
            };
            totalVotingPower += vote.votingPower;
        };

        {
            votingPowerByChoice = choices.entries()
            |> Iter.map(
                _,
                func((choice, votingPower) : (TChoice, Nat)) : ChoiceVotingPower<TChoice> = {
                    choice = choice;
                    votingPower = votingPower;
                },
            )
            |> Iter.toArray(_);
            totalVotingPower = totalVotingPower;
            undecidedVotingPower = undecidedVotingPower;
        };
    };

    public func calculateVoteStatus<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        votingThreshold : VotingThreshold,
        equalChoice : (TChoice, TChoice) -> Bool,
        hashChoice : (TChoice) -> Nat32,
        forceEnd : Bool,
    ) : ChoiceStatus<TChoice> {
        let { totalVotingPower; undecidedVotingPower; votingPowerByChoice } = buildVotingSummary(proposal, equalChoice, hashChoice);
        let votedVotingPower : Nat = totalVotingPower - undecidedVotingPower;
        
        switch (votingThreshold) {
            case (#percent({ percent; quorum })) {
                let quorumThreshold = switch (quorum) {
                    case (null) 0;
                    case (?q) calculateFromPercent(q, totalVotingPower, false);
                };
                
                // For real-time proposals, use the declared total voting power instead of current votes
                let effectiveTotalVotingPower = switch (proposal.mode) {
                    case (#realTime) {
                        switch (proposal.totalVotingPower) {
                            case (?total) total;
                            case (null) totalVotingPower; // Fallback to calculated
                        };
                    };
                    case (#fixedMembers) totalVotingPower;
                };
                
                // The proposal must reach the quorum threshold in any case
                if (votedVotingPower >= quorumThreshold) {
                    let hasEnded = forceEnd or (
                        switch (proposal.timeEnd) {
                            case (?timeEnd) timeEnd <= Time.now();
                            case (null) false;
                        }
                    );
                    
                    let voteThreshold = if (hasEnded) {
                        // If the proposal has reached the end time, it passes if the votes are above the threshold of the VOTED voting power
                        calculateFromPercent(percent, votedVotingPower, true);
                    } else {
                        // Use the effective total voting power for threshold calculation
                        let votingThreshold = calculateFromPercent(percent, effectiveTotalVotingPower, true);
                        if (votingThreshold >= effectiveTotalVotingPower) {
                            // Safety with low total voting power to make sure the proposal can pass
                            effectiveTotalVotingPower;
                        } else {
                            votingThreshold;
                        };
                    };
                    
                    let pluralityChoices = {
                        var votingPower = 0;
                        choices = Buffer.Buffer<TChoice>(1);
                    };
                    for (choice in votingPowerByChoice.vals()) {
                        if (choice.votingPower > pluralityChoices.votingPower) {
                            pluralityChoices.votingPower := choice.votingPower;
                            pluralityChoices.choices.clear();
                            pluralityChoices.choices.add(choice.choice);
                        } else if (choice.votingPower == pluralityChoices.votingPower) {
                            pluralityChoices.choices.add(choice.choice);
                        };
                    };
                    
                    if (pluralityChoices.choices.size() == 1) {
                        if (pluralityChoices.votingPower >= voteThreshold) {
                            // Real-time proposals should NOT auto-execute, even when threshold is reached
                            switch (proposal.mode) {
                                case (#realTime) return #undetermined; // Stay undetermined for manual execution
                                case (#fixedMembers) return #determined(?pluralityChoices.choices.get(0));
                            };
                        };
                    } else if (pluralityChoices.choices.size() > 1) {
                        // For real-time proposals, only consider it a tie if we've reached the total voting power
                        switch (proposal.mode) {
                            case (#realTime) {
                                switch (proposal.totalVotingPower) {
                                    case (?total) {
                                        if (totalVotingPower >= total) {
                                            return #determined(null);
                                        };
                                    };
                                    case (null) ();
                                };
                            };
                            case (#fixedMembers) {
                                // If everyone has voted and there is a tie -> undetermined
                                if (undecidedVotingPower <= 0) {
                                    return #determined(null);
                                };
                            };
                        };
                    };
                };
            };
        };
        return #undetermined;
    };


    public func create<TProposalContent, TChoice>(
        id : Nat,
        proposerId : Principal,
        content : TProposalContent,
        members : [Member],
        timeStart : Time.Time,
        timeEnd : ?Time.Time,
    ) : Proposal<TProposalContent, TChoice> {
        let votes = members.vals()
        |> Iter.map<Member, (Principal, Vote<TChoice>)>(
            _,
            func(member : Member) : (Principal, Vote<TChoice>) = (member.id, { choice = null; votingPower = member.votingPower }),
        )
        |> Iter.toArray(_);
        {
            id = id;
            proposerId = proposerId;
            content = content;
            timeStart = timeStart;
            timeEnd = timeEnd;
            votes = votes;
            status = #open;
            mode = #fixedMembers;
            totalVotingPower = null;
            members = null;
        };
    };

    public func createRealTime<TProposalContent, TChoice>(
        id : Nat,
        proposerId : Principal,
        content : TProposalContent,
        totalVotingPower : Nat,
        timeStart : Time.Time,
        timeEnd : ?Time.Time,
    ) : Proposal<TProposalContent, TChoice> {
        let membersMap = BTree.init<Principal, Member>(?32);
        {
            id = id;
            proposerId = proposerId;
            content = content;
            timeStart = timeStart;
            timeEnd = timeEnd;
            votes = [];
            status = #open;
            mode = #realTime;
            totalVotingPower = ?totalVotingPower;
            members = ?membersMap;
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
