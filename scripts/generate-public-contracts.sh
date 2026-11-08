#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROTOC_BIN="${PROTOC_PATH:-$(command -v protoc || true)}"
if [[ -z "$PROTOC_BIN" ]]; then
  echo "protoc is required to regenerate the checked-in public contract bindings" >&2
  exit 1
fi

SWIFT_PLUGIN="${SWIFT_PROTOBUF_PLUGIN:-$ROOT/.build/checkouts/swift-protobuf/.build/out/Products/Debug/protoc-gen-swift}"
GRPC_PLUGIN="${GRPC_SWIFT_PLUGIN:-$ROOT/.build/checkouts/grpc-swift/.build/out/Products/Debug/protoc-gen-grpc-swift}"
if [[ ! -x "$SWIFT_PLUGIN" || ! -x "$GRPC_PLUGIN" ]]; then
  swift package resolve
  swift build --package-path "$ROOT/.build/checkouts/swift-protobuf" --product protoc-gen-swift
  swift build --package-path "$ROOT/.build/checkouts/grpc-swift" --product protoc-gen-grpc-swift
fi

rm -f Sources/ShoparProtocol/shopar_*_entities.pb.swift
"$PROTOC_BIN" -I PublicContracts \
  --plugin="protoc-gen-swift=$SWIFT_PLUGIN" \
  --swift_opt=Visibility=Public,FileNaming=PathToUnderscores \
  --swift_out=Sources/ShoparProtocol \
  PublicContracts/shopar/common/v1/entities.proto \
  PublicContracts/shopar/creator/v1/entities.proto \
  PublicContracts/shopar/discovery/v1/entities.proto

rm -rf Sources/ShoparProtocol/shopar
"$PROTOC_BIN" -I PublicContracts \
  --plugin="protoc-gen-grpc-swift=$GRPC_PLUGIN" \
  --grpc-swift_opt=Visibility=Public,Client=true,Server=false \
  --grpc-swift_out=Sources/ShoparProtocol \
  PublicContracts/shopar/creator/v1/service.proto \
  PublicContracts/shopar/discovery/v1/service.proto

mv Sources/ShoparProtocol/shopar/creator/v1/service.grpc.swift Sources/ShoparProtocol/ShoparCreatorService.grpc.swift
mv Sources/ShoparProtocol/shopar/discovery/v1/service.grpc.swift Sources/ShoparProtocol/ShoparDiscoveryService.grpc.swift
rm -rf Sources/ShoparProtocol/shopar
shasum -a 256 PublicContracts/shopar/common/v1/entities.proto PublicContracts/shopar/creator/v1/entities.proto PublicContracts/shopar/creator/v1/service.proto PublicContracts/shopar/discovery/v1/entities.proto PublicContracts/shopar/discovery/v1/service.proto > PublicContracts/SCHEMA_SHA256SUMS
