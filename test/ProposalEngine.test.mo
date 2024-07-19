// import { test } "mo:test/async";
// import Result "mo:base/Result";
// import Principal "mo:base/Principal";
// import Debug "mo:base/Debug";
// import ProposalEngine "../src/ProposalEngine";
// import Types "../src/Types";

// TODO needs timer support
// await test(
//   "50/50 reject",
//   func() : async () {
//     type ProposalContent = {
//       title : Text;
//       description : Text;
//     };
//     let stableData : Types.StableData<ProposalContent> = {
//       proposals = [];
//       proposalDuration = #days(3);
//       votingThreshold = #percent({ percent = 50; quorum = ?20 });
//     };
//     let onExecute = func(_ : Types.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
//       #ok;
//     };
//     let onReject = func(_ : Types.Proposal<ProposalContent>) : async* () {

//     };
//     let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
//       #ok;
//     };
//     let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
//     let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
//     let members = [
//       { votingPower = 1; id = proposerId },
//       {
//         votingPower = 1;
//         id = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
//       },
//     ];

//     let createResult = await* engine.createProposal(
//       proposerId,
//       {
//         title = "Test";
//         description = "Test";
//       },
//       members,
//     );
//     let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal. Errors:" # debug_show (createResult));

//     let vote1Result = await* engine.vote(proposalId, members[0].id, true);
//     let #err(#alreadyVoted) = vote1Result else Debug.trap("Expected vote 1 to already have voted. Actual:" # debug_show (vote1Result));

//     let vote2Result = await* engine.vote(proposalId, members[1].id, false);
//     let #ok = vote2Result else Debug.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

//     let ?r = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
//     if (r.statusLog.size() != 1) {
//       Debug.trap("Expected 1 status log entry. Actual:" # debug_show (r.statusLog));
//     };
//     switch (r.statusLog[0]) {
//       case (#rejected(_)) {};
//       case (_) Debug.trap("Expected rejected status log entry. Actual:" # debug_show (r.statusLog[0]));
//     };

//   },
// );

// // Create test for proposal that is executed
// await test(
//   "50%+ yes vote, execute",
//   func() : async () {
//     type ProposalContent = {
//       title : Text;
//       description : Text;
//     };
//     let stableData : Types.StableData<ProposalContent> = {
//       proposals = [];
//       proposalDuration = #days(3);
//       votingThreshold = #percent({ percent = 50; quorum = ?20 });
//     };
//     let onExecute = func(_ : Types.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
//       #ok;
//     };
//     let onReject = func(_ : Types.Proposal<ProposalContent>) : async* () {

//     };
//     let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
//       #ok;
//     };
//     let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
//     let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
//     let members = [
//       { votingPower = 1; id = proposerId },
//       {
//         votingPower = 1;
//         id = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
//       },
//     ];

//     let createResult = await* engine.createProposal(
//       proposerId,
//       {
//         title = "Test";
//         description = "Test";
//       },
//       members,
//     );
//     let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal. Errors:" # debug_show (createResult));

//     let vote1Result = await* engine.vote(proposalId, members[0].id, true);
//     let #err(#alreadyVoted) = vote1Result else Debug.trap("Expected vote 1 to already have voted. Actual:" # debug_show (vote1Result));

//     let vote2Result = await* engine.vote(proposalId, members[1].id, true);
//     let #ok = vote2Result else Debug.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

//     let ?r = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
//     if (r.statusLog.size() != 2) {
//       Debug.trap("Expected 2 status log entry. Actual:" # debug_show (r.statusLog));
//     };

//     let #executing(_) = r.statusLog[0] else Debug.trap("Expected executing status log entry. Actual:" # debug_show (r.statusLog[0]));
//     let #executed(_) = r.statusLog[1] else Debug.trap("Expected executed status log entry. Actual:" # debug_show (r.statusLog[1]));
//   },
// );

// await test(
//   "50%+ no vote, reject",
//   func() : async () {
//     type ProposalContent = {
//       title : Text;
//       description : Text;
//     };
//     let stableData : Types.StableData<ProposalContent> = {
//       proposals = [];
//       proposalDuration = #days(3);
//       votingThreshold = #percent({ percent = 50; quorum = ?20 });
//     };
//     let onExecute = func(_ : Types.Proposal<ProposalContent>) : async* Result.Result<(), Text> {
//       #ok;
//     };
//     let onReject = func(_ : Types.Proposal<ProposalContent>) : async* () {

//     };
//     let onValidate = func(_ : ProposalContent) : async* Result.Result<(), [Text]> {
//       #ok;
//     };
//     let engine = ProposalEngine.ProposalEngine<system, ProposalContent>(stableData, onExecute, onReject, onValidate);
//     let proposerId = Principal.fromText("sbzkb-zqaaa-aaaaa-aaaiq-cai");
//     let members = [
//       { votingPower = 1; id = proposerId },
//       {
//         votingPower = 3;
//         id = Principal.fromText("bpr6f-4aaaa-aaaba-aaaiq-cai");
//       },
//       {
//         votingPower = 1;
//         id = Principal.fromText("ej7ca-hiaab-aaaba-aaaiq-cai");
//       },
//     ];

//     let createResult = await* engine.createProposal(
//       proposerId,
//       {
//         title = "Test";
//         description = "Test";
//       },
//       members,
//     );
//     let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal. Errors:" # debug_show (createResult));

//     let vote1Result = await* engine.vote(proposalId, members[0].id, false);
//     let #err(#alreadyVoted) = vote1Result else Debug.trap("Expected vote 1 to already have voted. Actual:" # debug_show (vote1Result));

//     let vote2Result = await* engine.vote(proposalId, members[1].id, false);
//     let #ok = vote2Result else Debug.trap("Expected vote 2 to be #ok. Actual:" # debug_show (vote2Result));

//     // vote 3 is not needed to reject

//     let ?r = engine.getProposal(proposalId) else Debug.trap("Failed to get proposal");
//     if (r.statusLog.size() != 1) {
//       Debug.trap("Expected 1 status log entry. Actual:" # debug_show (r.statusLog));
//     };
//     let #rejected(_) = r.statusLog[0] else Debug.trap("Expected rejected status log entry. Actual:" # debug_show (r.statusLog[0]));
//   },
// );
