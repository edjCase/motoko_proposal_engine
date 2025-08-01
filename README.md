# Overview

A library for creating, voting on and executing proposals

# Package

### MOPS

# Motoko Proposal Engine

A comprehensive library for creating, voting on, and executing proposals in Motoko. This library supports both simple boolean voting and advanced multi-choice voting with configurable thresholds and voting modes.

## Features

- **Multiple Voting Modes**: Snapshot-based and dynamic voting
- **Flexible Choices**: Boolean voting or custom choice types
- **Configurable Thresholds**: Percentage-based voting with optional quorum
- **Dynamic Member Management**: Add members to proposals during voting
- **Automatic Execution**: Proposals execute automatically when thresholds are met
- **Time-bound Voting**: Optional proposal durations with automatic ending
- **Stable Upgrades**: Full support for canister upgrades

## Package

### MOPS

```bash
mops install dao-proposal-engine
```

To setup MOPS package manage, follow the instructions from the [MOPS Site](https://j4mwm-bqaaa-aaaam-qajbq-cai.ic0.app/)

## Quick Start

### Simple Boolean Voting

```motoko
import ProposalEngine "mo:dao-proposal-engine/ProposalEngine";

// Initialize with stable data
let stableData = {
    proposals = BTree.init<Nat, ProposalEngine.ProposalData<MyProposalContent>>(null);
    proposalDuration = ?#days(7); // 7 day voting period
    votingThreshold = #percent({ percent = 50; quorum = ?25 });
    allowVoteChange = false;
};

// Create proposal engine for boolean voting
let engine = ProposalEngine.ProposalEngine<system, MyProposalContent>(
    stableData,
    onProposalAdopt, // Called when proposal passes
    onProposalReject, // Called when proposal fails
    onProposalValidate // Validates proposal content
);

// Create a proposal
let members = [
    { id = principalA; votingPower = 100 },
    { id = principalB; votingPower = 50 }
];
let proposalId = await* engine.createProposal(
    proposerId,
    proposalContent,
    members,
    #snapshot // Snapshot voting mode
);

// Vote on proposal
let _ = await* engine.vote(proposalId, voterId, true); // Vote yes
```

### Advanced Multi-Choice Voting

```motoko
import ExtendedProposalEngine "mo:dao-proposal-engine/ExtendedProposalEngine";

// Create proposal engine for custom choice voting
let engine = ExtendedProposalEngine.ProposalEngine<system, MyProposalContent, MyChoice>(
    stableData,
    onProposalExecute, // Called with winning choice
    onProposalValidate, // Validates proposal content
    MyChoice.compare, // Choice compare function
);

// Create proposal with dynamic voting
let proposalId = await* engine.createProposal(
    proposerId,
    proposalContent,
    members,
    #dynamic({ totalVotingPower = ?1000 }) // Dynamic voting mode
);

// Add member during voting (only for dynamic mode)
let newMember = { id = newPrincipal; votingPower = 75 };
let _ = engine.addMember(proposalId, newMember);

// Vote with custom choice
let _ = await* engine.vote(proposalId, voterId, myChoice);
```

## Architecture Overview

### Proposal vs Engine

The library provides two levels of abstraction for working with proposals:

#### **Proposal Modules** (`Proposal.mo` and `ExtendedProposal.mo`)

- **Pure data structures**: Hold proposal data and voting information
- **Stateless functions**: Provide utilities for voting, calculating status, and managing proposal data
- **Manual management**: You handle storage, timers, and state transitions yourself
- **Direct control**: Full control over when and how proposals are processed

```motoko
// Direct proposal management
import Proposal "mo:dao-proposal-engine/Proposal";

let proposal = Proposal.create(...);
let voteResult = Proposal.vote(proposal, voterId, true, allowVoteChange);
let status = Proposal.calculateVoteStatus(proposal, threshold, forceEnd);
// You handle storage and execution yourself
```

#### **Engine Classes** (`ProposalEngine.mo` and `ExtendedProposalEngine.mo`)

- **Complete management system**: Handles proposal storage, lifecycle, and execution
- **Automatic features**:
  - Timer-based proposal ending
  - Automatic status transitions
  - Auto-execution when thresholds are met
  - Stable data management for upgrades
- **Event-driven**: Callbacks for proposal adoption, rejection, and validation
- **Production-ready**: Handles all the complex state management for you

```motoko
// Managed proposal system
import ProposalEngine "mo:dao-proposal-engine/ProposalEngine";

let engine = ProposalEngine.ProposalEngine<system, MyContent>(...);
let proposalId = await* engine.createProposal(...); // Stored automatically
let _ = await* engine.vote(proposalId, voterId, true); // Auto-executes if threshold met
// Engine handles timers, storage, and execution automatically
```

### Standard vs Extended Proposals

#### **Standard Proposals** (`Proposal.mo` and `ProposalEngine.mo`)

- **Boolean voting**: Simple adopt (true) or reject (false) decisions
- **Two outcomes**: Proposals either pass or fail
- **Simplified API**: Easier to use for basic governance needs
- **Type safety**: Enforced boolean voting prevents choice errors

```motoko
// Boolean voting - simple and clear
let _ = await* engine.vote(proposalId, voterId, true); // Vote to adopt
let _ = await* engine.vote(proposalId, voterId, false); // Vote to reject
```

#### **Extended Proposals** (`ExtendedProposal.mo` and `ExtendedProposalEngine.mo`)

- **Custom choice types**: Any type can be used for voting choices
- **Multi-choice voting**: Support for complex decision-making scenarios
- **Flexible outcomes**: Winners determined by plurality or custom logic
- **Advanced scenarios**: Budget allocation, candidate selection, configuration options

```motoko
// Multi-choice voting with custom types
type BudgetChoice = {
  #allocateToMarketing: Nat;
  #allocateToEngineering: Nat;
  #allocateToOperations: Nat;
  #rejectBudget;
};

let _ = await* extendedEngine.vote(proposalId, voterId, #allocateToEngineering(500_000));
```

## API Reference

### Core Types

#### StableData

```motoko
type StableData<TProposalContent, TChoice> = {
    proposals : [Proposal<TProposalContent, TChoice>];
    proposalDuration : ?Duration;
    votingThreshold : VotingThreshold;
    allowVoteChange : Bool;
};
```

#### PagedResult

```motoko
type PagedResult<T> = {
    data : [T];
    offset : Nat;
    count : Nat;
    totalCount : Nat;
};
```

#### VotingMode

```motoko
type VotingMode = {
    #snapshot; // Fixed member list at creation
    #dynamic : { totalVotingPower : ?Nat }; // Members can be added during voting
};
```

#### VotingThreshold

```motoko
type VotingThreshold = {
    #percent : { percent : Nat; quorum : ?Nat }; // Percentage (0-100) with optional quorum
};
```

#### Duration

```motoko
type Duration = {
    #days : Nat;
    #nanoseconds : Nat;
};
```

#### Member

```motoko
type Member = {
    id : Principal;
    votingPower : Nat;
};
```

#### Proposal

```motoko
type Proposal<TProposalContent, TChoice> = {
    id : Nat;
    proposerId : Principal;
    timeStart : Int;
    timeEnd : ?Int;
    votingMode : VotingMode;
    content : TProposalContent;
    votes : BTree<Principal, Vote<TChoice>>;
    status : ProposalStatus<TChoice>;
};
```

#### ProposalStatus

```motoko
type ProposalStatus<TChoice> = {
    #open;
    #executing : { executingTime : Time; choice : ?TChoice };
    #executed : { executingTime : Time; executedTime : Time; choice : ?TChoice };
    #failedToExecute : { executingTime : Time; failedTime : Time; choice : ?TChoice; error : Text };
};
```

#### Vote

```motoko
type Vote<TChoice> = {
    choice : ?TChoice;
    votingPower : Nat;
};
```

#### VotingSummary

```motoko
type VotingSummary<TChoice> = {
    votingPowerByChoice : [ChoiceVotingPower<TChoice>];
    totalVotingPower : Nat;
    undecidedVotingPower : Nat;
};
```

#### ChoiceVotingPower

```motoko
type ChoiceVotingPower<TChoice> = {
    choice : TChoice;
    votingPower : Nat;
};
```

### Error Types

#### VoteError

```motoko
type VoteError = {
    #notEligible; // Voter is not a member of the proposal
    #alreadyVoted; // Voter has already voted (when vote changes are disabled)
    #votingClosed; // Voting period has ended or proposal is not open
    #proposalNotFound; // Proposal ID does not exist (ExtendedProposalEngine only)
};
```

#### CreateProposalError

```motoko
type CreateProposalError = {
    #notEligible; // Proposer is not eligible to create proposals
    #invalid : [Text]; // Proposal content failed validation
};
```

#### AddMemberResult

```motoko
type AddMemberResult = {
    #ok; // Member added successfully
    #alreadyExists; // Member already exists in the proposal
    #proposalNotFound; // Proposal ID does not exist
    #votingNotDynamic; // Proposal is not in dynamic voting mode
    #votingClosed; // Voting period has ended
};
```

### ProposalEngine (Boolean Voting)

#### Constructor

```motoko
ProposalEngine<system, TProposalContent>(
    data: StableData<TProposalContent>,
    onProposalAdopt: Proposal<TProposalContent> -> async* Result.Result<(), Text>,
    onProposalReject: Proposal<TProposalContent> -> async* (),
    onProposalValidate: TProposalContent -> async* Result.Result<(), [Text])
)
```

#### Methods

**`getProposal(id: Nat) : ?Proposal<TProposalContent>`**

Returns a proposal by its ID.

**`getProposals(count: Nat, offset: Nat) : PagedResult<Proposal<TProposalContent>>`**

Retrieves a paged list of proposals, sorted by creation time (newest first).

**`getVote(proposalId: Nat, voterId: Principal) : ?Vote<Bool>`**

Retrieves a specific voter's vote on a proposal.

**`buildVotingSummary(proposalId: Nat) : VotingSummary`**

Builds a voting summary showing vote tallies and statistics.

**`vote(proposalId: Nat, voterId: Principal, vote: Bool) : async* Result.Result<(), VoteError>`**

Casts a vote on a proposal. Returns error if voter is not eligible or voting is closed.

**`createProposal<system>(proposerId: Principal, content: TProposalContent, members: [Member], votingMode: VotingMode) : async* Result.Result<Nat, CreateProposalError>`**

Creates a new proposal. Returns the proposal ID on success.

**`addMember(proposalId: Nat, member: Member) : Result.Result<(), AddMemberResult>`**

Adds a member to a dynamic proposal during voting.

**`endProposal(proposalId: Nat) : async* Result.Result<(), { #alreadyEnded }>`**

Manually ends a proposal before its natural end time.

**`toStableData() : StableData<TProposalContent>`**

Converts the current state to stable data for upgrades.

### ExtendedProposalEngine (Multi-Choice Voting)

#### Constructor

```motoko
ProposalEngine<system, TProposalContent, TChoice>(
    data: StableData<TProposalContent, TChoice>,
    onProposalExecute: (?TChoice, Proposal<TProposalContent, TChoice>) -> async* Result.Result<(), Text>,
    onProposalValidate: TProposalContent -> async* Result.Result<(), [Text]),
    compareChoice: (TChoice, TChoice) -> Order.Order,
)
```

#### Methods

**`getProposal(id: Nat) : ?Proposal<TProposalContent, TChoice>`**

Returns a proposal by its ID.

**`getProposals(count: Nat, offset: Nat) : PagedResult<Proposal<TProposalContent, TChoice>>`**

Retrieves a paged list of proposals, sorted by creation time (newest first).

**`getVote(proposalId: Nat, voterId: Principal) : ?Vote<TChoice>`**

Retrieves a specific voter's vote on a proposal.

**`buildVotingSummary(proposalId: Nat) : VotingSummary<TChoice>`**

Builds a voting summary showing vote tallies and statistics.

**`vote(proposalId: Nat, voterId: Principal, vote: TChoice) : async* Result.Result<(), VoteError>`**

Casts a vote on a proposal with a custom choice type.

**`createProposal<system>(proposerId: Principal, content: TProposalContent, members: [Member], votingMode: VotingMode) : async* Result.Result<Nat, CreateProposalError>`**

Creates a new proposal. Returns the proposal ID on success.

**`addMember(proposalId: Nat, member: Member) : Result.Result<(), AddMemberResult>`**

Adds a member to a dynamic proposal during voting.

**`endProposal(proposalId: Nat) : async* Result.Result<(), { #alreadyEnded }>`**

Manually ends a proposal before its natural end time.

**`toStableData() : StableData<TProposalContent, TChoice>`**

Converts the current state to stable data for upgrades.

## Voting Modes

### Snapshot Mode (`#snapshot`)

- Member list is fixed at proposal creation
- No members can be added during voting
- Suitable for formal governance where membership is predetermined

### Dynamic Mode (`#dynamic`)

- Members can be added during the voting period
- Optionally specify total voting power for threshold calculations
- Suitable for evolving communities or stake-based voting

## Voting Thresholds

### Percentage Threshold

```motoko
#percent({ percent = 50; quorum = ?25 })
```

- `percent`: Required percentage of votes to pass (0-100)
- `quorum`: Optional minimum participation percentage

**Threshold Calculation:**

- Before proposal end: Threshold applies to total possible voting power
- After proposal end: Threshold applies only to votes cast
- Dynamic proposals: Stay undetermined even when threshold is met (manual execution required)

## Examples

### Governance Proposal

```motoko
type GovernanceProposal = {
    title: Text;
    description: Text;
    action: {
        #updateConfig: { key: Text; value: Text };
        #addMember: Principal;
        #removeMember: Principal;
    };
};

let proposal = await* engine.createProposal(
    caller,
    {
        title = "Update Configuration";
        description = "Change max proposal duration to 14 days";
        action = #updateConfig({ key = "maxDuration"; value = "14" });
    },
    members,
    #snapshot
);
```

### Multi-Choice Budget Proposal

```motoko
type BudgetChoice = {
    #allocateToMarketing: Nat;
    #allocateToEngineering: Nat;
    #allocateToOperations: Nat;
    #rejectBudget;
};

let proposalId = await* extendedEngine.createProposal(
    caller,
    budgetProposalContent,
    stakeholders,
    #dynamic({ totalVotingPower = ?totalStake })
);

// Stakeholders vote on budget allocation
let _ = await* extendedEngine.vote(proposalId, stakeholderA, #allocateToEngineering(500_000));
let _ = await* extendedEngine.vote(proposalId, stakeholderB, #allocateToMarketing(300_000));
```

## Testing

```bash
mops test
```

## License

This project is licensed under the MIT License.
