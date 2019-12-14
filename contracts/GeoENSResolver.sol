pragma solidity >=0.4.21 <0.6.0;

contract GeoENSResolver {
    // Other code

    bytes4 constant ERC165ID = 0x01ffc9a7;
    bytes4 constant ERC2390 = 0xa263115e;
    uint constant MAX_ADDR_RETURNS = 64;
    uint constant TREE_VISITATION_QUEUESZ = 64;
    //string constant BASE_32_TO_CHARS = "0123456789bcdefghjkmnpqrstuvwxyz";
    //bytes constant CHARS_TO_BASE_32 = hex"30313233343536373839626364656667686A6B6D6E707172737475767778797A";
    uint8 constant ASCII_0 = 48;
    uint8 constant ASCII_9 = 57;
    uint8 constant ASCII_a = 97;
    uint8 constant ASCII_b = 98;
    uint8 constant ASCII_i = 105;
    uint8 constant ASCII_l = 108;
    uint8 constant ASCII_o = 111;
    uint8 constant ASCII_z = 122;

    struct Node {
        address data; // 0 if not leaf
        uint256 parent;
        uint256[] children; // always length 32
    }

    // A geohash is 8, base-32 characters.
    // A geomap is stored as tree of fan-out 32 (because
    // geohash is base 32) and height 8 (because geohash
    // length is 8 characters)
    Node[] geomap;

    address public owner;

    event AddrChanged(bytes32 indexed node, string geohash, address addr);

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor() public {
        owner = msg.sender;
        //geomap.push(Node(address(0), 0, new uint256[](32)));
        geomap.push( Node({
            data: address(0),
            parent: 0,
            children: new uint256[](32)
        }));
    }

    // only 5 bits of ret value are used
    function chartobase32(byte c) pure internal returns (uint8 b) {
        uint8 ascii = uint8(c);
        require( (ascii >= ASCII_0 && ascii <= ASCII_9) ||
                (ascii > ASCII_a && ascii <= ASCII_z));
        require(ascii != ASCII_a);
        require(ascii != ASCII_i);
        require(ascii != ASCII_l);
        require(ascii != ASCII_o);

        if (ascii <= (ASCII_0 + 9)) {
            b = ascii - ASCII_0;

        } else {
            // base32 b = 10
            // ascii 'b' = 0x60
            // note base32 skips the letter 'a'
            b = ascii - ASCII_b + 10;

            // base32 also skips the following letters
            if (ascii > ASCII_i)
                b --;
            if (ascii > ASCII_l)
                b --;
            if (ascii > ASCII_o)
                b --;
        }
        require(b < 32); // base 32 cant be larger than 32
        return b;
    }

    function geoAddr(bytes32 node, string calldata geohash) external view returns (address[] memory ret) {
        bytes32(node); // single node georesolver ignores node
        require(bytes(geohash).length < 9); // 8 characters = +-1.9 meter resolution

        ret = new address[](MAX_ADDR_RETURNS);
        uint ret_i = 0;

        // walk into the geomap data structure
        uint pointer = 0; // not actual pointer but index into geomap
        for(uint i=0; i < bytes(geohash).length; i++) {

            uint8 c = chartobase32(bytes(geohash)[i]);
            uint next = geomap[pointer].children[c];
            if (next == 0) {
                // nothing found for this geohash.
                // return early.
                return ret;
            } else {
                pointer = next;
            }
        }

        // pointer is now node representing the resolution of the query geohash.
        // DFS until all addresses found or ret[] is full.
        // Do not use recursion because this is a blockchain...
        uint[] memory indexes_to_visit = new uint[](TREE_VISITATION_QUEUESZ);
        indexes_to_visit[0] = pointer;
        uint front_i = 0;
        uint back_i = 1;

        while(front_i != back_i) {
            Node memory cur_node = geomap[indexes_to_visit[front_i]];
            front_i ++;

            // if not a leaf node...
            if (cur_node.data == address(0)) {
                // visit all the chilin's
                for(uint i=0; i<cur_node.children.length; i++) {
                    // only visit valid children
                    if (cur_node.children[i] != 0) {
                        assert(back_i < TREE_VISITATION_QUEUESZ);
                        indexes_to_visit[back_i] = cur_node.children[i];
                        back_i ++;

                    }
                }
            } else {
                ret[ret_i] = cur_node.data;
                ret_i ++;
                if (ret_i > MAX_ADDR_RETURNS) break;
            }
        }

        return ret;
    }

    // when setting, geohash must be precise to 8 digits.
    function setGeoAddr(bytes32 node, string calldata geohash, address addr) external isOwner() {
        bytes32(node); // single node georesolver ignores node
        require(bytes(geohash).length == 8); // 8 characters = +-1.9 meter resolution

        // walk into the geomap data structure
        uint pointer = 0; // not actual pointer but index into geomap
        for(uint i=0; i < bytes(geohash).length; i++) {

            uint8 c = chartobase32(bytes(geohash)[i]);

            if (geomap[pointer].children[c] == 0) {
                // nothing found for this geohash.
                // we need to create a path to the leaf
                geomap.push( Node({
                    data: address(0),
                    parent: pointer,
                    children: new uint256[](32)
                }));
                geomap[pointer].children[c] = geomap.length - 1;
            }
            pointer = geomap[pointer].children[c];
        }

        Node storage cur_node = geomap[pointer]; // storage = get reference
        cur_node.data = addr;

        emit AddrChanged(node, geohash, addr);
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == ERC165ID || interfaceID == ERC2390;
    }

    function() external payable {
        revert();
    }
}
