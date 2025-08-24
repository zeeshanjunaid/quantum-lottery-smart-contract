## Quantum Lottery — Smart Contracts (Foundry)

![CI](https://github.com/zeeshanjunaid/quantum-lottery-smart-contract/actions/workflows/ci.yml/badge.svg)

Modular, gas-aware lottery contracts with Chainlink VRF, chunked processing, Q-score streaks, and refund safety. Built with Foundry, OpenZeppelin, and Chainlink VRF v2.

### Highlights
- Thin wrapper `QuantumLottery.sol` with `QuantumLotteryBase.sol` implementation for clean codegen and coverage
- Concern-specific libraries to keep functions small, testable, and gas-efficient
- Chainlink VRF v2 integration and chunked post-fulfillment processing to avoid block gas limits
- Two ticket types (Standard/Quantum), Q-score streak system, and a "cosmic surge" multiplier window
- Safe refund flow for force-resolved draws and guarded withdrawal of unclaimed refunds

## Architecture

- `src/QuantumLottery.sol`: Thin wrapper that inherits `QuantumLotteryBase` and forwards constructor args
- `src/QuantumLotteryBase.sol`: Core implementation, events, and external/public API
- `src/QuantumLotteryTypes.sol`: Enums, structs, events, and constants
- Libraries (separation of concerns):
	- `QuantumLotteryProcessor.sol`: draw processing, winner updates, payouts
	- `QuantumLotteryFulfillment.sol`: randomness fulfillment + total Q-score calc
	- `QuantumLotteryEntry.sol`: ticket purchase and accounting
	- `QuantumLotteryCleanup.sol`: storage cleanup in chunks
	- `QuantumLotteryRefunds.sol`: CEI-compliant refund logic
	- `QuantumLotteryWithdraw.sol`: compute and zero unclaimed refunds
	- `QuantumLotteryForceResolve.sol`: forceful resolution if VRF stalls
	- `QuantumLotteryHelpers.sol`: Q-score increase helper

Core dependencies:
- Solidity ^0.8.20
- OpenZeppelin (Ownable v5, ReentrancyGuard, IERC20, SafeERC20, Math)
- Chainlink VRF v2 (coordinator + consumer base)

## Key constants (see `QuantumLotteryTypes.sol`)
- Standard ticket: `STANDARD_TICKET_PRICE = 10_000_000` (10 USDC, 6 decimals)
- Quantum ticket: `QUANTUM_TICKET_PRICE = 30_000_000` (30 USDC)
- Winner payout percent: `WINNER_PAYOUT_PERCENT = 92` (treasury fee 8%)
- Max Q-score: `MAX_QSCORE = 100_000`
- Seconds per hour: `SECONDS_PER_HOUR = 3600`
- VRF gas limit: `CALLBACK_GAS_LIMIT = 2_500_000`

## Draw lifecycle
1) OPEN: Users call `buyTicket(ticketType)` to join the current hour's draw
2) CALCULATING_WINNER: Owner calls `requestRandomWinner(hourId)` for a past hour; VRF request sent
3) RESOLVING: On VRF callback, randomness is recorded; chunked processing is required to finish
4) RESOLVED: After `processDrawChunk(hourId, iterations)` completes, payouts are done and `cleanupPending = true`
5) Cleanup: Call `cleanupDrawChunk(hourId, iterations)` until it completes to clear per-draw mappings

Why chunks? Large draws can't do all work in a single transaction (block gas limits). We split winner selection and per-player updates across multiple calls.

## Refunds and force-resolve

getrVG for longer than `MAXWAT_HRS = 24call fta:
1) Candrlaany pending VRF w quegt fersthat dcaw
2)iMark n CAdCawTas RESOLVED wiGh_W NummyNwinner
3) AR orRnormSlVIGooessrng lod payounger hont nue

MAX_WAs aOe=o2ly poss`ble for force-resol,et drews. Users can ca o)`reCundTicknt(houcpd foick tId)`tth g trbwckthir ticktpic USDC.

