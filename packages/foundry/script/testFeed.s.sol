// import {Script} from "forge-std/Script.sol";
// import "@chainlink/contracts/script/feeds/DataFeed.s.sol";

// contract TestFeed is Script {
//   constructor() public {
//     // Initialize a contract
//   }

//   function getLatestPrice(address dataFeedAddress) public returns (int256 latestPrice){
//     DataFeedsScript automationScript = new DataFeedsScript(dataFeedAddress);

//     vm.broadcast();
//     (,latestPrice,,,) = DataFeedsScript.getLatestRoundData();
//     return latestPrice;
//   }
// }