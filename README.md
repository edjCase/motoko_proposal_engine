# Overview

A library for creating, voting on and executing proposals

# Package

### MOPS

```
mops install dao-proposal-engine
```

To setup MOPS package manage, follow the instructions from the [MOPS Site](https://j4mwm-bqaaa-aaaam-qajbq-cai.ic0.app/)

# API

## ProposalEngine

### ProposalEngine class
```
ProposalEngine<system, TProposalContent>(
    data: Types.StableData<TProposalContent>,
    onProposalExecute: Types.Proposal<TProposalContent> -> async* Result.Result<(), Text>,
    onProposalReject: Types.Proposal<TProposalContent> -> async* (),
    onProposalValidate: TProposalContent -> async* Result.Result<(), [Text]>
)
```

`getProposal(id: Nat) : ?Types.Proposal<TProposalContent>`

Returns a proposal by its ID.

`getProposals(count: Nat, offset: Nat) : Types.PagedResult<Types.Proposal<TProposalContent>>`

Retrieves a paged list of proposals.

`vote(proposalId: Nat, voterId: Principal, vote: Bool) : async* Result.Result<(), Types.VoteError>`

Casts a vote on a proposal for the specified voter.

`createProposal<system>(proposerId: Principal, content: TProposalContent, members: [Types.Member]) : async* Result.Result<Nat, Types.CreateProposalError>`

Creates a new proposal.

`toStableData() : Types.StableData<TProposalContent>`

Converts the current state to stable data for upgrades.


# Testing

```
mops test
```