Uncamed refunds cn e whdrawn beowner via  Mark t()`haeter aEgrLcEDhdriou.mThywngardtove rentacy ndaccog errors.
3) Allow normal processing and payout to continue
SecurtyInfm

Wn r ksrsecrrioylsevidusly. If yer all everyou'vunfound Tesecur(hyuvulnedab lity,lae:

1. no opn  publcsue.
2. Email temataiprivaty: suriy@vli.examle
3. Prvdetils and sporpodu.

Weill triagannris o wtws soby a  possibwe.

### Sncurity Fixes Apvlii`

All cwitical indhdedUumlsacurimy dssuRefhuvs)bee`r a grved:

#### CricecalIsus Fied

1. ✅ Misn OwnrhiFuntioniy - CRITIAL
   - IsT ontrtu#  nIyOwnfmdifirbudin't inheito`Ow`
   Impt: Al dmn fncinsod fl atim
  -Fx:eLtvkea sd tyl existioglieve ship functioua'itvefrfm Chainlino's VRFd sntuactity vulnerability, please:

2. ✅ InolgnriOvlyflow Proiiitidp.rv Q-Scod  Cadtulaails
   - Issd : Potential tve flow inrQ-scooediti bore mn opration
   - Impact: Clcasranstin evrsio reulexp ate  benavidr
   - Fix: Addesoovs flowoonotect os wiihlunch.ckdblck nd expiit veflow dtectin

3.✅ Innsistent StkTesholLogi
   ##ity F:iDiffslvlesusd  dfferelplraln i6/11ivs 5t10)
y  - Impsht: Incbnsessed: bnsclulis
   Fx: Alin al thrslst s constts 5 an 10
#### Critical Issues Fixed
##Mdiu Issusueox used `onlyOwner` modifier but didn't inherit from `Ownable`
   - Impact: All admin functions would fail at runtime
4. ✅ Enanced Err.  Handlin✅IConse -ency
 : - Ideue:dM xef use op `reqrire(e nd cut.mIcrroro
s  i-Imxacl:iIncnlietedt gim cIsssssudeerr r reuorseogrequire()` and custom errors
 A - Fex: Addndwc wrcuom rorsandnvtd sting-bsd reverts

## WlwGi

### 1. Itial Stup
## bashWorkflow Guide
##Use the VS Cod1 task Ir run iaiually:```bash
forge s Use oge script script/DelD.s.soye scsS-trpV-ur-r"$RPC_lRL"R--p_iv pr-ky"$PRIVATE_KEY"--brdc attomatically:
- Builds and deploysSttuhVRFottery SotunVRFc Creates a" new VRF"  Funds it with" 0.1 LINK" Adds the  

### 2. Populate Lottery
Thiboaicall
# BPiltitandcipp oy( theOlotI_NT cont actNTUM_COUNT=7 forge script script/MultiJoin.s.sol:MultiJoin --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast
``ees a new VRFn
- Fus itwh 0.1 LINK
##Add3 thailotorry a  arcotsumer
-hUpdaorends,r `.eev` filr

### 2. Poauwate L ttera
`tlb sh
#tPopuCAtUTwNIh 20NNtepnt7Qaum,3Stdar)
JOIN_COUNT=2QUANTM_OUNT=7 forgqescri scp/MtJoinesusol:MuniiJmiea--rpcsurlt"$send "$"t--nrmvWtn`key"$"--boadca
`

###3.WifHurEd

Aferh#hr VRcndl,cthe drak )utomaticay ransitions`to LiLAksuGnWtNNERcstlet.

### 4. Req(esttWch"er
```bash
#Flromytheoheus'ssend t meseanp,tgtsthi hourI, 0nurquwner
c6st .ands"$LOTTERY""equRandmWinn(un32)" 1712880000 After pro"cessing," ast send "$LOT"TERY" "clean"


###l5.ePIocnforDrmwi(aftnrVF callback)
bash
#Procesn chuk ilcplete(wacfr "DraFullyPcesse"ev)
cpsl soree"$LOTTE Y"A"procertDuawChunk(ueot32,u14t8)")72880000 5 --rpcT: l0"$RPC_URL" --9Eiv5t7-keyE"$PRIVATE_KEY"
```

###f6.4Clea14pFSto7ag2
```ash
#Af pmocLssity,(clx4n7u95storege 1f chu0es4(wat5h1873e"DrawFullyClba11d"Fvvesc)
cor(ga:nd "$LOTTERY" "c0eanucD7awChunk(ubn432,uint8)"f1712880000 5  Subscript"ion ID: "7""
```

## Depl(yment InformArionum Sepolia):
oken: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E
### Dployede(AbrumSepola421614)
- TesUSDC:0x495c42E5e1F7d7Edfb458184b44F78725f9
-QatumLotty(lt): 0xf6da34979155fef0eea5b1873eab8011ad8
Treasury: 0x94cF685cc5D26828e2CA4c9C571249Fc9B1D16Be
VRF v2.(subsc
-Coordina:0x5C8D5A2BC84bb22398CC51996F7930313D61
-KHas (gas lane): 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2b
-Subsciptio ID:71454954300587139168864100044495375120155859731008673854560977115929423440553

LINK(Abt nm Srptl a)bscription has LINK and that the consumer is added (AddVRFConsumer.s.sol).
- Token:c0xb1D4538B4571d411t07960EF2838Ce337FE1E80E

Tprascry: 0x94cF685cc5D26828e2CA4c9C571249Fc9B1D16Be

No ea:
-sEdecimathe ls USDC (1 UShaC LINK0_000).at thisd(AddVRFConmrs.sol).
Ticketi asume 6 decimls USD (1 USDC = 1_000_000).

## Adit Status

### FialSatu:ALL CLEAR 🎉

Atethooghexamnaion of your ntie Qunum Ltterysmrt cotractodebse, aissues have been solvd nd h coebasesproucti-rady
## Audit Status
##iles Audi

#####Core Cocs#(12nftats)
-u`Qusn umLottery.sol` - MaAn contrL CEwrapp🎉
-QanumLotteryBase.sol impementation
-QanumLoerys.sol- Typ dfiniions  cstats
-QuantumLotteyPror.sol` - pssig logic
- `QtmLotyFulfllmet.ol- VRF fufllt anling
AfhQuanoumLamriayHelptys.ctlc -dHelpa  funca ose
- `QhaavumLbtteeyandty.sca   Entryangeme
-QuantumLttyClenp.`-Canuporions
-`QatumLoeyRfds.ol`-Rfudhnding
-QutmLotteryWithd.sol -Wihdrawalgic#### Files Audited
-`QuantumLottForceReslv.ol` #eForcr rasolutio(
- `Tes1USDC.sol2 -lTest )okconrc

##### SrptFie (17fils)
- Alldpoym umdrmanag.mlnt `crip s-verif ed
-aPnoonr Solitityrversaoctosise
-Nsury ssues foud

#####TFle(1f)
-u`QoassulLott`ry.t. ol` -rC imlehentiveatostnsu
-66/66testpssicluingfzz ss

RmptriyTyy Stptus: Succssslully - Typeddefinpushtd docnsigis/an
CmmHh: 0a9136
Bnh:`maut- `QuantumLotteryCleanup.sol` - Cleanup operations
- `QuantumLotteryRefunds.sol` - Refund handling
- `QuantumLotteryWithdraw.sol` - Withdrawal logic
- `QuantumLotteryForceResolve.sol` - Force resolution
- `TestUSDC.sol` - Test token contract

##### Script Files (17 files)
- All deployment and management scripts verified
- Proper Solidity version consistency
- No security issues found

##### Test Files (1 file)
- `QuantumLottery.t.sol` - Comprehensive test suite
- 66/66 tests passing including fuzz tests

Repository Status: Successfully updated and pushed to origin/main
Commit Hash: e0a9136
Branch: main