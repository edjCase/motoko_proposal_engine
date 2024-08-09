import Principal "mo:base/Principal";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Order "mo:base/Order";
import IterTools "mo:itertools/Iter";
import Result "mo:base/Result";
import Option "mo:base/Option";

module {

    public type StableData<TProposalContent, TChoice> = {
        proposals : [Proposal<TProposalContent, TChoice>];
        proposalDuration : ?Duration;
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

    public type Proposal<TProposalContent, TChoice> = {
        id : Nat;
        proposerId : Principal;
        timeStart : Int;
        timeEnd : ?Int;
        endTimerId : ?Nat;
        content : TProposalContent;
        votes : [(Principal, Vote<TChoice>)];
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
        value : ?TChoice;
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

    type MutableProposal<TProposalContent, TChoice> = {
        id : Nat;
        proposerId : Principal;
        timeStart : Int;
        timeEnd : ?Int;
        var endTimerId : ?Nat;
        content : TProposalContent;
        votes : HashMap.HashMap<Principal, Vote<TChoice>>;
        var status : ProposalStatus<TChoice>;
        votingSummary : VotingSummary<TChoice>; // TODO remove and calculate on demand?
    };

    type VotingSummary<TChoice> = {
        values : HashMap.HashMap<TChoice, Nat>;
        var notVoted : Nat;
    };

    public class ProposalEngine<system, TProposalContent, TChoice>(
        data : StableData<TProposalContent, TChoice>,
        onProposalExecute : (?TChoice, Proposal<TProposalContent, TChoice>) -> async* Result.Result<(), Text>,
        onProposalValidate : TProposalContent -> async* Result.Result<(), [Text]>,
        equalChoice : (TChoice, TChoice) -> Bool,
        hashChoice : (TChoice) -> Nat32,
    ) {

        let proposalsIter = data.proposals.vals()
        |> Iter.map<Proposal<TProposalContent, TChoice>, (Nat, MutableProposal<TProposalContent, TChoice>)>(
            _,
            func(proposal : Proposal<TProposalContent, TChoice>) : (Nat, MutableProposal<TProposalContent, TChoice>) {
                let mutableProposal = toMutableProposal<TProposalContent, TChoice>(proposal, equalChoice, hashChoice);
                (
                    proposal.id,
                    mutableProposal,
                );
            },
        );

        var proposals = HashMap.fromIter<Nat, MutableProposal<TProposalContent, TChoice>>(proposalsIter, 0, Nat.equal, Nat32.fromNat);
        var nextProposalId = data.proposals.size() + 1; // TODO make last proposal + 1

        var proposalDuration = data.proposalDuration;
        var votingThreshold = data.votingThreshold;

        private func resetEndTimers<system>() {
            for (proposal in proposals.vals()) {
                switch (proposal.endTimerId) {
                    case (null) ();
                    case (?id) Timer.cancelTimer(id);
                };
                proposal.endTimerId := null;
                switch (proposal.status) {
                    case (#open) {
                        switch (proposalDuration) {
                            case (?proposalDuration) {
                                let proposalDurationNanoseconds = durationToNanoseconds(proposalDuration);
                                let endTimerId = createEndTimer<system>(proposal.id, proposalDurationNanoseconds);
                                proposal.endTimerId := ?endTimerId;
                            };
                            case (null) (); // Skip timer creation
                        };
                    };
                    case (_) (); // Skip timer creation
                };
            };
        };
        /// Returns a proposal by its Id.
        ///
        /// ```motoko
        /// let proposalId : Nat = 1;
        /// let ?proposal : ?Proposal<TProposalContent, TChoice> = proposalEngine.getProposal(proposalId) else Debug.trap("Proposal not found");
        /// ```
        public func getProposal(id : Nat) : ?Proposal<TProposalContent, TChoice> {
            let ?proposal = proposals.get(id) else return null;
            ?{
                proposal with
                endTimerId = proposal.endTimerId;
                votes = Iter.toArray(proposal.votes.entries());
                status = proposal.status;
            };
        };

        /// Retrieves a paged list of proposals.
        ///
        /// ```motoko
        /// let count : Nat = 10; // Max proposals to return
        /// let offset : Nat = 0; // Proposals to skip
        /// let pagedResult : PagedResult<Proposal<ProposalContent>> = proposalEngine.getProposals(count, offset);
        /// ```
        public func getProposals(count : Nat, offset : Nat) : PagedResult<Proposal<TProposalContent, TChoice>> {
            let vals = proposals.vals()
            |> Iter.map(
                _,
                func(proposal : MutableProposal<TProposalContent, TChoice>) : Proposal<TProposalContent, TChoice> = fromMutableProposal(proposal),
            )
            |> IterTools.sort(
                _,
                func(proposalA : Proposal<TProposalContent, TChoice>, proposalB : Proposal<TProposalContent, TChoice>) : Order.Order {
                    Int.compare(proposalA.timeStart, proposalB.timeStart);
                },
            )
            |> IterTools.skip(_, offset)
            |> IterTools.take(_, count)
            |> Iter.toArray(_);
            {
                data = vals;
                offset = offset;
                count = count;
                total = proposals.size();
            };
        };

        /// Casts a vote on a proposal for the specified voter.
        /// Will auto execute/reject the proposal if the voting threshold is reached.
        /// async* is due to potential execution of the proposal.
        ///
        /// ```motoko
        /// let proposalId : Nat = 1;
        /// let voterId : Principal = ...;
        /// let vote : Bool = true; // true for yes, false for no
        /// switch (await* proposalEngine.vote(proposalId, voterId, vote)) {
        ///   case (#ok) { /* Vote successful */ };
        ///   case (#err(error)) { /* Handle error */ };
        /// };
        /// ```
        public func vote(proposalId : Nat, voterId : Principal, vote : TChoice) : async* Result.Result<(), VoteError> {
            let ?proposal = proposals.get(proposalId) else return #err(#proposalNotFound);
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
            let ?existingVote = proposal.votes.get(voterId) else return #err(#notAuthorized); // Only allow members to vote who existed when the proposal was created
            let null = existingVote.value else return #err(#alreadyVoted);
            await* voteInternal(proposal, voterId, vote, existingVote.votingPower);
            #ok;
        };
        /// Creates a new proposal.
        /// The proposer does NOT automatically vote on the proposal.
        /// async* is due to potential execution of the proposal and validation function.
        ///
        /// ```motoko
        /// let proposerId = ...;
        /// let content = { /* Your proposal content here */ };
        /// let members = [...]; // Snapshot of members to vote on the proposal
        /// switch (await* proposalEngine.createProposal(proposerId, content, members)) {
        ///   case (#ok(proposalId)) { /* Use new proposal ID */ };
        ///   case (#err(error)) { /* Handle error */ };
        /// };
        /// ```
        public func createProposal<system>(
            proposerId : Principal,
            content : TProposalContent,
            members : [Member],
        ) : async* Result.Result<Nat, CreateProposalError> {

            switch (await* onProposalValidate(content)) {
                case (#ok) ();
                case (#err(errors)) {
                    return #err(#invalid(errors));
                };
            };

            let now = Time.now();
            let votes = HashMap.HashMap<Principal, Vote<TChoice>>(0, Principal.equal, Principal.hash);
            // Take snapshot of members at the time of proposal creation
            for (member in members.vals()) {
                votes.put(
                    member.id,
                    {
                        value = null;
                        votingPower = member.votingPower;
                    },
                );
            };
            let proposalId = nextProposalId;
            let (timeEnd, endTimerId) : (?Int, ?Nat) = switch (proposalDuration) {
                case (?proposalDuration) {
                    let proposalDurationNanoseconds = durationToNanoseconds(proposalDuration);
                    let timerId = createEndTimer<system>(proposalId, proposalDurationNanoseconds);
                    (?(now + proposalDurationNanoseconds), ?timerId);
                };
                case (null) (null, null);
            };
            let proposal : MutableProposal<TProposalContent, TChoice> = {
                id = proposalId;
                proposerId = proposerId;
                content = content;
                timeStart = now;
                timeEnd = timeEnd;
                var endTimerId = endTimerId;
                votes = votes;
                var status = #open;
                votingSummary = buildVotingSummary(votes, equalChoice, hashChoice);
            };
            proposals.put(nextProposalId, proposal);
            nextProposalId += 1;
            #ok(proposalId);
        };

        public func endProposal(proposalId : Nat) : async* Result.Result<(), { #alreadyEnded }> {
            let ?mutableProposal = proposals.get(proposalId) else Debug.trap("Proposal not found for onProposalEnd: " # Nat.toText(proposalId));
            switch (mutableProposal.status) {
                case (#open) {
                    let choice = switch (calculateVoteStatus(mutableProposal, true)) {
                        case (#determined(choice)) choice;
                        case (#undetermined) null;
                    };
                    await* executeProposal(mutableProposal, choice);
                    #ok;
                };
                case (_) #err(#alreadyEnded);
            };
        };

        /// Converts the current state to stable data for upgrades.
        ///
        /// ```motoko
        /// let stableData : StableData<ProposalContent> = proposalEngine.toStableData();
        /// ```
        public func toStableData() : StableData<TProposalContent, TChoice> {
            let proposalsArray = proposals.entries()
            |> Iter.map(
                _,
                func((_, v) : (Nat, MutableProposal<TProposalContent, TChoice>)) : Proposal<TProposalContent, TChoice> = fromMutableProposal<TProposalContent, TChoice>(v),
            )
            |> Iter.toArray(_);

            {
                proposals = proposalsArray;
                proposalDuration = proposalDuration;
                votingThreshold = votingThreshold;
            };
        };

        private func voteInternal(
            proposal : MutableProposal<TProposalContent, TChoice>,
            voterId : Principal,
            vote : TChoice,
            votingPower : Nat,
        ) : async* () {
            proposal.votes.put(
                voterId,
                {
                    value = ?vote;
                    votingPower = votingPower;
                },
            );
            proposal.votingSummary.notVoted -= votingPower;
            proposal.votingSummary.values.put(
                vote,
                Option.get(proposal.votingSummary.values.get(vote), 0) + votingPower,
            );
            switch (calculateVoteStatus(proposal, false)) {
                case (#determined(choice)) await* executeProposal(proposal, choice);
                case (#undetermined) ();
            };
        };

        private func durationToNanoseconds(duration : Duration) : Nat {
            switch (duration) {
                case (#days(d)) d * 24 * 60 * 60 * 1_000_000_000;
                case (#nanoseconds(n)) n;
            };
        };

        private func createEndTimer<system>(
            proposalId : Nat,
            proposalDurationNanoseconds : Nat,
        ) : Nat {
            Timer.setTimer<system>(
                #nanoseconds(proposalDurationNanoseconds),
                func() : async () {
                    switch (await* endProposal(proposalId)) {
                        case (#ok) ();
                        case (#err(#alreadyEnded)) {
                            Debug.print("EndTimer: Proposal already ended: " # Nat.toText(proposalId));
                        };
                    };
                },
            );
        };

        private func executeProposal(
            mutableProposal : MutableProposal<TProposalContent, TChoice>,
            choice : ?TChoice,
        ) : async* () {
            // TODO executing
            switch (mutableProposal.endTimerId) {
                case (null) ();
                case (?id) Timer.cancelTimer(id);
            };
            mutableProposal.endTimerId := null;
            let proposal = fromMutableProposal(mutableProposal);

            let executingTime = Time.now();
            mutableProposal.status := #executing({
                executingTime = executingTime;
                choice = choice;
            });

            let newStatus : ProposalStatus<TChoice> = try {
                switch (await* onProposalExecute(choice, proposal)) {
                    case (#ok) #executed({
                        executingTime = executingTime;
                        executedTime = Time.now();
                        choice = choice;
                    });
                    case (#err(e)) #failedToExecute({
                        executingTime = executingTime;
                        failedTime = Time.now();
                        choice = choice;
                        error = e;
                    });
                };
            } catch (e) {
                #failedToExecute({
                    executingTime = executingTime;
                    failedTime = Time.now();
                    choice = choice;
                    error = Error.message(e);
                });
            };
            mutableProposal.status := newStatus;
        };

        private func calculateVoteStatus(
            proposal : MutableProposal<TProposalContent, TChoice>,
            forceEnd : Bool,
        ) : {
            #undetermined;
            #determined : ?TChoice;
        } {
            let votedVotingPower = proposal.votes.vals()
            |> Iter.map(
                _,
                func(vote : Vote<TChoice>) : Nat {
                    switch (vote.value) {
                        case (null) 0;
                        case (?_) vote.votingPower;
                    };
                },
            )
            |> IterTools.sum(_, func(a : Nat, b : Nat) : Nat { a + b })
            |> Option.get(_, 0);
            let totalVotingPower = votedVotingPower + proposal.votingSummary.notVoted;
            switch (votingThreshold) {
                case (#percent({ percent; quorum })) {
                    let quorumThreshold = switch (quorum) {
                        case (null) 0;
                        case (?q) calculateFromPercent(q, totalVotingPower, false);
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
                            let votedPercent = votedVotingPower / totalVotingPower;
                            calculateFromPercent(percent, votedVotingPower, true);
                        } else {
                            // If the proposal has not reached the end time, it passes if votes are above the threshold (+1) of the TOTAL voting power
                            let votingThreshold = calculateFromPercent(percent, totalVotingPower, true);
                            if (votingThreshold >= totalVotingPower) {
                                // Safety with low total voting power to make sure the proposal can pass
                                totalVotingPower;
                            } else {
                                votingThreshold;
                            };
                        };
                        let pluralityChoices = {
                            var votingPower = 0;
                            choices = Buffer.Buffer<TChoice>(1);
                        };
                        for (choice in proposal.votingSummary.values.keys()) {
                            let votingPower = Option.get(proposal.votingSummary.values.get(choice), 0);
                            if (votingPower > pluralityChoices.votingPower) {
                                pluralityChoices.votingPower := votingPower;
                                pluralityChoices.choices.clear();
                                pluralityChoices.choices.add(choice);
                            } else if (votingPower == pluralityChoices.votingPower) {
                                pluralityChoices.choices.add(choice);
                            };
                        };
                        if (pluralityChoices.choices.size() == 1) {
                            if (pluralityChoices.votingPower >= voteThreshold) {
                                return #determined(?pluralityChoices.choices.get(0));
                            };
                        } else if (pluralityChoices.choices.size() > 1) {
                            // If everyone has voted and there is a tie -> undetermined
                            if (proposal.votingSummary.notVoted <= 0) {
                                return #determined(null);
                            };
                        };
                    };
                };
            };
            return #undetermined;
        };
        resetEndTimers<system>();

    };

    private func fromMutableProposal<TProposalContent, TChoice>(proposal : MutableProposal<TProposalContent, TChoice>) : Proposal<TProposalContent, TChoice> = {
        proposal with
        endTimerId = proposal.endTimerId;
        votes = Iter.toArray(proposal.votes.entries());
        status = proposal.status;
    };

    private func toMutableProposal<TProposalContent, TChoice>(
        proposal : Proposal<TProposalContent, TChoice>,
        equalChoice : (TChoice, TChoice) -> Bool,
        hashChoice : (TChoice) -> Nat32,
    ) : MutableProposal<TProposalContent, TChoice> {
        let votes = HashMap.fromIter<Principal, Vote<TChoice>>(
            proposal.votes.vals(),
            proposal.votes.size(),
            Principal.equal,
            Principal.hash,
        );
        {
            proposal with
            var endTimerId = proposal.endTimerId;
            votes = votes;
            var status = proposal.status;
            votingSummary = buildVotingSummary<TChoice>(votes, equalChoice, hashChoice);
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

    private func buildVotingSummary<TChoice>(
        votes : HashMap.HashMap<Principal, Vote<TChoice>>,
        equal : (TChoice, TChoice) -> Bool,
        hash : (TChoice) -> Nat32,
    ) : VotingSummary<TChoice> {
        let votingSummary = {
            values = HashMap.HashMap<TChoice, Nat>(2, equal, hash);
            var notVoted = 0;
        };

        for (vote in votes.vals()) {
            switch (vote.value) {
                case (null) {
                    votingSummary.notVoted += vote.votingPower;
                };
                case (?v) {
                    let currentVotingPower = Option.get(votingSummary.values.get(v), 0);
                    votingSummary.values.put(v, currentVotingPower + vote.votingPower);
                };
            };
        };
        votingSummary;
    };

};
