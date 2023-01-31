# sever
SElf VERification to combat and sever Sybil network connections

# Contract implementation

An ERC721 contract with address-bound ownership (one token per address, forever). Tokens are burnable.

Deployment: https://mumbai.polygonscan.com/address/0x506F4EcC9F9916d2dB93B56a79E1F760d70A6bED#writeProxyContract

Primary functions

- `safeMint` to create a non-scored sevel badge. 
- `request` to request scores for one or an array of models.
- `report` for model scoring reporters to send back an array of results for one target address.
- `batchReport` for model scoring reporters to send back a batch of results for many addresses.
- `tokenURI` request all score results attached to a token owned by an address. 
- `tokenOfOwnerByIndex` get the tokenId of the owner by querying index 0. 
- `addLego` adds a new scoring model to the model index.

# Data store

Legos: 

- All data for available model legos are stored in the the `sever_legos_80001_5500` table. 
- https://testnets.opensea.io/assets/mumbai/0x4b48841d4b32c4650e4abc117a03fe8b51f38f68/5500

Scores:

- All address x model-score pair is stored in a row in the `sever_scores_80001_5499` table.
- https://testnets.opensea.io/assets/mumbai/0x4b48841d4b32c4650e4abc117a03fe8b51f38f68/5499

Both tables are owned by the implementation contract and cannot be modified except through calling one of the methods above. 

# Sever NFT badge

The NFT is served from the `tokenURI` method and available on opensea and other NFT platforms. The NFT currently shows just two forms (visually), the unscored and scored addresses. However, all score values are available directly in the NFT metadata or by querying the tables above. 

- Sever Collection https://testnets.opensea.io/collection/severbadge-v3
- Unscored example https://testnets.opensea.io/assets/mumbai/0x506f4ecc9f9916d2db93b56a79e1f760d70a6bed/1
- Scored example https://testnets.opensea.io/assets/mumbai/0x506f4ecc9f9916d2db93b56a79e1f760d70a6bed/0

You can view the metadata of the Scored example here https://testnets.tableland.network/query?extract=true&unwrap=true&s=SELECT%20json_object%28%27name%27%2C%20%27SEVER%200%27%2C%20%27external_url%27%2C%20%27pending%27%2C%20%27image%27%2C%20%27ipfs%3A%2F%2Fbafybeiajfx3r67elxmkwxg4o3f4zv2gb4mi4bfw6ljywfoml5y3qafa2qa%2F1.png%27%2C%20%27attributes%27%2C%28SELECT%20json_group_array%28json_object%28%27trait_type%27%2C%20%27LEGO_%27%7C%7Cmodel_id%2C%20%27value%27%2C%20score%29%29%20FROM%20sever_scores_80001_5499%20where%20address%3D%270x82da49fdb997e058c4a8e5ee63b4a336689ca394%27%20GROUP%20BY%20address%29%29%20FROM%20sever_legos_80001_5500%20LIMIT%201 

# Closed contract methods

The contract above is deployed using Role based access control and then configured using OpenZepplin Defender. The `addLego` and `report` methods (including bulk) are not available to the public and must be permissioned to address, multisig, or governance contract. The project creators are currently permissioned to use these functions, but they can be upgraded to allow for exciting future directions:

- Scope lego addition to a governace contract or DAO where only legos can be submitted but will be vetted and voted on before inclusion in the index.
- Scope scoring & reporting to a set of oracles or a DAO where they can be managed and quality controlled in an open process. 
