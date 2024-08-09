import Result "mo:base/Result";
import Bool "mo:base/Bool";
import GenericProposalEngine "GenericProposalEngine";
module {

    public type StableData<TProposalContent> = GenericProposalEngine.StableData<TProposalContent, Bool>;

    public type Proposal<TProposalContent> = GenericProposalEngine.Proposal<TProposalContent, Bool>;

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

        let internalEngine = GenericProposalEngine.ProposalEngine<system, TProposalContent, Bool>(
            data,
            onProposalExecute,
            onProposalValidate,
            Bool.equal,
            func(vote : Bool) : Nat32 = if (vote) 1 else 0,
        );

        /// Returns a proposal by its Id.
        ///
        /// ```motoko
        /// let proposalId : Nat = 1;
        /// let ?proposal : ?GenericProposalEngine.Proposal<TProposalContent, TChoice> = proposalEngine.getProposal(proposalId) else Debug.trap("Proposal not found");
        /// ```
        public func getProposal(id : Nat) : ?Proposal<TProposalContent> {
            internalEngine.getProposal(id);
        };

        /// Retrieves a paged list of proposals.
        ///
        /// ```motoko
        /// let count : Nat = 10; // Max proposals to return
        /// let offset : Nat = 0; // Proposals to skip
        /// let pagedResult : GenericProposalEngine.PagedResult<GenericProposalEngine.Proposal<ProposalContent>> = proposalEngine.getProposals(count, offset);
        /// ```
        public func getProposals(count : Nat, offset : Nat) : GenericProposalEngine.PagedResult<Proposal<TProposalContent>> {
            internalEngine.getProposals(count, offset);
        };

        public func getVote(proposalId : Nat, voterId : Principal) : ?GenericProposalEngine.Vote<Bool> {
            internalEngine.getVote(proposalId, voterId);
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
        public func vote(proposalId : Nat, voterId : Principal, vote : Bool) : async* Result.Result<(), GenericProposalEngine.VoteError> {
            await* internalEngine.vote(proposalId, voterId, vote);
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
            members : [GenericProposalEngine.Member],
        ) : async* Result.Result<Nat, GenericProposalEngine.CreateProposalError> {
            await* internalEngine.createProposal(proposerId, content, members);
        };

        public func endProposal(proposalId : Nat) : async* Result.Result<(), { #alreadyEnded }> {
            await* internalEngine.endProposal(proposalId);
        };

        /// Converts the current state to stable data for upgrades.
        ///
        /// ```motoko
        /// let stableData : GenericProposalEngine.StableData<ProposalContent> = proposalEngine.toStableData();
        /// ```
        public func toStableData() : StableData<TProposalContent> {
            internalEngine.toStableData();
        };

    };
};
