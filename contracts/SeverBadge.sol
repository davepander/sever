// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Base64Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@tableland/evm/contracts/ITablelandTables.sol";
import "@tableland/evm/contracts/utils/TablelandDeployments.sol";
import "@tableland/evm/contracts/utils/URITemplate.sol";

struct Info {
    uint256 tokenId;
    uint256 score; 
    bool scored; 
}
struct StoredData {
    uint256 scoreTableId;
    string scoreTableName;
    uint256 legoTableId;
    string legoTableName;
    ITablelandTables _tableland;
    mapping(address => Info) badges;
}

contract SeverBadge is
    Initializable, 
    ERC721Upgradeable, 
    ERC721EnumerableUpgradeable, 
    ERC721HolderUpgradeable,
    ERC721URIStorageUpgradeable, 
    ERC721BurnableUpgradeable, 
    AccessControlUpgradeable, 
    UUPSUpgradeable
{
    // An instance of the struct defined above.
    StoredData internal stored;
    string private _baseURIString;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _tokenIdCounter;
    CountersUpgradeable.Counter private _modelIdCounter;

    /*
     * The below roles could be turned over to a DAO for governance.
     * They are currently managed through OpenZepplin defender. 
     */
    // Only addresses allowed to publish new legos
    bytes32 public constant LEGO_PUB_ROLE = keccak256("LEGO_PUB_ROLE");
    // Only addresses allowed to report requester scores
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    // Only addresses allowed to upgrade the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    event MetadataUpdate(uint256 _tokenId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC721_init("SeverBadge", "SvB");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LEGO_PUB_ROLE, msg.sender);
        _grantRole(REPORTER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    /**
     * @dev Called when the smart contract is deployed. This function will create a table
     * on the Tableland network that will contain a new row for every new project minted
     * by a user of this smart contract.
     */
    function _init() external onlyRole(UPGRADER_ROLE) {
        stored._tableland = TablelandDeployments.get();
        // The create statement sent to Tableland.
        stored.scoreTableId = stored._tableland.createTable(
            address(this),
            string.concat(
                "CREATE TABLE sever_scores_",
                StringsUpgradeable.toString(block.chainid),
                " (",
                " id TEXT PRIMARY KEY,",
                " address TEXT,", // address being scored
                " model_id INTEGER,", // associated w/ model table
                " score INTEGER,", // latest score
                " date INTEGER,", // latest score date
                " source TEXT,", // source of score
                " request INTEGER", // date of request, null if not requested
                ");"
            )
        );

        // Store the table name locally for future reference.
        stored.scoreTableName = string.concat(
            "sever_scores_",
            StringsUpgradeable.toString(block.chainid),
            "_",
            StringsUpgradeable.toString(stored.scoreTableId)
        );


        /*
         * We could move the below to a separate contract with governance.
         * Allowing for various mechanics to update or add new legos.
         */
        stored.legoTableId = stored._tableland.createTable(
            address(this),
            string.concat(
                "CREATE TABLE sever_legos_",
                StringsUpgradeable.toString(block.chainid),
                " (",
                " id INTEGER PRIMARY KEY,",
                " name TEXT,",
                " version TEXT,",
                " updated INTEGER,",
                " source TEXT"
                ");"
            )
        );

        // Store the table name locally for future reference.
        stored.legoTableName = string.concat(
            "sever_legos_",
            StringsUpgradeable.toString(block.chainid),
            "_",
            StringsUpgradeable.toString(stored.legoTableId)
        );
    }

    // Create an empty score badge
    function safeMint(address to) public {
        require(balanceOf(to) == 0, "Badge minted already");
        _privateSafeMint(to);
    }

    // ensures an address will only ever mint one badge holder
    function _privateSafeMint(address to) private {
        // Mint new token
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
        _tokenIdCounter.increment();
        stored.badges[to] = Info(tokenId, 0, false);
    }

    function upsert(uint32 model, address to) private view returns (string memory) {
        // string model id
        string memory modelId = StringsUpgradeable.toString(model);
        // string address
        string memory addr = StringsUpgradeable.toHexString(to);
        // id
        string memory id = string.concat(addr, '-', modelId);
        // string date
        string memory date = StringsUpgradeable.toString(block.timestamp);
        return string.concat(
            "INSERT INTO ",
            stored.scoreTableName,
            " (id,address,model_id,request) VALUES ('",
            id,
            "','",
            addr,
            "',",
            modelId,
            ",",
            date,
            ") ON CONFLICT (id) DO UPDATE SET request=",
            date
            ,";"
        );
    }

    /**
    * @dev Called by anyone to refresh the sybil score for an array of models for a given address.
    */
    function request(address to, uint32[] memory models) public {
        string memory ups = "";
        // make sure that no ids in the models array are greater than our model counter
        for (uint i = 0; i < models.length; i++) {
            require(models[i] < _modelIdCounter.current(), "Model ID does not exist");
            // string sql
            ups = string.concat(ups, upsert(models[i], to));
        }
        // makes sure the target address has a badge
        if (balanceOf(to)==0) {
            _privateSafeMint(to);
        } 
        stored._tableland.runSQL(
            address(this),
            stored.scoreTableId,
            ups
        );
    }

    /**
    * @dev request a set of models each for an array of addresses. 
    */
    function bulkRequest(address[] memory tos, uint32[] memory models) public {
        // make sure that no ids in the models array are greater than our model counter
        for (uint i = 0; i < tos.length; i++) {
            request(tos[i], models);
        }
    }

    // An admin function (not yet) that would store new legos w/ a unique id. 
    function addLego(string memory name, string memory version) public onlyRole(LEGO_PUB_ROLE) {
        // new model id
        string memory modelId = StringsUpgradeable.toString(_modelIdCounter.current());
        // string sender address
        string memory source = StringsUpgradeable.toHexString(_msgSender());
        // current date as string
        string memory date = StringsUpgradeable.toString(block.timestamp);

        string memory ups = string.concat(
            "INSERT INTO ",
            stored.legoTableName,
            " (name,version,source,updated,id) VALUES ('",
            name,
            "','",
            version,
            "','",
            source,
            "',",
            date,
            ",",
            modelId,
            ");"
        );
        stored._tableland.runSQL(
            address(this),
            stored.legoTableId,
            ups
        );
        _modelIdCounter.increment();
    }

    // Called by an oracle to store the scores for any single address.
    function report(address target, uint32[] memory models, uint32[] memory scores) public onlyRole(REPORTER_ROLE) {
        // require models length == scores length
        require(models.length > 0, "Must report at least one score");
        require(models.length == scores.length, "Models and scores must be the same length");
        string memory update = "";
        if (stored.badges[target].scored == false) {
            stored.badges[target].scored = true;
            emit MetadataUpdate(stored.badges[target].tokenId);
        }
        
        // make sure that no ids in the models array are greater than our model counter
        for (uint i = 0; i < models.length; i++) {
            require(models[i] < _modelIdCounter.current(), "Model ID does not exist");
            // get primary score key
            string memory id = string.concat(
                StringsUpgradeable.toHexString(target),
                '-',
                StringsUpgradeable.toString(models[i])
            );
            // string score
            string memory score = StringsUpgradeable.toString(scores[i]);
            // string date
            string memory date = StringsUpgradeable.toString(block.timestamp);
            update = string.concat(
                update,
                "UPDATE ",
                stored.scoreTableName,
                " SET score=",
                score,
                ",date=",
                date,
                " WHERE id='",
                id,
                "';"
            );
        }
        stored._tableland.runSQL(
            address(this),
            stored.scoreTableId,
            update
        );
    }

    // bulkReport allows the sender to send an array of addresses and an array of scores for each address.
    function bulkReport(address[] memory targets, uint32[] memory models, uint32[] memory scores) public onlyRole(REPORTER_ROLE) {
        // require models length == scores length
        require(models.length == scores.length, "Models and scores must be the same length");
        // require targets length == scores length
        require(targets.length == scores.length, "Targets and scores must be the same length");
        // make sure that no ids in the models array are greater than our model counter
        for (uint i = 0; i < targets.length; i++) {
            report(targets[i], models, scores);
        }
    }

    // Get the url encoded payload for the requested nft
    function urlEncoded(uint256 tokenId) private view returns (string memory){
        address owner = ownerOf(tokenId);
        string memory addrStr = StringsUpgradeable.toHexString(owner);
        string memory tokenID = StringsUpgradeable.toString(tokenId);
        string memory imageId = "0";
        if (stored.badges[owner].scored == true) {
            imageId = "1";
        }
        string memory trick = "SELECT"; // avoiding cloudflare api filter on polygonscan :(
        return string.concat(
            trick,"%20json_object%28%27name%27%2C%20%27SEVER%20",
            tokenID,"%27%2C%20%27external_url%27%2C%20%27pending%27%2C%20%27image%27%2C%20%27ipfs%3A%2F%2Fbafybeiajfx3r67elxmkwxg4o3f4zv2gb4mi4bfw6ljywfoml5y3qafa2qa%2F",imageId,".png%27%2C%20%27attributes%27%2C%28",trick,"%20json_group_array%28json_object%28%27trait_type%27%2C%20%27LEGO_%27%7C%7Cmodel_id%2C%20%27value%27%2C%20score%29%29%20FROM%20",
            stored.scoreTableName,
            "%20where%20address%3D%27",
            addrStr,
            "%27%20GROUP%20BY%20address%29%29%20FROM%20",
            stored.legoTableName,
            "%20LIMIT%201"
        );
    }

    /**
    * @dev Dynamically generate the metadata payload for any game.
    */
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        _requireMinted(tokenId);
        return string.concat(
            "https://testnets.tableland.network/query?extract=true&unwrap=true&s=",
            urlEncoded(tokenId)
        );
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // bound
    function _beforeTokenTransfer(address from, address to, uint256, uint256) pure internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        require(from == address(0) || to == address(0), "This a Soulbound token. It cannot be transferred. It can only be burned by the token owner.");
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        super._burn(tokenId);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
