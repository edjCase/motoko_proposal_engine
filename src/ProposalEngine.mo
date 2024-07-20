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
import Types "Types";

module {

    type MutableProposal<TProposalContent> = {
        id : Nat;
        proposerId : Principal;
        timeStart : Int;
        timeEnd : Int;
        var endTimerId : ?Nat;
        content : TProposalContent;
        votes : HashMap.HashMap<Principal, Types.Vote>;
        statusLog : Buffer.Buffer<Types.ProposalStatusLogEntry>;
        votingSummary : VotingSummary;
    };

    type VotingSummary = {
        var yes : Nat;
        var no : Nat;
        var notVoted : Nat;
    };

    /// Creates a new proposal engine.
    /// <system> is required for timers.
    ///
    /// ```motoko
    /// // Define your proposal content type
    /// type ProposalContent = { /* Your proposal type definition */ };
    /// // Intiialize with max proposal duration of 7 days, 50% voting threshold for auto execution and 20% quorum for execution after duration
    /// let data : Types.StableData<ProposalContent> = { proposals = [], proposalDuration = #days(7), votingThreshold = #percent({ percent = 50, quorum = ?20 }) };
    /// // Create function that runs on execution of a proposal. Return error message on failure.
    /// let onProposalExecute = func(proposal : Types.Proposal<ProposalContent>) : async* Result.Result<(), Text> { ... };
    /// // Create function that runs on rejection of a proposal
    /// let onProposalReject = func(proposal : Types.Proposal<ProposalContent>) : async* () { ... };
    /// // Create function that runs on validation of a proposal. Return validation errors on failure.
    /// let onProposalValidate = func(content : ProposalContent) : async* Result.Result<(), [Text]> { ... };
    /// let proposalEngine = ProposalEngine<system, ProposalContent>(data, onProposalExecute, onProposalReject, onProposalValidate);
    /// ```
    public class ProposalEngine<system, TProposalContent>(
        data : Types.StableData<TProposalContent>,
        onProposalExecute : Types.Proposal<TProposalContent> -> async* Result.Result<(), Text>,
        onProposalReject : Types.Proposal<TProposalContent> -> async* (),
        onProposalValidate : TProposalContent -> async* Result.Result<(), [Text]>,
    ) {
        func hashNat(n : Nat) : Nat32 = Nat32.fromNat(n); // TODO

        let proposalsIter = data.proposals.vals()
        |> Iter.map<Types.Proposal<TProposalContent>, (Nat, MutableProposal<TProposalContent>)>(
            _,
            func(proposal : Types.Proposal<TProposalContent>) : (Nat, MutableProposal<TProposalContent>) {
                let mutableProposal = toMutableProposal(proposal);
                (
                    proposal.id,
                    mutableProposal,
                );
            },
        );

        var proposals = HashMap.fromIter<Nat, MutableProposal<TProposalContent>>(proposalsIter, 0, Nat.equal, hashNat);
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
                let currentStatus = getProposalStatus(proposal.statusLog);
                if (currentStatus == #open) {
                    let proposalDurationNanoseconds = durationToNanoseconds(proposalDuration);
                    let endTimerId = createEndTimer<system>(proposal.id, proposalDurationNanoseconds);
                    proposal.endTimerId := ?endTimerId;
                };
            };
        };
        /// Returns a proposal by its Id.
        ///
        /// ```motoko
        /// let proposalId : Nat = 1;
        /// let ?proposal : ?Types.Proposal<TProposalContent> = proposalEngine.getProposal(proposalId) else Debug.trap("Proposal not found");
        /// ```
        public func getProposal(id : Nat) : ?Types.Proposal<TProposalContent> {
            let ?proposal = proposals.get(id) else return null;
            ?{
                proposal with
                endTimerId = proposal.endTimerId;
                votes = Iter.toArray(proposal.votes.entries());
                statusLog = Buffer.toArray(proposal.statusLog);
                votingSummary = {
                    yes = proposal.votingSummary.yes;
                    no = proposal.votingSummary.no;
                    notVoted = proposal.votingSummary.notVoted;
                };
            };
        };

        /// Retrieves a paged list of proposals.
        ///
        /// ```motoko
        /// let count : Nat = 10; // Max proposals to return
        /// let offset : Nat = 0; // Proposals to skip
        /// let pagedResult : Types.PagedResult<Types.Proposal<ProposalContent>> = proposalEngine.getProposals(count, offset);
        /// ```
        public func getProposals(count : Nat, offset : Nat) : Types.PagedResult<Types.Proposal<TProposalContent>> {
            let vals = proposals.vals()
            |> Iter.map(
                _,
                func(proposal : MutableProposal<TProposalContent>) : Types.Proposal<TProposalContent> = fromMutableProposal(proposal),
            )
            |> IterTools.sort(
                _,
                func(proposalA : Types.Proposal<TProposalContent>, proposalB : Types.Proposal<TProposalContent>) : Order.Order {
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
        public func vote(proposalId : Nat, voterId : Principal, vote : Bool) : async* Result.Result<(), Types.VoteError> {
            let ?proposal = proposals.get(proposalId) else return #err(#proposalNotFound);
            let now = Time.now();
            let currentStatus = getProposalStatus(proposal.statusLog);
            if (proposal.timeStart > now or proposal.timeEnd < now or currentStatus != #open) {
                return #err(#votingClosed);
            };
            let ?existingVote = proposal.votes.get(voterId) else return #err(#notAuthorized); // Only allow members to vote who existed when the proposal was created
            if (existingVote.value != null) {
                return #err(#alreadyVoted);
            };
            await* voteInternal(proposal, voterId, vote, existingVote.votingPower);
            #ok;
        };
        /// Creates a new proposal.
        /// The proposer is automatically voted yes.
        /// The proposal will be auto executed if the voting threshold is reached (from proposer).
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
            members : [Types.Member],
        ) : async* Result.Result<Nat, Types.CreateProposalError> {

            switch (await* onProposalValidate(content)) {
                case (#ok) ();
                case (#err(errors)) {
                    return #err(#invalid(errors));
                };
            };

            let now = Time.now();
            let votes = HashMap.HashMap<Principal, Types.Vote>(0, Principal.equal, Principal.hash);
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
            let proposalDurationNanoseconds = durationToNanoseconds(proposalDuration);
            let endTimerId = createEndTimer<system>(proposalId, proposalDurationNanoseconds);
            let proposal : MutableProposal<TProposalContent> = {
                id = proposalId;
                proposerId = proposerId;
                content = content;
                timeStart = now;
                timeEnd = now + proposalDurationNanoseconds;
                var endTimerId = ?endTimerId;
                votes = votes;
                statusLog = Buffer.Buffer<Types.ProposalStatusLogEntry>(0);
                votingSummary = buildVotingSummary(votes);
            };
            proposals.put(nextProposalId, proposal);
            nextProposalId += 1;
            // Automatically vote yes for the proposer
            switch (IterTools.find(members.vals(), func(m : Types.Member) : Bool { m.id == proposerId })) {
                case (null) (); // Skip if proposer is not a member
                case (?proposerMember) {
                    // Vote yes for proposer
                    await* voteInternal(proposal, proposerId, true, proposerMember.votingPower);
                };
            };
            #ok(proposalId);
        };

        /// Converts the current state to stable data for upgrades.
        ///
        /// ```motoko
        /// let stableData : Types.StableData<ProposalContent> = proposalEngine.toStableData();
        /// ```
        public func toStableData() : Types.StableData<TProposalContent> {
            let proposalsArray = proposals.entries()
            |> Iter.map(
                _,
                func((_, v) : (Nat, MutableProposal<TProposalContent>)) : Types.Proposal<TProposalContent> = fromMutableProposal<TProposalContent>(v),
            )
            |> Iter.toArray(_);

            {
                proposals = proposalsArray;
                proposalDuration = proposalDuration;
                votingThreshold = votingThreshold;
            };
        };

        private func voteInternal(
            proposal : MutableProposal<TProposalContent>,
            voterId : Principal,
            vote : Bool,
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
            if (vote) {
                proposal.votingSummary.yes += votingPower;
            } else {
                proposal.votingSummary.no += votingPower;
            };
            switch (calculateVoteStatus(proposal)) {
                case (#passed) {
                    await* executeOrRejectProposal(proposal, true);
                };
                case (#rejected) {
                    await* executeOrRejectProposal(proposal, false);
                };
                case (#undetermined) ();
            };
        };

        private func durationToNanoseconds(duration : Types.Duration) : Nat {
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
                    switch (await* onProposalEnd(proposalId)) {
                        case (#ok) ();
                        case (#alreadyEnded) {
                            Debug.print("EndTimer: Proposal already ended: " # Nat.toText(proposalId));
                        };
                    };
                },
            );
        };

        private func onProposalEnd(proposalId : Nat) : async* {
            #ok;
            #alreadyEnded;
        } {
            let ?mutableProposal = proposals.get(proposalId) else Debug.trap("Proposal not found for onProposalEnd: " # Nat.toText(proposalId));
            switch (getProposalStatus(mutableProposal.statusLog)) {
                case (#open) {
                    let passed = switch (calculateVoteStatus(mutableProposal)) {
                        case (#passed) true;
                        case (#rejected or #undetermined) false;
                    };
                    await* executeOrRejectProposal(mutableProposal, passed);
                    #ok;
                };
                case (_) #alreadyEnded;
            };
        };

        private func executeOrRejectProposal(mutableProposal : MutableProposal<TProposalContent>, execute : Bool) : async* () {
            // TODO executing
            switch (mutableProposal.endTimerId) {
                case (null) ();
                case (?id) Timer.cancelTimer(id);
            };
            mutableProposal.endTimerId := null;
            let proposal = fromMutableProposal(mutableProposal);
            if (execute) {
                mutableProposal.statusLog.add(#executing({ time = Time.now() }));

                let newStatus : Types.ProposalStatusLogEntry = try {
                    switch (await* onProposalExecute(proposal)) {
                        case (#ok) #executed({
                            time = Time.now();
                        });
                        case (#err(e)) #failedToExecute({
                            time = Time.now();
                            error = e;
                        });
                    };
                } catch (e) {
                    #failedToExecute({
                        time = Time.now();
                        error = Error.message(e);
                    });
                };
                mutableProposal.statusLog.add(newStatus);
            } else {
                mutableProposal.statusLog.add(#rejected({ time = Time.now() }));
                await* onProposalReject(proposal);
            };
        };

        private func calculateVoteStatus(proposal : MutableProposal<TProposalContent>) : {
            #undetermined;
            #passed;
            #rejected;
        } {
            let votedVotingPower = proposal.votingSummary.yes + proposal.votingSummary.no;
            let totalVotingPower = votedVotingPower + proposal.votingSummary.notVoted;
            switch (votingThreshold) {
                case (#percent({ percent; quorum })) {
                    let quorumThreshold = switch (quorum) {
                        case (null) 0;
                        case (?q) calculateFromPercent(q, totalVotingPower, false);
                    };
                    // The proposal must reach the quorum threshold in any case
                    if (votedVotingPower >= quorumThreshold) {
                        let hasEnded = proposal.timeEnd <= Time.now();
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
                        if (proposal.votingSummary.yes > proposal.votingSummary.no and proposal.votingSummary.yes >= voteThreshold) {
                            return #passed;
                        } else if (proposal.votingSummary.no > proposal.votingSummary.yes and proposal.votingSummary.no >= voteThreshold) {
                            return #rejected;
                        } else if (proposal.votingSummary.yes + proposal.votingSummary.no >= totalVotingPower) {
                            // If the proposal has reached the end time and the votes are equal, it is rejected
                            return #rejected;
                        };
                    };
                };
            };
            return #undetermined;
        };
        resetEndTimers<system>();

    };

    private func getProposalStatus(proposalStatusLog : Buffer.Buffer<Types.ProposalStatusLogEntry>) : Types.ProposalStatusLogEntry or {
        #open;
    } {
        if (proposalStatusLog.size() < 1) {
            return #open;
        };
        proposalStatusLog.get(proposalStatusLog.size() - 1);
    };

    private func fromMutableProposal<TProposalContent>(proposal : MutableProposal<TProposalContent>) : Types.Proposal<TProposalContent> = {
        proposal with
        endTimerId = proposal.endTimerId;
        votes = Iter.toArray(proposal.votes.entries());
        statusLog = Buffer.toArray(proposal.statusLog);
        votingSummary = {
            yes = proposal.votingSummary.yes;
            no = proposal.votingSummary.no;
            notVoted = proposal.votingSummary.notVoted;
        };
    };

    private func toMutableProposal<TProposalContent>(proposal : Types.Proposal<TProposalContent>) : MutableProposal<TProposalContent> {
        let votes = HashMap.fromIter<Principal, Types.Vote>(
            proposal.votes.vals(),
            proposal.votes.size(),
            Principal.equal,
            Principal.hash,
        );
        {
            proposal with
            var endTimerId = proposal.endTimerId;
            votes = votes;
            statusLog = Buffer.fromArray<Types.ProposalStatusLogEntry>(proposal.statusLog);
            votingSummary = buildVotingSummary(votes);
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

    private func buildVotingSummary(votes : HashMap.HashMap<Principal, Types.Vote>) : VotingSummary {
        let votingSummary = {
            var yes = 0;
            var no = 0;
            var notVoted = 0;
        };

        for (vote in votes.vals()) {
            switch (vote.value) {
                case (null) {
                    votingSummary.notVoted += vote.votingPower;
                };
                case (?true) {
                    votingSummary.yes += vote.votingPower;
                };
                case (?false) {
                    votingSummary.no += vote.votingPower;
                };
            };
        };
        votingSummary;
    };

};
