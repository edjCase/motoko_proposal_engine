import { test; suite } "mo:test/async";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Array "mo:base/Array";
import ProposalEngine "../src/ProposalEngine";

// This test suite demonstrates the real-world use case of proof-on-demand
// voting where users prove their ETH chain balances to participate
await suite(
    "ETH Chain Proof-of-Balance Voting Scenarios",
    func() : async () {
        await test(
            "DAO treasury allocation - ETH holders vote on-demand",
            func() : async () {
                type TreasuryProposal = {
                    title : Text;
                    description : Text;
                    recipient : Text; // ETH address
                    amount : Nat; // Amount in Wei
                    category : {
                        #development;
                        #marketing;
                        #community;
                        #operations;
                    };
                };

                let stableData : ProposalEngine.StableData<TreasuryProposal> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 60; quorum = ?10 });
                    allowVoteChange = false;
                };

                let onExecute = func(proposal : ProposalEngine.Proposal<TreasuryProposal>) : async* Result.Result<(), Text> {
                    // In real implementation, this would trigger treasury transfer
                    Debug.print("🏦 Treasury transfer approved:");
                    Debug.print("  Recipient: " # proposal.content.recipient);
                    Debug.print("  Amount: " # debug_show (proposal.content.amount) # " Wei");
                    Debug.print("  Category: " # debug_show (proposal.content.category));
                    #ok;
                };

                let onReject = func(proposal : ProposalEngine.Proposal<TreasuryProposal>) : async* () {
                    Debug.print("❌ Treasury proposal rejected: " # proposal.content.title);
                };

                let onValidate = func(content : TreasuryProposal) : async* Result.Result<(), [Text]> {
                    var errors : [Text] = [];
                    if (content.amount == 0) {
                        errors := ["Amount must be greater than 0"];
                    };
                    if (content.recipient == "") {
                        errors := Array.append(errors, ["Recipient address cannot be empty"]);
                    };
                    if (errors.size() == 0) #ok else #err(errors);
                };

                let engine = ProposalEngine.ProposalEngine<system, TreasuryProposal>(
                    stableData,
                    onExecute,
                    onReject,
                    onValidate,
                );

                let proposerId = Principal.fromBlob("\04\08\01\0F"); // DAO coordinator

                // Total ETH supply eligible for voting (in ETH Wei equivalent voting power)
                // For example: 10,000 ETH total supply = 10,000 * 10^18 Wei
                // Simplified to 10,000,000 voting units for easier calculation
                let totalEligibleVotingPower = 10_000_000;

                // Create proposal for development funding
                let createResult = await* engine.createProposal(
                    proposerId,
                    {
                        title = "Q4 2024 Development Funding";
                        description = "Funding for core protocol development team";
                        recipient = "0x742d35Cc6634C0532925a3b8D581C462C5c50b3F";
                        amount = 500_000_000_000_000_000_000; // 500 ETH in Wei
                        category = #development;
                    },
                    [],
                    #dynamic({ totalVotingPower = ?totalEligibleVotingPower }),
                );
                let #ok(proposalId) = createResult else Debug.trap("Failed to create proposal");

                Debug.print("📝 Created treasury proposal with ID: " # debug_show (proposalId));
                Debug.print("💰 Total eligible voting power: " # debug_show (totalEligibleVotingPower));

                // === Users arrive with their balance proofs ===

                // Large ETH holder arrives with proof of 1000 ETH
                let whale = Principal.fromBlob("\04\08\01\0C");
                let whaleVotingPower = 1_000_000; // 1000 ETH equivalent
                ignore engine.addMember(proposalId, { id = whale; votingPower = whaleVotingPower });
                Debug.print("🐋 Whale joined with " # debug_show (whaleVotingPower) # " voting power");

                // Medium holder with 200 ETH
                let dolphin = Principal.fromBlob("\04\08\01\0D");
                let dolphinVotingPower = 200_000;
                ignore engine.addMember(proposalId, { id = dolphin; votingPower = dolphinVotingPower });
                Debug.print("🐬 Dolphin joined with " # debug_show (dolphinVotingPower) # " voting power");

                // Several smaller holders join over time
                let fish1 = Principal.fromBlob("\04\08\01\09");
                ignore engine.addMember(proposalId, { id = fish1; votingPower = 50_000 }); // 50 ETH

                let fish2 = Principal.fromBlob("\04\08\01\0A");
                ignore engine.addMember(proposalId, { id = fish2; votingPower = 25_000 }); // 25 ETH

                let fish3 = Principal.fromBlob("\04\08\01\0B");
                ignore engine.addMember(proposalId, { id = fish3; votingPower = 75_000 }); // 75 ETH

                Debug.print("🐠 Multiple smaller holders joined");

                // Start voting
                // Whale supports the proposal (10% of total supply)
                let whaleVote = await* engine.vote(proposalId, whale, true);
                let #ok = whaleVote else Debug.trap("Whale vote failed");
                Debug.print("🐋 Whale voted YES (10% of total supply)");

                // Dolphin also supports (2% more)
                let dolphinVote = await* engine.vote(proposalId, dolphin, true);
                let #ok = dolphinVote else Debug.trap("Dolphin vote failed");
                Debug.print("🐬 Dolphin voted YES (12% total support so far)");

                // Small fish vote - mixed opinions
                ignore await* engine.vote(proposalId, fish1, true); // 0.5% more support
                ignore await* engine.vote(proposalId, fish2, false); // 0.25% against
                ignore await* engine.vote(proposalId, fish3, true); // 0.75% more support

                Debug.print("🐠 Small holders voted - 12.75% total support");

                // Check current status - shouldn't execute yet (need 60% of 10M = 6M votes)
                // Current support: ~1.35M votes (13.5%) - way below threshold
                let ?currentProposal = engine.getProposal(proposalId) else Debug.trap("Proposal not found");
                switch (currentProposal.status) {
                    case (#open) Debug.print("✓ Proposal remains open (13.5% < 60% threshold)");
                    case (_) Debug.trap("Expected proposal to remain open");
                };

                // Large institution arrives late in the process with massive holdings
                let institution = Principal.fromBlob("\04\08\01\0E");
                let institutionVotingPower = 5_000_000; // 5000 ETH (50% of total!)
                ignore engine.addMember(proposalId, { id = institution; votingPower = institutionVotingPower });
                Debug.print("🏛️  Large institution joined with 50% of total supply!");

                // Institution votes YES - this should push proposal over the edge
                let institutionVote = await* engine.vote(proposalId, institution, true);
                let #ok = institutionVote else Debug.trap("Institution vote failed");

                // Total YES votes: 1M + 200K + 50K + 75K + 5M = ~6.325M (63.25%)
                // This exceeds 60% threshold but should NOT auto-execute in real-time mode
                let ?finalProposal = engine.getProposal(proposalId) else Debug.trap("Proposal not found");
                switch (finalProposal.status) {
                    case (#open) {
                        Debug.print("✓ Real-time proposal remains open despite reaching threshold");
                        Debug.print("🔧 Manual execution required for real-time proposals");
                    };
                    case (_) Debug.trap("Expected real-time proposal to remain open: " # debug_show (finalProposal.status));
                };

                // Show voting summary instead of calculating vote status
                let summary = engine.buildVotingSummary(proposalId);
                Debug.print("📊 Voting Summary: " # debug_show (summary));

                Debug.print("✅ Treasury voting scenario complete - demonstrates proof-of-balance voting");
            },
        );

        await test(
            "NFT governance - Holders vote on collection decisions",
            func() : async () {
                type NFTProposal = {
                    collectionId : Text;
                    action : {
                        #mint : Nat;
                        #burn : [Nat];
                        #transfer : { tokenId : Nat; to : Text };
                    };
                    rationale : Text;
                };

                let onExecute = func(proposal : ProposalEngine.Proposal<NFTProposal>) : async* Result.Result<(), Text> {
                    Debug.print("🎨 NFT governance action approved:");
                    Debug.print("  Collection: " # proposal.content.collectionId);
                    Debug.print("  Action: " # debug_show (proposal.content.action));
                    #ok;
                };

                let onReject = func(_proposal : ProposalEngine.Proposal<NFTProposal>) : async* () {
                    Debug.print("❌ NFT proposal rejected");
                };

                let onValidate = func(content : NFTProposal) : async* Result.Result<(), [Text]> {
                    if (content.collectionId == "") {
                        #err(["Collection ID cannot be empty"]);
                    } else {
                        #ok;
                    };
                };

                let nftStableData : ProposalEngine.StableData<NFTProposal> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 51; quorum = ?15 });
                    allowVoteChange = false;
                };

                let engine = ProposalEngine.ProposalEngine<system, NFTProposal>(
                    nftStableData,
                    onExecute,
                    onReject,
                    onValidate,
                );

                // Total NFT collection size: 10,000 NFTs
                // Each NFT holder gets voting power equal to their holdings
                let totalCollectionSize = 10_000;

                let proposerId = Principal.fromBlob("\04\08\01\02");
                let createResult = await* engine.createProposal(
                    proposerId,
                    {
                        collectionId = "CryptoPunks";
                        action = #mint(100); // Mint 100 new NFTs
                        rationale = "Expand collection to reward long-term holders";
                    },
                    [],
                    #dynamic({ totalVotingPower = ?totalCollectionSize }),
                );
                let #ok(proposalId) = createResult else Debug.trap("Failed to create NFT proposal");

                // Major holder with 500 NFTs joins
                let majorHolder = Principal.fromBlob("\04\08\01\03");
                ignore engine.addMember(proposalId, { id = majorHolder; votingPower = 500 });

                // Medium holders join
                let holder1 = Principal.fromBlob("\04\08\01\04");
                ignore engine.addMember(proposalId, { id = holder1; votingPower = 150 });

                let holder2 = Principal.fromBlob("\04\08\01\05");
                ignore engine.addMember(proposalId, { id = holder2; votingPower = 200 });

                // Vote on NFT expansion
                ignore await* engine.vote(proposalId, majorHolder, true);
                ignore await* engine.vote(proposalId, holder1, false);
                ignore await* engine.vote(proposalId, holder2, true);

                let ?_nftProposal = engine.getProposal(proposalId) else Debug.trap("NFT proposal not found");
                Debug.print("🎨 NFT governance voting complete - 700/10000 votes cast");

                Debug.print("✅ NFT governance scenario complete");
            },
        );

        await test(
            "Cross-chain voting - Bridge proposals with ETH stake verification",
            func() : async () {
                type CrossChainProposal = {
                    sourceChain : Text;
                    targetChain : Text;
                    bridgeAmount : Nat;
                    validatorSet : [Text];
                };

                let crossChainStableData : ProposalEngine.StableData<CrossChainProposal> = {
                    proposals = [];
                    proposalDuration = null;
                    votingThreshold = #percent({ percent = 67; quorum = ?20 });
                    allowVoteChange = false;
                };

                let onExecute = func(proposal : ProposalEngine.Proposal<CrossChainProposal>) : async* Result.Result<(), Text> {
                    Debug.print("🌉 Cross-chain bridge proposal approved:");
                    Debug.print("  Bridge: " # proposal.content.sourceChain # " → " # proposal.content.targetChain);
                    Debug.print("  Amount: " # debug_show (proposal.content.bridgeAmount));
                    #ok;
                };

                let onReject = func(_proposal : ProposalEngine.Proposal<CrossChainProposal>) : async* () {
                    Debug.print("Cross-chain bridging proposal rejected");
                };

                let onValidate = func(_content : CrossChainProposal) : async* Result.Result<(), [Text]> {
                    #ok;
                };

                let engine = ProposalEngine.ProposalEngine<system, CrossChainProposal>(
                    crossChainStableData,
                    onExecute,
                    onReject,
                    onValidate,
                );

                let coordinator = Principal.fromBlob("\04\08\01\06");
                let totalSupply = 50_000_000; // 50M tokens across chains

                let createResult = await* engine.createProposal(
                    coordinator,
                    {
                        sourceChain = "ethereum";
                        targetChain = "arbitrum";
                        bridgeAmount = 1_000_000;
                        validatorSet = ["validator1", "validator2", "validator3"];
                    },
                    [],
                    #dynamic({ totalVotingPower = ?totalSupply }),
                );
                let #ok(proposalId) = createResult else Debug.trap("Failed to create cross-chain proposal");

                // Add cross-chain token holders
                let ethHolder = Principal.fromBlob("\04\08\01\07");
                ignore engine.addMember(proposalId, { id = ethHolder; votingPower = 10_000_000 }); // 20%

                let arbHolder = Principal.fromBlob("\04\08\01\08");
                ignore engine.addMember(proposalId, { id = arbHolder; votingPower = 25_000_000 }); // 50%

                // Vote on bridge proposal
                ignore await* engine.vote(proposalId, ethHolder, true);
                ignore await* engine.vote(proposalId, arbHolder, true);

                let ?_crossProposal = engine.getProposal(proposalId) else Debug.trap("Cross-chain proposal not found");
                Debug.print("🌉 Cross-chain bridge voting complete - 70% participation, all in favor");

                Debug.print("✅ Cross-chain governance scenario complete");
            },
        );
    },
);
