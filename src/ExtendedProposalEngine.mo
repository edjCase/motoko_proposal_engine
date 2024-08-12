import Principal "mo:base/Principal";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Int "mo:base/Int";
import Error "mo:base/Error";
import Order "mo:base/Order";
import IterTools "mo:itertools/Iter";
import Result "mo:base/Result";
import ExtendedProposal "ExtendedProposal";

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
        totalCount : Nat;
    };

    public type VotingThreshold = ExtendedProposal.VotingThreshold;

    public type Duration = ExtendedProposal.Duration;

    public type Member = ExtendedProposal.Member;

    public type Proposal<TProposalContent, TChoice> = ExtendedProposal.Proposal<TProposalContent, TChoice>;

    public type ProposalStatus<TChoice> = ExtendedProposal.ProposalStatus<TChoice>;

    public type Vote<TChoice> = ExtendedProposal.Vote<TChoice>;

    public type VotingSummary<TChoice> = ExtendedProposal.VotingSummary<TChoice>;

    public type ChoiceVotingPower<TChoice> = ExtendedProposal.ChoiceVotingPower<TChoice>;

    public type AddMemberResult = {
        #ok;
        #alreadyExists;
    };

    public type CreateProposalError = {
        #notAuthorized;
        #invalid : [Text];
    };

    public type VoteError = ExtendedProposal.VoteError;

    type ProposalWithTimer<TProposalContent, TChoice> = ExtendedProposal.Proposal<TProposalContent, TChoice> and {
        var endTimerId : ?Nat;
    };

    public class ProposalEngine<system, TProposalContent, TChoice>(
        data : StableData<TProposalContent, TChoice>,
        onProposalExecute : (?TChoice, Proposal<TProposalContent, TChoice>) -> async* Result.Result<(), Text>,
        onProposalValidate : TProposalContent -> async* Result.Result<(), [Text]>,
        equalChoice : (TChoice, TChoice) -> Bool,
        hashChoice : (TChoice) -> Nat32,
    ) {

        var proposals = data.proposals.vals()
        |> Iter.map<Proposal<TProposalContent, TChoice>, (Nat, ProposalWithTimer<TProposalContent, TChoice>)>(
            _,
            func(proposal : Proposal<TProposalContent, TChoice>) : (Nat, ProposalWithTimer<TProposalContent, TChoice>) = (
                proposal.id,
                {
                    proposal with
                    var endTimerId : ?Nat = null;
                },
            ),
        )
        |> HashMap.fromIter<Nat, ProposalWithTimer<TProposalContent, TChoice>>(_, 0, Nat.equal, Nat32.fromNat);

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
            proposals.get(id);
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
                totalCount = proposals.size();
            };
        };

        public func getVote(proposalId : Nat, voterId : Principal) : ?Vote<TChoice> {
            let ?proposal = proposals.get(proposalId) else return null;

            ExtendedProposal.getVote<TProposalContent, TChoice>(proposal, voterId);
        };

        public func buildVoteSummary(proposalId : Nat) : VotingSummary<TChoice> {
            let ?proposal = proposals.get(proposalId) else Debug.trap("Proposal not found: " # Nat.toText(proposalId));
            ExtendedProposal.buildVotingSummary(proposal.votes, equalChoice, hashChoice);
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
            switch (ExtendedProposal.vote(proposal, voterId, vote, votingThreshold, equalChoice, hashChoice)) {
                case (#ok(ok)) {
                    proposals.put(proposalId, { ok.updatedProposal with var endTimerId = proposal.endTimerId });
                    switch (ok.choiceStatus) {
                        case (#determined(choice)) {
                            await* executeProposal(proposalId, proposals, choice);
                        };
                        case (#undetermined) ();
                    };
                };
                case (#err(error)) return #err(error);
            };
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

            // Take snapshot of members at the time of proposal creation
            let votes = members.vals()
            |> Iter.map<Member, (Principal, Vote<TChoice>)>(
                _,
                func(member : Member) : (Principal, Vote<TChoice>) = (
                    member.id,
                    {
                        choice = null;
                        votingPower = member.votingPower;
                    },
                ),
            )
            |> Iter.toArray(_);
            let proposalId = nextProposalId;
            let (timeEnd, endTimerId) : (?Int, ?Nat) = switch (proposalDuration) {
                case (?proposalDuration) {
                    let proposalDurationNanoseconds = durationToNanoseconds(proposalDuration);
                    let timerId = createEndTimer<system>(proposalId, proposalDurationNanoseconds);
                    (?(now + proposalDurationNanoseconds), ?timerId);
                };
                case (null) (null, null);
            };
            let proposal : ProposalWithTimer<TProposalContent, TChoice> = {
                id = proposalId;
                proposerId = proposerId;
                content = content;
                timeStart = now;
                timeEnd = timeEnd;
                var endTimerId = endTimerId;
                votes = votes;
                status = #open;
            };
            proposals.put(nextProposalId, proposal);
            nextProposalId += 1;
            #ok(proposalId);
        };

        public func endProposal(proposalId : Nat) : async* Result.Result<(), { #alreadyEnded }> {
            let ?proposal = proposals.get(proposalId) else Debug.trap("Proposal not found for onProposalEnd: " # Nat.toText(proposalId));
            switch (proposal.status) {
                case (#open) {
                    let choice = switch (ExtendedProposal.calculateVoteStatus(proposal, votingThreshold, equalChoice, hashChoice, true)) {
                        case (#determined(choice)) choice;
                        case (#undetermined) null;
                    };
                    await* executeProposal(proposalId, proposals, choice);
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
            let proposalsArray = proposals.vals()
            |> Iter.toArray(_);

            {
                proposals = proposalsArray;
                proposalDuration = proposalDuration;
                votingThreshold = votingThreshold;
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
            proposalId : Nat,
            proposals : HashMap.HashMap<Nat, ProposalWithTimer<TProposalContent, TChoice>>,
            choice : ?TChoice,
        ) : async* () {
            let ?proposal = proposals.get(proposalId) else Debug.trap("Proposal not found: " # Nat.toText(proposalId));
            switch (proposal.endTimerId) {
                case (null) ();
                case (?id) Timer.cancelTimer(id);
            };
            proposal.endTimerId := null;

            let executingTime = Time.now();

            let executingProposal = {
                proposal with
                var endTimerId : ?Nat = null;
                status : ProposalStatus<TChoice> = #executing({
                    executingTime = executingTime;
                    choice = choice;
                });
            };

            proposals.put(proposalId, executingProposal);

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

            proposals.put(
                proposalId,
                {
                    executingProposal with
                    var endTimerId : ?Nat = null;
                    status = newStatus;
                },
            );
        };

        resetEndTimers<system>();

    };

};
