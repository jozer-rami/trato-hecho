const { SecretsManager, SubscriptionManager } = require("@chainlink/functions-toolkit");

/**
 * DEV TODOS
 * 1. make sure your metamask is connected to Sepolia Sepolia
 * 2. Have sufficient ETH on Sepolia
 * 3. update Constants below if you're using another network.
 */

const functionsRouterAddress = "0xb83E47C2bC239B3bf370bc41e1459A34b41238D0"; // Sepolia
const donId = "fun-ethereum-sepolia-1"; // Sepolia
const linkTokenAddress = "0x779877A7B0D9E8603169DdbD7836e478b4624789" // Sepolia
const LINK_AMOUNT = "0.000001"

const GATEWAY_URLS = ["https://01.functions-gateway.testnet.chain.link/", "https://02.functions-gateway.testnet.chain.link/"] // Sepolia

let provider, signer

// initialize
async function init() {
    provider = new ethers.providers.Web3Provider(window.ethereum);
    signer = provider.getSigner();

    // Switch to Sepolia
    await provider.send("wallet_switchEthereumChain", [{ chainId: '0xaa36a7' }]); // Sepolia Chain ID in hex
    n = await signer.provider.getNetwork();
    console.log("NETWORK IS:  ", n)


    if (!provider || !signer) {
        throw Error("MISSING PROVIDER OR SIGNER")
    } else {
        console.info("Connection initialized")
    }
}


const encryptAndUploadSecrets = async () => {
    const secretsManager = new SecretsManager({
        signer: signer,
        functionsRouterAddress: functionsRouterAddress,
        donId: donId,
    });
    await secretsManager.initialize();

    const SLOT_ID = 0;
    const expirationTimeMinutes = 1440;

    // Encrypt secrets
    const secrets = { apikey: "9c6cb5e9-7a09-4a87-bd0d-3b6a129e67b7" };
    const encryptedSecretsObj = await secretsManager.encryptSecrets(secrets);

    console.log(
        `Upload encrypted secret to gateways ${GATEWAY_URLS}. slotId ${SLOT_ID}. Expiration in minutes: ${expirationTimeMinutes}`
    );

    // Upload secrets
    const uploadResult = await secretsManager.uploadEncryptedSecretsToDON({
        encryptedSecretsHexstring: encryptedSecretsObj.encryptedSecrets,
        gatewayUrls: GATEWAY_URLS,
        slotId: SLOT_ID,
        minutesUntilExpiration: expirationTimeMinutes,
    });

    if (!uploadResult.success) throw new Error(`Encrypted secrets not uploaded to ${GATEWAY_URLS}`);

    console.log(`\n✅ Secrets uploaded properly to gateways ${GATEWAY_URLS}! Gateways response: `, uploadResult);

    const donHostedSecretsVersion = parseInt(uploadResult.version); // fetch the reference of the encrypted secrets

    console.log(`donHostedSecretsVersion is ${donHostedSecretsVersion}`);
}



const createAndFundSub = async (consumerAddress = undefined) => {
    const subscriptionManager = new SubscriptionManager({
        signer,
        linkTokenAddress,
        functionsRouterAddress,
    });

    await subscriptionManager.initialize();

    // Create Subscription
    const subscriptionId = await subscriptionManager.createSubscription();
    console.log(`\nSubscription ${subscriptionId} created.`);

    // add consumer to subscription
    let addConsumerReceipt
    if (consumerAddress) {
        const addConsumerReceipt = await subscriptionManager.addConsumer({
            subscriptionId,
            consumerAddress,
        })
        console.log(
            `\nSubscription ${subscriptionId} now has ${consumerAddress} as a consumer. Tx Receipt: ${addConsumerReceipt})`
        );
    }


    // Fund Subscription
    const juelsAmount = ethers.utils.parseUnits(LINK_AMOUNT, 18).toString();
    console.log(`Funding Subscription ${subscriptionId} with ${juelsAmount} juels`)

    await subscriptionManager.fundSubscription({
        subscriptionId,
        juelsAmount,
    });

    console.log(
        `\nSubscription ${subscriptionId} funded with ${LINK_AMOUNT} LINK. Done.`
    );
};

async function main() {
    await init()
    await encryptAndUploadSecrets()
    //   await createAndFundSub()

}

main().catch((e) => { console.log("ERROR:   ", e) })