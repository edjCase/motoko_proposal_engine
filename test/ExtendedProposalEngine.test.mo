import { test } "mo:test/async";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import ExtendedProposalEngine "../src/ExtendedProposalEngine";

await test(
    "33/33/33 no consensus",
    func() : async () {
        type ProposalContent = {
            title : Text;
            description : Text;
        };
        let stableData : ExtendedProposalEngine.StableData<ProposalContent, Nat> = {
            proposals = [];
            proposalDuration = null;
            votingThreshold = #percent({ percent = 50; quorum = ?20 });
        };
        let onExecute = func(_ : ?Nat, _ : ExtendedProposalEngine.Proposal<ProposalContent, Nat>) : async* Result.Result<(), Text> {
            #ok;
        };
        let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
            #ok;
        };
        let engine = ExtendedProposalEngine.ProposalEngine<system, ProposalContent, Nat>(stableData, onExecute, onValidate, Nat.equal, Nat32.fromNat);
        let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
        let members = [
            { votingPower = 1; id = proposerId },
            {
                votingPower = 1;
                id = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("ej7ca-hiaab-aaaba-aaaiq-cai");
            },
        ];

        let createResult = await* engine.createProposal(
            proposerId,
            {
                title = "Test";
                description = "Test";
            },
            members,
        );
        let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal. Errors:" # debug_show (createResult));

        let vote1Result = await* engine.vote(proposalId, members[0].id, 0);
        let #ok = vote1Result else Debug.trap("Expected vote 1 to be #ok. Actual:" # debug_show (vote1Result));

        let vote2Result = await* engine.vote(proposalId, members[1].id, 1);
        let #ok = vote2Result else Debug.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

        let vote3Result = await* engine.vote(proposalId, members[2].id, 2);
        let #ok = vote3Result else Debug.trap("Expected vote 3 to be #ok. Actual:" # debug_show (vote3Result));

        let ?r = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
        switch (r.status) {
            case (#executed(executed)) {
                switch (executed.choice) {
                    case (null) ();
                    case (_) Debug.trap("Expected choice to be null. Actual:" # debug_show (executed.choice));
                };
            };
            case (_) Debug.trap("Expected #executed(_) status. Actual:" # debug_show (r.status));
        };
    },
);

await test(
    "50%+, 20%+ quorum, execute",
    func() : async () {
        type ProposalContent = {
            title : Text;
            description : Text;
        };
        let stableData : ExtendedProposalEngine.StableData<ProposalContent, Nat> = {
            proposals = [];
            proposalDuration = null;
            votingThreshold = #percent({ percent = 50; quorum = ?20 });
        };
        let onExecute = func(_ : ?Nat, _ : ExtendedProposalEngine.Proposal<ProposalContent, Nat>) : async* Result.Result<(), Text> {
            #ok;
        };
        let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
            #ok;
        };
        let engine = ExtendedProposalEngine.ProposalEngine<system, ProposalContent, Nat>(stableData, onExecute, onValidate, Nat.equal, Nat32.fromNat);
        let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
        let members = [
            { votingPower = 1; id = proposerId },
            {
                votingPower = 1;
                id = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("ej7ca-hiaab-aaaba-aaaiq-cai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("6gntx-kaaab-eaaba-aaaiq-cai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("g5c5s-xyaab-aaabs-aaaiq-cai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("3u5w5-zaaab-aqqba-aaaiq-cai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("uoq3o-oiaab-zzaab-aaaai-qcai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("futcu-4iaab-aaara-aaaiq-cai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("r4mcr-paaab-aaaba-ffaiq-cai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("v7dqd-jaaab-aaaba-qqaiq-cai");
            },
        ];

        let createResult = await* engine.createProposal(
            proposerId,
            {
                title = "Test";
                description = "Test";
            },
            members,
        );
        let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal. Errors:" # debug_show (createResult));

        let vote1Result = await* engine.vote(proposalId, members[0].id, 0);
        let #ok = vote1Result else Debug.trap("Expected vote 1 to be #ok. Actual:" # debug_show (vote1Result));

        let vote2Result = await* engine.vote(proposalId, members[1].id, 0);
        let #ok = vote2Result else Debug.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

        let endResult = await* engine.endProposal(proposalId);
        let #ok = endResult else Debug.trap("Expected end to be #ok. Actual:" # debug_show (endResult));

        let ?r = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
        switch (r.status) {
            case (#executed(executed)) {
                switch (executed.choice) {
                    case (?0) ();
                    case (_) Debug.trap("Expected choice to be null. Actual:" # debug_show (executed.choice));
                };
            };
            case (_) Debug.trap("Expected #executed(_) status. Actual:" # debug_show (r.status));
        };
    },
);

await test(
    "50/50 reject",
    func() : async () {
        type ProposalContent = {
            title : Text;
            description : Text;
        };
        let stableData : ExtendedProposalEngine.StableData<ProposalContent, Nat> = {
            proposals = [];
            proposalDuration = null;
            votingThreshold = #percent({ percent = 50; quorum = ?20 });
        };
        let onExecute = func(_ : ?Nat, _ : ExtendedProposalEngine.Proposal<ProposalContent, Nat>) : async* Result.Result<(), Text> {
            #ok;
        };
        let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
            #ok;
        };
        let engine = ExtendedProposalEngine.ProposalEngine<system, ProposalContent, Nat>(stableData, onExecute, onValidate, Nat.equal, Nat32.fromNat);
        let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
        let members = [
            { votingPower = 1; id = proposerId },
            {
                votingPower = 1;
                id = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
            },
        ];

        let createResult = await* engine.createProposal(
            proposerId,
            {
                title = "Test";
                description = "Test";
            },
            members,
        );
        let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal. Errors:" # debug_show (createResult));

        let vote1Result = await* engine.vote(proposalId, members[0].id, 1);
        let #ok = vote1Result else Debug.trap("Expected vote 1 to be #ok. Actual:" # debug_show (vote1Result));

        let vote2Result = await* engine.vote(proposalId, members[1].id, 0);
        let #ok = vote2Result else Debug.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

        let ?r = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
        switch (r.status) {
            case (#executed(executed)) {
                switch (executed.choice) {
                    case (null) ();
                    case (_) Debug.trap("Expected choice to be null. Actual:" # debug_show (executed.choice));
                };
            };
            case (_) Debug.trap("Expected #executed(_) status. Actual:" # debug_show (r.status));
        };
    },
);

// Create test for proposal that is executed
await test(
    "50%+ yes vote, execute",
    func() : async () {
        type ProposalContent = {
            title : Text;
            description : Text;
        };
        let stableData : ExtendedProposalEngine.StableData<ProposalContent, Nat> = {
            proposals = [];
            proposalDuration = null;
            votingThreshold = #percent({ percent = 50; quorum = ?20 });
        };
        let onExecute = func(_ : ?Nat, _ : ExtendedProposalEngine.Proposal<ProposalContent, Nat>) : async* Result.Result<(), Text> {
            #ok;
        };
        let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
            #ok;
        };
        let engine = ExtendedProposalEngine.ProposalEngine<system, ProposalContent, Nat>(stableData, onExecute, onValidate, Nat.equal, Nat32.fromNat);
        let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
        let members = [
            { votingPower = 1; id = proposerId },
            {
                votingPower = 1;
                id = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
            },
        ];

        let createResult = await* engine.createProposal(
            proposerId,
            {
                title = "Test";
                description = "Test";
            },
            members,
        );
        let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal. Errors:" # debug_show (createResult));

        let vote1Result = await* engine.vote(proposalId, members[0].id, 1);
        let #ok = vote1Result else Debug.trap("Expected vote 1 to be #ok. Actual:" # debug_show (vote1Result));

        let vote2Result = await* engine.vote(proposalId, members[1].id, 1);
        let #ok = vote2Result else Debug.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

        let ?r = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");

        switch (r.status) {
            case (#executed(executed)) {
                switch (executed.choice) {
                    case (?1) ();
                    case (_) Debug.trap("Expected choice to be 1. Actual:" # debug_show (executed.choice));
                };
            };
            case (_) Debug.trap("Expected #executed(_) status. Actual:" # debug_show (r.status));
        };
    },
);

await test(
    "50%+ no vote, reject",
    func() : async () {
        type ProposalContent = {
            title : Text;
            description : Text;
        };
        let stableData : ExtendedProposalEngine.StableData<ProposalContent, Nat> = {
            proposals = [];
            proposalDuration = null;
            votingThreshold = #percent({ percent = 50; quorum = ?20 });
        };
        let onExecute = func(_ : ?Nat, _ : ExtendedProposalEngine.Proposal<ProposalContent, Nat>) : async* Result.Result<(), Text> {
            #ok;
        };
        let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
            #ok;
        };
        let engine = ExtendedProposalEngine.ProposalEngine<system, ProposalContent, Nat>(stableData, onExecute, onValidate, Nat.equal, Nat32.fromNat);
        let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
        let members = [
            { votingPower = 1; id = proposerId },
            {
                votingPower = 3;
                id = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
            },
            {
                votingPower = 1;
                id = Principal.fromText("ej7ca-hiaab-aaaba-aaaiq-cai");
            },
        ];

        let createResult = await* engine.createProposal(
            proposerId,
            {
                title = "Test";
                description = "Test";
            },
            members,
        );
        let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal. Errors:" # debug_show (createResult));

        let vote1Result = await* engine.vote(proposalId, members[0].id, 0);
        let #ok = vote1Result else Debug.trap("Expected vote 1 to be #ok. Actual:" # debug_show (vote1Result));

        let vote2Result = await* engine.vote(proposalId, members[1].id, 0);
        let #ok = vote2Result else Debug.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

        // vote 3 is not needed to reject

        let ?r = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
        switch (r.status) {
            case (#executed(executed)) {
                switch (executed.choice) {
                    case (?0) ();
                    case (_) Debug.trap("Expected choice to be false. Actual:" # debug_show (executed.choice));
                };
            };
            case (_) Debug.trap("Expected #executed(_) status. Actual:" # debug_show (r.status));
        };
    },
);
