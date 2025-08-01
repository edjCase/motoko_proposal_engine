import { test } "mo:test/async";
import Result "mo:core/Result";
import Principal "mo:core/Principal";
import ProposalEngine "../src/ProposalEngine";
import Runtime "mo:core/Runtime";
import BTree "mo:stableheapbtreemap/BTree";

await test(
  "50/50 reject",
  func() : async () {
    type ProposalContent = {
      title : Text;
      description : Text;
    };
    let stableData : ProposalEngine.StableData<ProposalContent> = {
      proposals = BTree.init<Nat, ProposalEngine.ProposalData<ProposalContent>>(null);
      proposalDuration = null;
      votingThreshold = #percent({ percent = 50; quorum = ?20 });
      allowVoteChange = false;
    };
    let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
      #ok;
    };
    let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {

    };
    let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
      #ok;
    };
    let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
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
      #snapshot,
    );
    let #ok(proposalId) = createResult else Runtime.trap("Failed to create proposal. Errors:" # debug_show (createResult));

    let vote1Result = await* engine.vote(proposalId, members[0].id, true);
    let #ok = vote1Result else Runtime.trap("Expected vote 1 to be #ok. Actual:" # debug_show (vote1Result));

    let vote2Result = await* engine.vote(proposalId, members[1].id, false);
    let #ok = vote2Result else Runtime.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

    let ?r = engine.getProposal(proposalId) else Runtime.trap("Failed to get proposal");
    switch (r.status) {
      case (#executed(executed)) {
        switch (executed.choice) {
          case (null) ();
          case (_) Runtime.trap("Expected choice to be null. Actual:" # debug_show (executed.choice));
        };
      };
      case (_) Runtime.trap("Expected #executed(_) status. Actual:" # debug_show (r.status));
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
    let stableData : ProposalEngine.StableData<ProposalContent> = {
      proposals = BTree.init<Nat, ProposalEngine.ProposalData<ProposalContent>>(null);
      proposalDuration = null;
      votingThreshold = #percent({ percent = 50; quorum = ?20 });
      allowVoteChange = false;
    };
    let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
      #ok;
    };
    let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {

    };
    let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
      #ok;
    };
    let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
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
      #snapshot,
    );
    let #ok(proposalId) = createResult else Runtime.trap("Failed to create proposal. Errors:" # debug_show (createResult));

    let vote1Result = await* engine.vote(proposalId, members[0].id, true);
    let #ok = vote1Result else Runtime.trap("Expected vote 1 to be #ok. Actual:" # debug_show (vote1Result));

    let vote2Result = await* engine.vote(proposalId, members[1].id, true);
    let #ok = vote2Result else Runtime.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

    let endResult = await* engine.endProposal(proposalId);
    let #ok = endResult else Runtime.trap("Expected end to be #ok. Actual:" # debug_show (endResult));

    let ?r = engine.getProposal(proposalId) else Runtime.trap("Failed to get proposal");
    switch (r.status) {
      case (#executed(executed)) {
        switch (executed.choice) {
          case (?true) ();
          case (_) Runtime.trap("Expected choice to be null. Actual:" # debug_show (executed.choice));
        };
      };
      case (_) Runtime.trap("Expected #executed(_) status. Actual:" # debug_show (r.status));
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
    let stableData : ProposalEngine.StableData<ProposalContent> = {
      proposals = BTree.init<Nat, ProposalEngine.ProposalData<ProposalContent>>(null);
      proposalDuration = null;
      votingThreshold = #percent({ percent = 50; quorum = ?20 });
      allowVoteChange = false;
    };
    let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
      #ok;
    };
    let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {

    };
    let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
      #ok;
    };
    let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
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
      #snapshot,
    );
    let #ok(proposalId) = createResult else Runtime.trap("Failed to create proposal. Errors:" # debug_show (createResult));

    let vote1Result = await* engine.vote(proposalId, members[0].id, true);
    let #ok = vote1Result else Runtime.trap("Expected vote 1 to be #ok. Actual:" # debug_show (vote1Result));

    let vote2Result = await* engine.vote(proposalId, members[1].id, true);
    let #ok = vote2Result else Runtime.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

    let ?r = engine.getProposal(proposalId) else Runtime.trap("Failed to get proposal");

    switch (r.status) {
      case (#executed(executed)) {
        switch (executed.choice) {
          case (?true) ();
          case (_) Runtime.trap("Expected choice to be true. Actual:" # debug_show (executed.choice));
        };
      };
      case (_) Runtime.trap("Expected #executed(_) status. Actual:" # debug_show (r.status));
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
    let stableData : ProposalEngine.StableData<ProposalContent> = {
      proposals = BTree.init<Nat, ProposalEngine.ProposalData<ProposalContent>>(null);
      proposalDuration = null;
      votingThreshold = #percent({ percent = 50; quorum = ?20 });
      allowVoteChange = false;
    };
    let onExecute = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
      #ok;
    };
    let onReject = func(_ : ProposalEngine.Proposal<ProposalContent>) : async* () {

    };
    let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
      #ok;
    };
    let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
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
      #snapshot,
    );
    let #ok(proposalId) = createResult else Runtime.trap("Failed to create proposal. Errors:" # debug_show (createResult));

    let vote1Result = await* engine.vote(proposalId, members[0].id, false);
    let #ok = vote1Result else Runtime.trap("Expected vote 1 to be #ok. Actual:" # debug_show (vote1Result));

    let vote2Result = await* engine.vote(proposalId, members[1].id, false);
    let #ok = vote2Result else Runtime.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

    // vote 3 is not needed to reject

    let ?r = engine.getProposal(proposalId) else Runtime.trap("Failed to get proposal");
    switch (r.status) {
      case (#executed(executed)) {
        switch (executed.choice) {
          case (?false) ();
          case (_) Runtime.trap("Expected choice to be false. Actual:" # debug_show (executed.choice));
        };
      };
      case (_) Runtime.trap("Expected #executed(_) status. Actual:" # debug_show (r.status));
    };
  },
);
