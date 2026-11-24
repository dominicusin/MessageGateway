# MessageGateway

Universal message bridge on Haskell.

**Status: early skeleton (Phase 0).** The repository currently contains a cabal project and a small `src/` module skeleton; no production transport is implemented yet.

## Scope (planned)

- FTN / NNTP / email routing bridge as part of the S5 messaging system.
- Integration point for FidoGate and PolyResolver.
- Transport adapters added one at a time, with tests.

## Development

```sh
cabal build all
cabal test all
```

## License

MPL-2.0 — see [LICENSE](LICENSE).
