# SID Name Wrapper

The SID Name Wrapper is a smart contract that wraps existing SID names, providing several new features:

- Wrapped names are ERC1155 tokens
- Better permission control over wrapped names
- Consistent API for names at any level of the hierarchy

In addition to implementing ERC1155, wrapped names have an ERC721-compatible `ownerOf` function to return the owner of a wrapped name.

Making SID names ERC1155 compatible allows them to be displayed, transferred and traded in any wallet that supports the standard.

`NameWrapper` implements the optional ERC1155 metadata extension; presently this is via an HTTPS URL to a service SID operates, but this can be changed in future as better options become available.

With the exception of the functionality to upgrade the metadata generation for tokens, there is no upgrade mechanism or centralised control over wrapped names.

## Wrapping a name

`.bnb` 2LDs (second-level domains) such as `example.bnb` can be wrapped by calling `wrapBNB2LD(label, wrappedOwner, fuses, resolver)`. `label` is the first part of the domain name (eg, `'example'` for `example.bnb`), `wrappedOwner` is the desired owner for the wrapped name, and `fuses` is a bitfield representing permissions over the name that should be irrevoacably burned (see 'Fuses' below). A `fuses` value of `0` represents no restrictions on the name. The resolver can also optionally be set here and would need to be a _wrapper aware_ resolver that uses the NameWrapper ownership over the Registry ownership.

In order to wrap a `.bnb` 2LD, the owner of the name must have authorised the wrapper by calling `setApprovalForAll` on the registrar, and the caller of `wrapBNB2LD` must be either the owner, or authorised by the owner on either the wrapper or the registrar.

