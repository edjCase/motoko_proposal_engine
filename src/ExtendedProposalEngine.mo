import Principal "mo:core/Principal";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Iter "mo:core/Iter";
import Map "mo:core/Map";
import Time "mo:core/Time";
import Timer "mo:core/Timer";
import Int "mo:core/Int";
import Error "mo:core/Error";
import Order "mo:core/Order";
import Result "mo:core/Result";
import Runtime "mo:core/Runtime";
import ExtendedProposal "ExtendedProposal";
import BTree "mo:stableheapbtreemap/BTree";

module {

  public type StableData<TProposalContent, TChoice> = {
    proposals : BTree.BTree<Nat, ProposalData<TProposalContent, TChoice>>;
    proposalDuration : ?Duration;
    votingThreshold : VotingThreshold;
    allowVoteChange : Bool;
  };

  public type PagedResult<T> = {
    data : [T];
    offset : Nat;
    count : Nat;
    totalCount : Nat;
  };

  public type VotingMode = ExtendedProposal.VotingMode;

  public type VotingThreshold = ExtendedProposal.VotingThreshold;

  public type Duration = ExtendedProposal.Duration;

  public type Member = ExtendedProposal.Member;

  public type Proposal<TProposalContent, TChoice> = ExtendedProposal.Proposal<TProposalContent, TChoice>;

  public type ProposalData<TProposalContent, TChoice> = ExtendedProposal.ProposalData<TProposalContent, TChoice>;

  public type ProposalStatus<TChoice> = ExtendedProposal.ProposalStatus<TChoice>;

  public type Vote<TChoice> = ExtendedProposal.Vote<TChoice>;

  public type VotingSummary<TChoice> = ExtendedProposal.VotingSummary<TChoice>;

  public type ChoiceVotingPower<TChoice> = ExtendedProposal.ChoiceVotingPower<TChoice>;

  public type AddMemberResult = {
    #ok;
    #alreadyExists;
    #proposalNotFound;
    #votingNotDynamic;
    #votingClosed;
  };

  public type AddMemberError = ExtendedProposal.AddMemberError;

  public type CreateProposalError = {
    #notEligible;
    #invalid : [Text];
  };

  public type VoteError = ExtendedProposal.VoteError or {
    #proposalNotFound;
  };

  public class ProposalEngine<system, TProposalContent, TChoice>(
    data : StableData<TProposalContent, TChoice>,
    onProposalExecute : (?TChoice, Proposal<TProposalContent, TChoice>) -> async* Result.Result<(), Text>,
    onProposalValidate : TProposalContent -> async* Result.Result<(), [Text]>,
    compareChoice : (TChoice, TChoice) -> Order.Order,
  ) {

    let proposals = data.proposals;
    let endTimerIds = Map.empty<Nat, Nat>(); // Map to track end timer IDs by proposal ID

    var nextProposalId = BTree.size(data.proposals) + 1; // TODO make last proposal + 1

    let proposalDuration = data.proposalDuration;
    let votingThreshold = data.votingThreshold;
    let allowVoteChange = data.allowVoteChange;

    private func resetEndTimers<system>() {
      for ((proposalId, proposal) in BTree.entries(proposals)) {
        switch (Map.get(endTimerIds, Nat.compare, proposalId)) {
          case (null) ();
          case (?id) {
            Timer.cancelTimer(id);
            Map.remove(endTimerIds, Nat.compare, proposalId);
          };
        };
        switch (proposal.status) {
          case (#open) {
            switch (proposal.timeEnd) {
              case (?timeEnd) {
                let currentTime = Time.now();
                if (timeEnd > currentTime) {
                  // Only create timer if proposal hasn't expired yet
                  let remainingNanoseconds = Int.abs(timeEnd - currentTime);
                  let endTimerId = createEndTimer<system>(proposalId, remainingNanoseconds);
                  Map.add(endTimerIds, Nat.compare, proposalId, endTimerId);
                } else {
                  // Proposal has already expired, end it immediately
                  // Note: We can't call endProposal here directly as it's async*,
                  // but the timer mechanism will handle this
                  let endTimerId = createEndTimer<system>(proposalId, 1); // 1 nanosecond delay
                  Map.add(endTimerIds, Nat.compare, proposalId, endTimerId);
                };
              };
              case (null) {}; // No end time, skip timer creation
            };
          };
          case (_) (); // Skip timer creation for non-open proposals
        };
      };
    };
    /// Returns a proposal by its Id.
    ///
    /// ```motoko
    /// let proposalId : Nat = 1;
    /// let ?proposal : ?Proposal<TProposalContent, TChoice> = proposalEngine.getProposal(proposalId) else Runtime.trap("Proposal not found");
    /// ```
    public func getProposal(id : Nat) : ?Proposal<TProposalContent, TChoice> {
      do ? {
        let proposalData = BTree.get(proposals, Nat.compare, id)!;
        {
          proposalData with
          id = id
        };
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
      let vals = proposals
      |> BTree.entries(_)
      |> Iter.sort(
        _,
        func((_, proposalA) : (Nat, ProposalData<TProposalContent, TChoice>), (_, proposalB) : (Nat, ProposalData<TProposalContent, TChoice>)) : Order.Order {
          Int.compare(proposalB.timeStart, proposalA.timeStart);
        },
      )
      |> Iter.drop(_, offset)
      |> Iter.take(_, count)
      |> Iter.map(
        _,
        func((id : Nat, proposal : ProposalData<TProposalContent, TChoice>)) : Proposal<TProposalContent, TChoice> = {
          proposal with
          id = id;
        },
      )
      |> Iter.toArray(_);
      {
        data = vals;
        offset = offset;
        count = count;
        totalCount = BTree.size(proposals);
      };
    };

    /// Retrieves a vote for a specific voter on a proposal.
    ///
    /// ```motoko
    /// let proposalId : Nat = 1;
    /// let voterId : Principal = ...;
    /// let ?vote : ?Vote<TChoice> = proposalEngine.getVote(proposalId, voterId) else Runtime.trap("Vote not found");
    /// ```
    public func getVote(proposalId : Nat, voterId : Principal) : ?Vote<TChoice> {
      let ?proposal = Map.get(proposals, Nat.compare, proposalId) else return null;

      ExtendedProposal.getVote<TProposalContent, TChoice>(proposal, voterId);
    };

    /// Builds a voting summary for a proposal showing vote tallies by choice.
    ///
    /// ```motoko
    /// let proposalId : Nat = 1;
    /// let summary : VotingSummary<TChoice> = proposalEngine.buildVotingSummary(proposalId);
    /// Debug.print("Total voting power: " # Nat.toText(summary.totalVotingPower));
    /// ```
    public func buildVotingSummary(proposalId : Nat) : VotingSummary<TChoice> {
      let ?proposal = Map.get(proposals, Nat.compare, proposalId) else Runtime.trap("Proposal not found: " # Nat.toText(proposalId));
      ExtendedProposal.buildVotingSummary(proposal, compareChoice);
    };

    /// Casts a vote on a proposal for the specified voter.
    /// Will auto execute/reject the proposal if the voting threshold is reached.
    /// async* is due to potential execution of the proposal.
    ///
    /// ```motoko
    /// let proposalId : Nat = 1;
    /// let voterId : Principal = ...;
    /// let vote : TChoice = ...; // Your choice value
    /// switch (await* proposalEngine.vote(proposalId, voterId, vote)) {
    ///   case (#ok) { /* Vote successful */ };
    ///   case (#err(error)) { /* Handle error */ };
    /// };
    /// ```
    public func vote(proposalId : Nat, voterId : Principal, vote : TChoice) : async* Result.Result<(), VoteError> {
      let ?proposal = Map.get(proposals, Nat.compare, proposalId) else return #err(#proposalNotFound);
      switch (ExtendedProposal.vote(proposal, voterId, vote, allowVoteChange)) {
        case (#ok) {
          let choiceStatus = ExtendedProposal.calculateVoteStatus(proposal, votingThreshold, compareChoice, false);
          switch (choiceStatus) {
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
    /// let votingMode = #snapshot; // or #dynamic({ totalVotingPower = ?1000 })
    /// switch (await* proposalEngine.createProposal(proposerId, content, members, votingMode)) {
    ///   case (#ok(proposalId)) { /* Use new proposal ID */ };
    ///   case (#err(error)) { /* Handle error */ };
    /// };
    /// ```
    public func createProposal<system>(
      proposerId : Principal,
      content : TProposalContent,
      members : [Member],
      votingMode : VotingMode,
    ) : async* Result.Result<Nat, CreateProposalError> {

      switch (await* onProposalValidate(content)) {
        case (#ok) ();
        case (#err(errors)) {
          return #err(#invalid(errors));
        };
      };

      let timeStart = Time.now();

      let proposalId = nextProposalId;
      let (timeEnd, endTimerId) : (?Int, ?Nat) = switch (proposalDuration) {
        case (?proposalDuration) {
          let proposalDurationNanoseconds = durationToNanoseconds(proposalDuration);
          let timerId = createEndTimer<system>(proposalId, proposalDurationNanoseconds);
          (?(timeStart + proposalDurationNanoseconds), ?timerId);
        };
        case (null) (null, null);
      };
      let proposal = ExtendedProposal.create<TProposalContent, TChoice>(
        proposerId,
        content,
        members,
        timeStart,
        timeEnd,
        votingMode,
      );
      ignore BTree.insert<Nat, ProposalData<TProposalContent, TChoice>>(proposals, Nat.compare, proposalId, proposal);
      switch (endTimerId) {
        case (null) ();
        case (?endTimerId) Map.add(endTimerIds, Nat.compare, proposalId, endTimerId);
      };
      nextProposalId += 1;
      #ok(proposalId);
    };

    /// Adds a member to a real-time proposal.
    /// Only works with proposals created using createRealTimeProposal.
    ///
    /// ```motoko
    /// let proposalId : Nat = 1;
    /// let member = { id = Principal.fromText("..."); votingPower = 100 };
    /// switch (proposalEngine.addMember(proposalId, member)) {
    ///   case (#ok) { /* Member added successfully */ };
    ///   case (#err(error)) { /* Handle error */ };
    /// };
    /// ```
    public func addMember(
      proposalId : Nat,
      member : Member,
    ) : Result.Result<(), AddMemberResult> {
      let ?proposal = BTree.get(proposals, Nat.compare, proposalId) else return #err(#proposalNotFound);

      switch (ExtendedProposal.addMember(proposal, member)) {
        case (#ok) #ok;
        case (#err(#alreadyExists)) #err(#alreadyExists);
        case (#err(#votingNotDynamic)) #err(#votingNotDynamic);
        case (#err(#votingClosed)) #err(#votingClosed);
      };
    };

    /// Manually ends a proposal before its natural end time.
    ///
    /// ```motoko
    /// let proposalId : Nat = 1;
    /// switch (await* proposalEngine.endProposal(proposalId)) {
    ///   case (#ok) { /* Proposal ended successfully */ };
    ///   case (#err(#alreadyEnded)) { /* Proposal was already ended */ };
    /// };
    /// ```
    public func endProposal(proposalId : Nat) : async* Result.Result<(), { #alreadyEnded }> {
      let ?proposal = BTree.get(proposals, Nat.compare, proposalId) else Runtime.trap("Proposal not found for onProposalEnd: " # Nat.toText(proposalId));
      switch (proposal.status) {
        case (#open) {
          let voteStatus = ExtendedProposal.calculateVoteStatus(proposal, votingThreshold, compareChoice, true);
          let choice = switch (voteStatus) {
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

      {
        proposals = proposals;
        proposalDuration = proposalDuration;
        votingThreshold = votingThreshold;
        allowVoteChange = allowVoteChange;
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
      proposals : BTree.BTree<Nat, ProposalData<TProposalContent, TChoice>>,
      choice : ?TChoice,
    ) : async* () {
      let ?proposal = BTree.get(proposals, Nat.compare, proposalId) else Runtime.trap("Proposal not found: " # Nat.toText(proposalId));
      switch (Map.get(endTimerIds, Nat.compare, proposalId)) {
        case (null) ();
        case (?id) {
          Timer.cancelTimer(id);
          Map.remove(endTimerIds, Nat.compare, proposalId);
        };
      };

      let executingTime = Time.now();

      let executingProposal = {
        proposal with
        status : ProposalStatus<TChoice> = #executing({
          executingTime = executingTime;
          choice = choice;
        });
      };

      let ?_ = BTree.insert(proposals, Nat.compare, proposalId, executingProposal) else Runtime.trap("Proposal not found: " # Nat.toText(proposalId));

      let newStatus : ProposalStatus<TChoice> = try {
        switch (await* onProposalExecute(choice, { proposal with id = proposalId })) {
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

      let ?_ = BTree.insert(
        proposals,
        Nat.compare,
        proposalId,
        {
          executingProposal with
          status = newStatus;
        },
      ) else Runtime.trap("Proposal not found: " # Nat.toText(proposalId));
    };

    resetEndTimers<system>();

  };

};
