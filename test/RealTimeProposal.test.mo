import { test; suite } "mo:test/async";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import ProposalEngine "../src/ProposalEngine";
import ExtendedProposalEngine "../src/ExtendedProposalEngine";
import ExtendedProposal "../src/ExtendedProposal";

await suite(
    "Real-time proposal tests",
    func() : async () {
        await test(
            "createRealTimeProposal - basic functionality",
            func() : async () {
                type ProposalContent = {
                    title : Text;
                    description : Text;
                };
                let stableData : ProposalEngine.StableData<ProposalContent> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 51; quorum = ?20 });
                    allowVoteChange = false;
                };
                let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
                    #ok;
                };
                let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {};
                let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
                    #ok;
                };
                
                let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                
                // Create real-time proposal with 1000 total voting power
                let createResult = await* engine.createRealTimeProposal(
                    proposerId,
                    {
                        title = "Real-time Proposal";
                        description = "Test real-time functionality";
                    },
                    1000
                );
                let #ok(proposalId) = createResult else Debug.trap("Failed to create real-time proposal: " # debug_show(createResult));
                
                let ?proposal = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
                
                // Verify proposal was created correctly
                assert proposal.id == proposalId;
                assert proposal.proposerId == proposerId;
                assert proposal.votes == []; // Should start with no votes
                
                Debug.print("✓ Real-time proposal created successfully");
            }
        );
        
        await test(
            "addMember - basic functionality",
            func() : async () {
                type ProposalContent = {
                    title : Text;
                    description : Text;
                };
                let stableData : ProposalEngine.StableData<ProposalContent> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 51; quorum = ?20 });
                    allowVoteChange = false;
                };
                let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
                    #ok;
                };
                let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {};
                let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
                    #ok;
                };
                
                let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                let member1 = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
                let member2 = Principal.fromText("ej7ca-hiaab-aaaba-aaaiq-cai");
                
                // Create real-time proposal
                let createResult = await* engine.createRealTimeProposal(proposerId, { title = "Test"; description = "Test"; }, 1000);
                let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal");
                
                // Add first member
                let addResult1 = engine.addMember(proposalId, { id = member1; votingPower = 250 });
                let #ok = addResult1 else Debug.trap("Failed to add member 1: " # debug_show(addResult1));
                
                // Add second member
                let addResult2 = engine.addMember(proposalId, { id = member2; votingPower = 300 });
                let #ok = addResult2 else Debug.trap("Failed to add member 2: " # debug_show(addResult2));
                
                let ?proposal = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
                assert proposal.votes.size() == 2;
                
                Debug.print("✓ Members added successfully to real-time proposal");
            }
        );
        
        await test(
            "addMember - duplicate member should fail",
            func() : async () {
                type ProposalContent = {
                    title : Text;
                    description : Text;
                };
                let stableData : ProposalEngine.StableData<ProposalContent> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 51; quorum = ?20 });
                    allowVoteChange = false;
                };
                let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
                    #ok;
                };
                let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {};
                let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
                    #ok;
                };
                
                let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                let member1 = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
                
                // Create real-time proposal
                let createResult = await* engine.createRealTimeProposal(proposerId, { title = "Test"; description = "Test"; }, 1000);
                let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal");
                
                // Add member
                let addResult1 = engine.addMember(proposalId, { id = member1; votingPower = 250 });
                let #ok = addResult1 else Debug.trap("Failed to add member 1");
                
                // Try to add same member again
                let addResult2 = engine.addMember(proposalId, { id = member1; votingPower = 300 });
                let #err(#alreadyExists) = addResult2 else Debug.trap("Expected #alreadyExists error: " # debug_show(addResult2));
                
                Debug.print("✓ Duplicate member correctly rejected");
            }
        );
        
        await test(
            "real-time proposal voting - threshold not met",
            func() : async () {
                type ProposalContent = {
                    title : Text;
                    description : Text;
                };
                let stableData : ProposalEngine.StableData<ProposalContent> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 51; quorum = ?20 });
                    allowVoteChange = false;
                };
                let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
                    #ok;
                };
                let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {};
                let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
                    #ok;
                };
                
                let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                let member1 = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
                let member2 = Principal.fromText("ej7ca-hiaab-aaaba-aaaiq-cai");
                
                // Create real-time proposal with 1000 total voting power
                let createResult = await* engine.createRealTimeProposal(proposerId, { title = "Test"; description = "Test"; }, 1000);
                let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal");
                
                // Add members with total 500 voting power (50% of total)
                ignore engine.addMember(proposalId, { id = member1; votingPower = 250 });
                ignore engine.addMember(proposalId, { id = member2; votingPower = 250 });
                
                // Vote with both members for "true" - this gives 500 voting power (50%)
                // Should NOT auto-execute since we need >51% of 1000 = >510
                let voteResult1 = await* engine.vote(proposalId, member1, true);
                let #ok = voteResult1 else Debug.trap("Vote 1 failed");
                
                let voteResult2 = await* engine.vote(proposalId, member2, true);
                let #ok = voteResult2 else Debug.trap("Vote 2 failed");
                
                // Proposal should still be open (not auto-executed)
                let ?proposal = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
                switch (proposal.status) {
                    case (#open) Debug.print("✓ Proposal correctly remains open");
                    case (_) Debug.trap("Expected proposal to remain open: " # debug_show(proposal.status));
                };
            }
        );
        
        await test(
            "real-time proposal voting - threshold met, NO auto-execute",
            func() : async () {
                type ProposalContent = {
                    title : Text;
                    description : Text;
                };
                let stableData : ProposalEngine.StableData<ProposalContent> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 51; quorum = ?20 });
                    allowVoteChange = false;
                };
                let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
                    #ok;
                };
                let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {};
                let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
                    #ok;
                };
                
                let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                let member1 = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
                let member2 = Principal.fromText("ej7ca-hiaab-aaaba-aaaiq-cai");
                let member3 = Principal.fromText("6gntx-kaaab-eaaba-aaaiq-cai");
                
                // Create real-time proposal with 1000 total voting power
                let createResult = await* engine.createRealTimeProposal(proposerId, { title = "Test"; description = "Test"; }, 1000);
                let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal");
                
                // Add members with enough voting power to exceed threshold
                ignore engine.addMember(proposalId, { id = member1; votingPower = 300 });
                ignore engine.addMember(proposalId, { id = member2; votingPower = 250 });
                ignore engine.addMember(proposalId, { id = member3; votingPower = 200 }); // Total available: 750
                
                // Vote with enough power to exceed 51% of 1000 = >510
                let voteResult1 = await* engine.vote(proposalId, member1, true); // 300 votes for true
                let #ok = voteResult1 else Debug.trap("Vote 1 failed");
                
                let voteResult2 = await* engine.vote(proposalId, member2, true); // 250 votes for true (total: 550)
                let #ok = voteResult2 else Debug.trap("Vote 2 failed");
                
                // Should NOT auto-execute even though 550 > 510 (51% of 1000) - real-time mode
                let ?proposal = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
                switch (proposal.status) {
                    case (#open) {
                        Debug.print("✓ Real-time proposal correctly stays open despite reaching threshold");
                    };
                    case (_) Debug.trap("Expected real-time proposal to remain open: " # debug_show(proposal.status));
                };
            }
        );
        
        await test(
            "real-time vs fixed member comparison",
            func() : async () {
                type ProposalContent = {
                    title : Text;
                    description : Text;
                };
                let stableData : ProposalEngine.StableData<ProposalContent> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 51; quorum = ?20 });
                    allowVoteChange = false;
                };
                let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
                    #ok;
                };
                let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {};
                let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
                    #ok;
                };
                
                let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                let member1 = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
                
                // Create traditional fixed member proposal
                let members = [
                    { votingPower = 1; id = proposerId },
                    { votingPower = 1; id = member1 },
                ];
                let createFixed = await* engine.createProposal(proposerId, { title = "Fixed"; description = "Fixed"; }, members);
                let #ok(fixedId) = createFixed else Debug.trap("Failed to create fixed proposal");
                
                // Create real-time proposal with same effective total
                let createRealTime = await* engine.createRealTimeProposal(proposerId, { title = "RealTime"; description = "RealTime"; }, 2);
                let #ok(realTimeId) = createRealTime else Debug.trap("Failed to create real-time proposal");
                
                // Add same members to real-time proposal
                ignore engine.addMember(realTimeId, { id = proposerId; votingPower = 1 });
                ignore engine.addMember(realTimeId, { id = member1; votingPower = 1 });
                
                // Vote with one member in each proposal (50% - should not execute)
                let voteFixed = await* engine.vote(fixedId, proposerId, true);
                let #ok = voteFixed else Debug.trap("Fixed vote failed");
                
                let voteRealTime = await* engine.vote(realTimeId, proposerId, true);
                let #ok = voteRealTime else Debug.trap("Real-time vote failed");
                
                // Both should remain open since 1 vote = 50%, need >51%
                let ?fixedProposal = engine.getProposal(fixedId) else Debug.trap("Failed to get fixed proposal");
                let ?realTimeProposal = engine.getProposal(realTimeId) else Debug.trap("Failed to get real-time proposal");
                
                switch (fixedProposal.status, realTimeProposal.status) {
                    case (#open, #open) Debug.print("✓ Both proposals correctly remain open");
                    case (_) Debug.trap("Expected both proposals to remain open");
                };
                
                Debug.print("✓ Fixed and real-time proposals behave consistently");
            }
        );
        
        await test(
            "ExtendedProposal.addMember direct test",
            func() : async () {
                let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
                let member1 = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
                
                // Create a real-time proposal
                let proposal = ExtendedProposal.createRealTime<{title: Text}, Bool>(
                    1,
                    proposerId,
                    {title = "Real-time Test"},
                    1000, // totalVotingPower
                    0, // timeStart
                    null // timeEnd
                );
                
                assert proposal.mode == #realTime;
                assert proposal.totalVotingPower == ?1000;
                assert proposal.votes == [];
                
                // Add member 1
                let addResult1 = ExtendedProposal.addMember(proposal, { votingPower = 100; id = member1 });
                let #ok(proposal1) = addResult1 else Debug.trap("Add member 1 failed: " # debug_show(addResult1));
                
                assert proposal1.votes.size() == 1;
                let (memberId, vote) = proposal1.votes[0];
                assert memberId == member1;
                assert vote.votingPower == 100;
                assert vote.choice == null;
                
                // Try to add same member again - should fail
                let addResult2 = ExtendedProposal.addMember(proposal1, { votingPower = 150; id = member1 });
                let #err(#alreadyExists) = addResult2 else Debug.trap("Expected #alreadyExists: " # debug_show(addResult2));
                
                Debug.print("✓ ExtendedProposal.addMember works correctly");
            }
        );
    }
);
