import Time "mo:core/Time";
import Result "mo:core/Result";
import Principal "mo:core/Principal";
import Map "mo:core/Map";
import Option "mo:core/Option";
import Iter "mo:core/Iter";
import List "mo:core/List";
import Float "mo:core/Float";
import Int "mo:core/Int";
import Order "mo:core/Order";
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

  public type ProposalData<TProposalContent, TChoice> = {
    proposerId : Principal;
    content : TProposalContent;
    timeStart : Time.Time;
    timeEnd : ?Time.Time;
    votingMode : VotingMode;
    votes : BTree.BTree<Principal, Vote<TChoice>>;
    status : ProposalStatus<TChoice>;
  };

  public type Proposal<TProposalContent, TChoice> = ProposalData<TProposalContent, TChoice> and {
    id : Nat;
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
  /// let proposal : ProposalData<MyContent, MyChoice> = ...;
  /// let member : Member = { id = Principal.fromText("..."); votingPower = 100 };
  /// switch (addMember(proposal, member)) {
  ///   case (#ok) { /* Member added successfully */ };
  ///   case (#err(#alreadyExists)) { /* Member already exists */ };
  ///   case (#err(#votingNotDynamic)) { /* Proposal is not dynamic */ };
  ///   case (#err(#votingClosed)) { /* Voting is closed */ };
  /// };
  /// ```
  public func addMember<TProposalContent, TChoice>(
    proposal : ProposalData<TProposalContent, TChoice>,
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
  /// let proposal : ProposalData<MyContent, MyChoice> = ...;
  /// let voterId : Principal = ...;
  /// let ?vote : ?Vote<MyChoice> = getVote(proposal, voterId) else Runtime.trap("Vote not found");
  /// ```
  public func getVote<TProposalContent, TChoice>(
    proposal : ProposalData<TProposalContent, TChoice>,
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
  /// let proposal : ProposalData<MyContent, MyChoice> = ...;
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
    proposal : ProposalData<TProposalContent, TChoice>,
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
  /// let proposal : ProposalData<MyContent, MyChoice> = ...;
  /// let compare : (MyChoice, MyChoice) -> Order.Order = ...;
  /// let summary : VotingSummary<MyChoice> = buildVotingSummary(proposal, compare);
  /// Debug.print("Total voting power: " # Nat.toText(summary.totalVotingPower));
  /// ```
  public func buildVotingSummary<TProposalContent, TChoice>(
    proposal : ProposalData<TProposalContent, TChoice>,
    compare : (TChoice, TChoice) -> Order.Order,
  ) : VotingSummary<TChoice> {

    let choices = Map.empty<TChoice, Nat>();
    var undecidedVotingPower = 0;
    let totalVotingPower = switch (proposal.votingMode) {
      case (#dynamic({ totalVotingPower = ?totalVotingPower })) {
        totalVotingPower;
      };
      case (#snapshot(_) or #dynamic({ totalVotingPower = null })) {
        var totalVotingPower = 0;
        let voteCount = BTree.size(proposal.votes);

        for ((voterId, vote) in BTree.entries(proposal.votes)) {
          switch (vote.choice) {
            case (null) {
              undecidedVotingPower += vote.votingPower;
            };
            case (?choice) {
              let currentVotingPower = Option.get(Map.get(choices, compare, choice), 0);
              Map.add(choices, compare, choice, currentVotingPower + vote.votingPower);
            };
          };
          totalVotingPower += vote.votingPower;
        };
        totalVotingPower;
      };
    };

    let choiceArray = Iter.toArray(
      Iter.map(
        Map.entries(choices),
        func((choice, votingPower) : (TChoice, Nat)) : ChoiceVotingPower<TChoice> = {
          choice = choice;
          votingPower = votingPower;
        },
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
  /// let proposal : ProposalData<MyContent, MyChoice> = ...;
  /// let votingThreshold : VotingThreshold = #percent({ percent = 50; quorum = ?25 });
  /// let compareChoice : (MyChoice, MyChoice) -> Order.Order = ...;
  /// let forceEnd : Bool = false;
  /// switch (calculateVoteStatus(proposal, votingThreshold, compareChoice, forceEnd)) {
  ///   case (#determined(?choice)) { /* Proposal passed with choice */ };
  ///   case (#determined(null)) { /* Proposal rejected */ };
  ///   case (#undetermined) { /* Still voting */ };
  /// };
  /// ```
  public func calculateVoteStatus<TProposalContent, TChoice>(
    proposal : ProposalData<TProposalContent, TChoice>,
    votingThreshold : VotingThreshold,
    compareChoice : (TChoice, TChoice) -> Order.Order,
    forceEnd : Bool,
  ) : ChoiceStatus<TChoice> {
    let { totalVotingPower; undecidedVotingPower; votingPowerByChoice } = buildVotingSummary(proposal, compareChoice);
    let votedVotingPower : Nat = totalVotingPower - undecidedVotingPower;

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
              case (null) false; // No end time means it hasn't ended
            }
          );

          let voteThreshold = if (hasEnded) {
            // If the proposal has reached the end time, it passes if the votes are above the threshold of the VOTED voting power
            let threshold = calculateFromPercent(percent, votedVotingPower, true);
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
            finalThreshold;
          };

          let pluralityChoices = {
            var votingPower = 0;
            choices = List.empty<TChoice>();
          };
          for (choice in votingPowerByChoice.vals()) {
            if (choice.votingPower > pluralityChoices.votingPower) {
              pluralityChoices.votingPower := choice.votingPower;
              List.clear(pluralityChoices.choices);
              List.add(pluralityChoices.choices, choice.choice);
            } else if (choice.votingPower == pluralityChoices.votingPower) {
              List.add(pluralityChoices.choices, choice.choice);
            };
          };

          if (List.size(pluralityChoices.choices) == 1) {
            if (pluralityChoices.votingPower >= voteThreshold) {
              // Real-time proposals should NOT auto-execute, even when threshold is reached
              switch (proposal.votingMode) {
                case (#dynamic(_)) {

                  if (hasEnded) {
                    let winningChoice = List.get(pluralityChoices.choices, 0);

                    return #determined(?winningChoice);
                  } else {
                    return #undetermined; // Stay undetermined for manual execution
                  };
                };
                case (#snapshot(_)) {
                  let winningChoice = List.get(pluralityChoices.choices, 0);
                  return #determined(?winningChoice);
                };
              };
            };
          } else if (List.size(pluralityChoices.choices) > 1) {
            // If everyone has voted and there is a tie -> undetermined
            if (undecidedVotingPower <= 0) {
              return #determined(null);
            };
          };
        };
      };
    };
    return #undetermined;
  };

  /// Creates a new proposal with the specified parameters.
  ///
  /// ```motoko
  /// let proposerId : Principal = ...;
  /// let content = { /* Your proposal content */ };
  /// let members : [Member] = [{ id = ...; votingPower = 100 }];
  /// let timeStart : Time.Time = Time.now();
  /// let timeEnd : ?Time.Time = ?(timeStart + 24 * 60 * 60 * 1_000_000_000); // 24 hours
  /// let votingMode : VotingMode = #snapshot;
  /// let proposal : ProposalData<MyContent, MyChoice> = create(proposerId, content, members, timeStart, timeEnd, votingMode);
  /// ```
  public func create<TProposalContent, TChoice>(
    proposerId : Principal,
    content : TProposalContent,
    members : [Member],
    timeStart : Time.Time,
    timeEnd : ?Time.Time,
    votingMode : VotingMode,
  ) : ProposalData<TProposalContent, TChoice> {
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