All other domains (non `.bnb` names as well as `.bnb` subdomains such as `sub.example.bnb` can be wrapped by calling `wrap(parentNode, label, wrappedOwner, fuses)`. `parentNode` is the namehash of the name one level higher than the name to be wrapped, `label` is the first part of the name, `wrappedOwner` is the address that should own the wrapped name, and `fuses` is a bitfield representing permissions over the name that should be irrevocably burned (see 'Fuses' below). A `fuses` value of `0` represents no restrictions on the name. For example, to wrap `sub.example.bnb`, you should call `wrap(namehash('example.bnb'), 'example', owner, fuses)`.

In order to wrap a domain that is not a `.bnb` 2LD, the owner of the name must have authorised the wrapper by calling `setApprovalForAll` on the registry, and the caller of `wrap` must be either the owner, or authorised by the owner on either the wrapper or the registry.

## Wrapping a name by sending the `.bnb` token

An alternative way to wrap `.bnb` names is to send the name to the NameWrapper contract, this bypasses the need to `setApprovalForAll` on the registrar and is preferable when only wrapping one name.

To wrap a name by sending to the contract, you must use `safeTransferFrom(address,address,uint256,bytes)` with the extra data (the last parameter) ABI formatted as `[string label, address owner, uint96 fuses, address resolver]`.

Example:

```js
// Using ethers.js v5
abiCoder.encode(
  ['string', 'address', 'uint96', 'address'],
  ['vitalik', '0x...', '0x000000000000000000000001', '0x...']
)
```

## Unwrapping a name

Wrapped names can be unwrapped by calling either `unwrapBNB2LD(label, newRegistrant, newController)` or `unwrap(parentNode, label, newController)` as appropriate. `label` and `parentNode` have meanings as described under "Wrapping a name", while `newRegistrant` is the address that should own the .bnb registrar token, and `newController` is the address that should be set as the owner of the ENS registry record.

## Working with wrapped names

The wrapper exposes all the registry functionality via its own methods - `setSubnodeOwner`, `setSubnodeRecord`, `setRecord`, `setResolver` and `setTTL` are all implemented with the same functionality as the registry, and pass through to it after doing authorisation checks. Transfers are handled via ERC1155's transfer methods rather than mirroring the registry's `setOwner` method.

In addition, `setSubnodeOwnerAndWrap` and `setSubnodeRecordAndWrap` methods are provided, which create or replace subdomains while automatically wrapping the resulting subdomain.

All functions for working with wrapped names utilise ERC1155's authorisation mechanism, meaning an account that is authorised to act on behalf of another account can manage all its names.

## Fuses

`NameWrapper` also implements a permissions mechanism called 'fuses'. Each name has a set of fuses representing permissions over that name. Fuses can be 'burned' either at the time the name is wrapped or at any subsequent time when the owner or authorised operator calls `burnFuses`. Once a fuse is burned, it cannot be 'unburned' - the permission that fuse represents is permanently revoked.

Before any fuses can be burned on a name, the parent name's "replace subdomain" fuse must first be burned. Without this restriction, any permissions revoked via fuses can be evaded by the parent name replacing the subdomain and then re-wrapping it with a more permissive fuse field. Likewise, when any fuses on a name are burned, the "unwrap" fuse must also be burned, to prevent the name being directly unwrapped and re-wrapped to reset the fuses. These restrictions have the effect of allowing applications to simply check the fuse value they care about on the name they are examining without having to be aware of the entire chain of custody up to the root.

The SID root and the .bnb 2LD are treated as having the "replace subdomain" and "unwrap" fuses burned. There is one edge-case here insofar as a .bnb name's registration can expire; at that point the name can be purchased by a new registrant and effectively becomes unwrapped despite any fuse restrictions. When that name is re-wrapped, fuse fields can be set to a more permissive value than the name previously had. Any application relying on fuse values for .bnb subdomains should check the expiration date of the .bnb name and warn users if this is likely to expire soon.

The fuses field is 96 bits, and only 7 fuses are defined by the `NameWrapper` contract itself. Applications may use additional fuse bits to encode their own restrictions on applications. Any application wishing to do so should submit a PR to this README in order to record the use of the value and ensure there is no unintentional overlap.

Each fuse is represented by a single bit. If that bit is cleared (0) the restriction is not applied, and if it is set (1) the restriction is applied. Any updates to the fuse field for a name are treated as a logical-OR; as a result bits can only be set, never cleared.

### CANNOT_UNWRAP = 1

If this fuse is burned, the name cannot be unwrapped, and calls to `unwrap` and `unwrapBNB2LD` will fail.

### CANNOT_BURN_FUSES = 2

If this fuse is burned, no further fuses can be burned. This has the effect of 'locking open' some set of permissions on the name. Calls to `burnFuses` will fail.

### CANNOT_TRANSFER = 4

If this fuse is burned, the name cannot be transferred. Calls to `safeTransferFrom` and `safeBatchTransferFrom` will fail.

### CANNOT_SET_RESOLVER = 8

If this fuse is burned, the resolver cannot be changed. Calls to `setResolver` and `setRecord` will fail.

### CANNOT_SET_TTL = 16

If this fuse is burned, the TTL cannot be changed. Calls to `setTTL` and `setRecord` will fail.

### CANNOT_CREATE_SUBDOMAIN = 32

If this fuse is burned, new subdomains cannot be created. Calls to `setSubnodeOwner`, `setSubnodeRecord`, `setSubnodeOwnerAndWrap` and `setSubnodeRecordAndWrap` will fail if they reference a name that does not already exist.

### CANNOT_REPLACE_SUBDOMAIN = 64

If this fuse is burned, existing subdomains cannot be replaced by the parent name. Calls to `setSubnodeOwner`, `setSubnodeRecord`, `setSubnodeOwnerAndWrap` and `setSubnodeRecordAndWrap` will fail if they reference a name that already exists.

### Checking Fuses using `allFusesBurned(node, uint96)`

To check whether or not a fuse is burnt you can use this function that takes a fuse mask of all fuses you want to check.

```js
const areBurned = await allFusesBurned(
  namehash('vitalik.bnb'),
  CANNOT_TRANSFER | CANNOT_SET_RESOLVER
)
// if CANNOT_UNWRAP AND CANNOT_SET_RESOLVER are *both* burned this will return true
```

### Get current fuses and parent safety using `getFuses(node)`

Get fuses gets the raw fuses for a current node and also checks the parent hierarchy for you. The raw fuses it returns will be a `uint96` and you will have to decode this yourself. If you just need to check a fuse has been burned, you can call `allFusesBurned` as it will use less gas.

The parent hierarchy check will start from the root and check 4 things:

1. Is the registrant of the name the wrapper?
2. Is the controller of the name the wrapper?
3. Are the fuses burnt for replacing a subdomain?
4. Is the name expired?

This is represented by `enum NameSafety {Safe, Registrant, Controller, Fuses, Expired}`

Lastly it will return to you the first node up the hierarchy that is vulnerable. After it finds a vulnerable node, it will break from checking and so it needs to be rechecked for children down the hierarchy once the vulnerable node has been made safe.

## Installation and setup

```bash
npm install
```

## Testing

```bash
npm run test
```

Any contract with `2` at the end, is referring to the contract being called by `account2`, rather than `account1`. This is for tests that require authorising another user.

## Deploying test contracts into Rinkeby

### Create .env

```
cp .env.org .env
```

### Set credentials

```
PRIVATE_KEY=
ETHERSCAN_API_KEY=
INFURA_API_KEY=
```

Please leave the following fields as blank

```
SEED_NAME=
METADATA_ADDRESS=
WRAPPER_ADDRESS=
RESOLVER_ADDRESS=
```

### Run deploy script

`yarn deploy:rinkeby` will deploy to rinkeby and verify its source code

NOTE: If you want to override the default metadata url, set `METADATA_HOST=` to `.env`

```
$yarn deploy:rinkeby
yarn run v1.22.10
$ npx hardhat run --network rinkeby scripts/deploy.js
Deploying contracts to rinkeby with the account:0x97bA55F61345665cF08c4233b9D6E61051A43B18
Account balance: 1934772596667918724 true
{
  registryAddress: '0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e',
  registrarAddress: '0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85'
}
Setting metadata service to https://ens-metadata-service.appspot.com/name/0x{id}
Metadata address: 0x08f2D8D8240fC70FD777358b0c63e539714DD473
Wrapper address: 0x88ce50eFeA21996B20838d5E71994191562758f9
Resolver address: 0x784b7B9BA0Fc04b90187c06C0C7efC51AeA06aFB
wait for 5 sec until bytecodes are uploaded into bscscan
verify  0x08f2D8D8240fC70FD777358b0c63e539714DD473 with arguments https://ens-metadata-service.appspot.com/name/0x{id}
verify  0x88ce50eFeA21996B20838d5E71994191562758f9 with arguments 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e,0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85,0x08f2D8D8240fC70FD777358b0c63e539714DD473
verify  0x784b7B9BA0Fc04b90187c06C0C7efC51AeA06aFB with arguments 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e,0x88ce50eFeA21996B20838d5E71994191562758f9
```

After running the script it sets addresses to `.env`. If you want to redeploy some of contracts, remove the contract address from `.env` and runs the script again.

## Seeding test data into Rinkeby

1. Register a name using the account you used to deploy the contract
2. Set the label (`matoken` for `matoken.bnb`) to `SEED_NAME=` on `.env`
3. Run `yarn seed:rinkeby`

```
~/.../ens/name-wrapper (seed)$yarn seed:rinkeby
yarn run v1.22.10
$ npx hardhat run --network rinkeby scripts/seed.js
Account balance: 1925134991223891632
{
  registryAddress: '0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e',
  registrarAddress: '0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85',
  wrapperAddress: '0x88ce50eFeA21996B20838d5E71994191562758f9',
  resolverAddress: '0x784b7B9BA0Fc04b90187c06C0C7efC51AeA06aFB',
  firstAddress: '0x97bA55F61345665cF08c4233b9D6E61051A43B18',
  name: 'wrappertest4'
}
Wrapped NFT for wrappertest4.bnb is available at https://testnets.opensea.io/assets/0x88ce50eFeA21996B20838d5E71994191562758f9/42538507198368349158588132934279877358592939677496199760991827793914037599925
Wrapped NFT for sub2.wrappertest4.bnb is available at https://testnets.opensea.io/assets/0x88ce50eFeA21996B20838d5E71994191562758f9/22588238952906792220944282072078294622689934598844133294480594786812258911617
```