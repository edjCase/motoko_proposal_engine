import Result "mo:base/Result";
import Bool "mo:base/Bool";
import ExtendedProposalEngine "ExtendedProposalEngine";
import Proposal "Proposal";

module {
  

    public type StableData<TProposalContent> = ExtendedProposalEngine.StableData<TProposalContent, Bool>;

    public type ChoiceVotingPower = Proposal.ChoiceVotingPower;

    public type AddMemberResult = ExtendedProposalEngine.AddMemberResult;

    public type CreateProposalError = ExtendedProposalEngine.CreateProposalError;

    public type VoteError = ExtendedProposalEngine.VoteError;

    public type Proposal<TProposalContent> = Proposal.Proposal<TProposalContent>;

    public class ProposalEngine<system, TProposalContent>(
        data : StableData<TProposalContent>,
        onProposalAdopt : (Proposal<TProposalContent>) -> async* Result.Result<(), Text>,
        onProposalReject : (Proposal<TProposalContent>) -> async* (),
        onProposalValidate : TProposalContent -> async* Result.Result<(), [Text]>,
    ) {
        private func onProposalExecute(choice : ?Bool, proposal : Proposal<TProposalContent>) : async* Result.Result<(), Text> {
            switch (choice) {
                case (?true) await* onProposalAdopt(proposal);
                case (?false or null) {
                    await* onProposalReject(proposal);
                    #ok;
                };
            };
        };

        let internalEngine = ExtendedProposalEngine.ProposalEngine<system, TProposalContent, Bool>(
            data,
            onProposalExecute,
            onProposalValidate,
            Bool.equal,
            func(vote : Bool) : Nat32 = if (vote) 1 else 0,
        );

        /// Returns a proposal by its Id.
        public func getProposal(id : Nat) : ?Proposal<TProposalContent> {
            internalEngine.getProposal(id);
        };

        /// Retrieves a paged list of proposals.
        public func getProposals(count : Nat, offset : Nat) : ExtendedProposalEngine.PagedResult<Proposal<TProposalContent>> {
            internalEngine.getProposals(count, offset);
        };

        public func getVote(proposalId : Nat, voterId : Principal) : ?ExtendedProposalEngine.Vote<Bool> {
            internalEngine.getVote(proposalId, voterId);
        };

        public func buildVotingSummary(proposalId : Nat) : Proposal.VotingSummary {
            internalEngine.buildVotingSummary(proposalId);
        };

        /// Casts a vote on a proposal for the specified voter.
        public func vote(proposalId : Nat, voterId : Principal, vote : Bool) : async* Result.Result<(), ExtendedProposalEngine.VoteError> {
            await* internalEngine.vote(proposalId, voterId, vote);
        };

        /// Creates a new proposal.
        public func createProposal<s>(
            proposerId : Principal,
            content : TProposalContent,
            members : [ExtendedProposalEngine.Member],
        ) : async* Result.Result<Nat, ExtendedProposalEngine.CreateProposalError> {
            await* internalEngine.createProposal(proposerId, content, members);
        };

        /// Creates a new real-time proposal with dynamic member management.
        public func createRealTimeProposal<system>(
            proposerId : Principal,
            content : TProposalContent,
            totalVotingPower : Nat,
        ) : async* Result.Result<Nat, ExtendedProposalEngine.CreateProposalError> {
            await* internalEngine.createRealTimeProposal(proposerId, content, totalVotingPower);
        };

        /// Adds a member to a real-time proposal.
        public func addMember(
            proposalId : Nat,
            member : ExtendedProposalEngine.Member,
        ) : Result.Result<(), ExtendedProposalEngine.AddMemberResult> {
            internalEngine.addMember(proposalId, member);
        };

        public func endProposal(proposalId : Nat) : async* Result.Result<(), { #alreadyEnded }> {
            await* internalEngine.endProposal(proposalId);
        };

        /// Converts the current state to stable data for upgrades.
        public func toStableData() : StableData<TProposalContent> {
            internalEngine.toStableData();
        };

    };
};
