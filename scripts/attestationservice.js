const axios = require("axios");

const AttestationStatus = {
  COMPLETE: "complete",
  PENDING_CONFIRMATIONS: "pending_confirmations",
};

const mapAttestation = (attestationResponse) => ({
  message: attestationResponse.attestation,
  status: attestationResponse.status,
});

const baseURL = "https://iris-api-sandbox.circle.com/v2/messages/";
const axiosInstance = axios.create({ baseURL });

const getAttestation = async (sourceDomainId, transactionHash) => {
  console.log("Retrieving attestation...");
  const url = `https://iris-api-sandbox.circle.com/v2/messages/${sourceDomainId}?transactionHash=${transactionHash}`;
  try {
    const response = await axios.get(url);
    console.log("response:", response);
    if (response.status === 404) {
      console.log("Waiting for attestation...");
    }else if(response.data?.messages?.[0]?.status === "complete") {
      console.log("Attestation retrieved successfully!", response.data.messages[0]);
      return response.data.messages[0];
    }else if(response.data?.messages?.[0].status === "PENDING"){
      console.log("Pending");
    }
    await new Promise((resolve) => setTimeout(resolve, 60000));
  } catch (error) {
    console.error("Error fetching attestation:", error.message);
    await new Promise((resolve) => setTimeout(resolve, 60000));
  }
};

module.exports = { getAttestation };
