import { test; suite } "mo:test/async";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import ExtendedProposalEngine "../src/ExtendedProposalEngine";

await suite(
    "ExtendedProposalEngine Real-time Tests",
    func() : async () {
        await test(
            "createRealTimeProposal with custom choice type",
            func() : async () {
                type ProposalContent = {
                    title : Text;
                    description : Text;
                };
                type Choice = {
                    #approve;
                    #reject;
                    #abstain;
                };
                
                let stableData : ExtendedProposalEngine.StableData<ProposalContent, Choice> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 51; quorum = ?25 });
                    allowVoteChange = false;
                };
                
                let onExecute = func(choice : ?Choice, _ : ExtendedProposalEngine.Proposal<ProposalContent, Choice>) : async* Result.Result<(), Text> {
                    switch (choice) {
                        case (?#approve) Debug.print("Proposal approved!");
                        case (?#reject) Debug.print("Proposal rejected!");
                        case (?#abstain) Debug.print("Proposal abstained!");
                        case (null) Debug.print("No clear choice!");
                    };
                    #ok;
                };
                
                let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
                    #ok;
                };
                
                let choiceEqual = func(a : Choice, b : Choice) : Bool {
                    switch (a, b) {
                        case (#approve, #approve) true;
                        case (#reject, #reject) true;
                        case (#abstain, #abstain) true;
                        case (_, _) false;
                    };
                };
                
                let choiceHash = func(choice : Choice) : Nat32 {
                    switch (choice) {
                        case (#approve) 0;
                        case (#reject) 1;
                        case (#abstain) 2;
                    };
                };
                
                let engine = ExtendedProposalEngine.ProposalEngine<system, ProposalContent, Choice>(
                    stableData, 
                    onExecute, 
                    onValidate, 
                    choiceEqual, 
                    choiceHash
                );
                
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                
                // Create real-time proposal with 10,000 total voting power
                let createResult = await* engine.createRealTimeProposal(
                    proposerId,
                    {
                        title = "Multi-choice Real-time Proposal";
                        description = "Test real-time functionality with custom choices";
                    },
                    10000
                );
                let #ok(proposalId) = createResult else Debug.trap("Failed to create real-time proposal");
                
                let ?proposal = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
                assert proposal.votes == [];
                
                Debug.print("✓ Real-time proposal with custom choices created successfully");
            }
        );
        
        await test(
            "complex real-time voting scenario",
            func() : async () {
                type ProposalContent = {
                    title : Text;
                    budget : Nat;
                };
                type Choice = {
                    #approve;
                    #reject;
                    #amendBudget : Nat;
                };
                
                let stableData : ExtendedProposalEngine.StableData<ProposalContent, Choice> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 60; quorum = ?30 }); // Higher threshold
                    allowVoteChange = true; // Allow vote changes
                };
                
                let onExecute = func(choice : ?Choice, proposal : ExtendedProposalEngine.Proposal<ProposalContent, Choice>) : async* Result.Result<(), Text> {
                    switch (choice) {
                        case (?#approve) Debug.print("Budget approved: " # debug_show(proposal.content.budget));
                        case (?#reject) Debug.print("Budget rejected");
                        case (?#amendBudget(newBudget)) Debug.print("Budget amended to: " # debug_show(newBudget));
                        case (null) Debug.print("No consensus reached");
                    };
                    #ok;
                };
                
                let onValidate = func(content : ProposalContent) : async* Result.Result<(), [Text]> {
                    if (content.budget == 0) {
                        #err(["Budget cannot be zero"]);
                    } else {
                        #ok;
                    };
                };
                
                let choiceEqual = func(a : Choice, b : Choice) : Bool {
                    switch (a, b) {
                        case (#approve, #approve) true;
                        case (#reject, #reject) true;
                        case (#amendBudget(a), #amendBudget(b)) a == b;
                        case (_, _) false;
                    };
                };
                
                let choiceHash = func(choice : Choice) : Nat32 {
                    switch (choice) {
                        case (#approve) 0;
                        case (#reject) 1;
                        case (#amendBudget(_)) 2; // Simplified hash
                    };
                };
                
                let engine = ExtendedProposalEngine.ProposalEngine<system, ProposalContent, Choice>(
                    stableData, 
                    onExecute, 
                    onValidate, 
                    choiceEqual, 
                    choiceHash
                );
                
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                let stakeholder1 = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
                let stakeholder2 = Principal.fromText("ej7ca-hiaab-aaaba-aaaiq-cai");
                let stakeholder3 = Principal.fromText("6gntx-kaaab-eaaba-aaaiq-cai");
                let stakeholder4 = Principal.fromText("g5c5s-xyaab-aaabs-aaaiq-cai");
                
                // Create proposal for budget allocation
                let createResult = await* engine.createRealTimeProposal(
                    proposerId,
                    {
                        title = "Annual Budget Allocation";
                        budget = 1000000; // 1M units
                    },
                    10000 // Total voting power representing all stakeholders
                );
                let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal");
                
                // Add stakeholders dynamically as they provide proof of eligibility
                ignore engine.addMember(proposalId, { id = stakeholder1; votingPower = 3000 }); // 30%
                ignore engine.addMember(proposalId, { id = stakeholder2; votingPower = 2500 }); // 25%
                ignore engine.addMember(proposalId, { id = stakeholder3; votingPower = 2000 }); // 20%
                ignore engine.addMember(proposalId, { id = stakeholder4; votingPower = 1500 }); // 15%
                // Total so far: 9000 (90% of total voting power)
                
                // Start voting
                let vote1 = await* engine.vote(proposalId, stakeholder1, #approve); // 3000 votes for approve
                let #ok = vote1 else Debug.trap("Vote 1 failed");
                
                let vote2 = await* engine.vote(proposalId, stakeholder2, #amendBudget(800000)); // 2500 votes for amendment
                let #ok = vote2 else Debug.trap("Vote 2 failed");
                
                let vote3 = await* engine.vote(proposalId, stakeholder3, #amendBudget(800000)); // 2000 votes for same amendment
                let #ok = vote3 else Debug.trap("Vote 3 failed");
                
                // Check status - should not be executed yet
                // amendBudget has 4500 votes (45% of 10000), approve has 3000 (30%)
                // Need >60% of 10000 = >6000 votes
                let ?proposal = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
                switch (proposal.status) {
                    case (#open) Debug.print("✓ Proposal correctly remains open (45% < 60% threshold)");
                    case (_) Debug.trap("Expected proposal to remain open: " # debug_show(proposal.status));
                };
                
                // stakeholder4 votes for the amendment too, pushing it over the threshold
                let vote4 = await* engine.vote(proposalId, stakeholder4, #amendBudget(800000)); // 1500 votes
                let #ok = vote4 else Debug.trap("Vote 4 failed");
                
                // Now amendBudget has 6000 votes (60% exactly, but we need >60%)
                // Should still be open
                let ?proposal2 = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
                switch (proposal2.status) {
                    case (#open) Debug.print("✓ Proposal correctly remains open (60% == 60% threshold, need >60%)");
                    case (_) Debug.trap("Expected proposal to remain open: " # debug_show(proposal2.status));
                };
                
                // Add one more small stakeholder to push over the edge
                let smallStakeholder = Principal.fromText("3u5w5-zaaab-aqqba-aaaiq-cai");
                ignore engine.addMember(proposalId, { id = smallStakeholder; votingPower = 100 });
                
                let vote5 = await* engine.vote(proposalId, smallStakeholder, #amendBudget(800000));
                let #ok = vote5 else Debug.trap("Vote 5 failed");
                
                // Now amendBudget has 6100 votes (61% of 10000) - should NOT auto-execute (real-time mode)
                let ?proposal3 = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
                switch (proposal3.status) {
                    case (#open) {
                        Debug.print("✓ Real-time proposal correctly stays open despite reaching threshold");
                    };
                    case (_) Debug.trap("Expected real-time proposal to remain open: " # debug_show(proposal3.status));
                };
                
                Debug.print("✓ Complex real-time voting scenario completed successfully");
            }
        );
        
        await test(
            "real-time proposal - adding member to fixed proposal should fail",
            func() : async () {
                type ProposalContent = {
                    title : Text;
                    description : Text;
                };
                type Choice = {
                    #yes;
                    #no;
                };
                
                let stableData : ExtendedProposalEngine.StableData<ProposalContent, Choice> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 51; quorum = ?20 });
                    allowVoteChange = false;
                };
                
                let onExecute = func(_ : ?Choice, _ : ExtendedProposalEngine.Proposal<ProposalContent, Choice>) : async* Result.Result<(), Text> {
                    #ok;
                };
                
                let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
                    #ok;
                };
                
                let choiceEqual = func(a : Choice, b : Choice) : Bool { a == b };
                let choiceHash = func(choice : Choice) : Nat32 {
                    switch (choice) {
                        case (#yes) 0;
                        case (#no) 1;
                    };
                };
                
                let engine = ExtendedProposalEngine.ProposalEngine<system, ProposalContent, Choice>(
                    stableData, 
                    onExecute, 
                    onValidate, 
                    choiceEqual, 
                    choiceHash
                );
                
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                let member1 = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
                let member2 = Principal.fromText("ej7ca-hiaab-aaaba-aaaiq-cai");
                
                // Create traditional fixed proposal
                let members = [
                    { id = proposerId; votingPower = 1 },
                    { id = member1; votingPower = 1 },
                ];
                let createResult = await* engine.createProposal(proposerId, { title = "Fixed"; description = "Fixed"; }, members);
                let #ok(proposalId) = createResult else Debug.trap("Failed to create fixed proposal");
                
                // Try to add member to fixed proposal - should fail
                let addResult = engine.addMember(proposalId, { id = member2; votingPower = 1 });
                let #err(#notRealTimeProposal) = addResult else Debug.trap("Expected #notRealTimeProposal: " # debug_show(addResult));
                
                Debug.print("✓ Adding member to fixed proposal correctly failed");
            }
        );
    }
);
