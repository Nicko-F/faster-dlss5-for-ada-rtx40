# Distribution status

[中文](distribution.zh-CN.md)

This source preview contains original management and analysis tools, documentation,
aggregate measurements and compatibility identities. The source archive uses an
explicit file allowlist, not a copy of the private research repository.

It excludes extracted NVIDIA PTX/SASS, GPU binaries derived from that code,
runtime DLLs, weights, tensors, game resources, third-party plugin binaries and
proprietary SDK headers. No private git history is imported.

The local complete accelerator remains outside this source tree. Removing PTX/SASS
text while shipping the same code as a cubin does not itself establish permission
to distribute it. NVIDIA's SDK terms distinguish modification of sample source
from other SDK modification and impose restrictions on reverse engineering and
redistribution. See the [NVIDIA SDK license](https://github.com/NVIDIA/DLSS/blob/main/LICENSE.txt).

We have not established permission covering the current modified GPU payloads.
This is a concrete unresolved distribution basis, not a claim that all reverse
engineering, interoperability analysis or independently written tools are unlawful.
Local-only packaging also does not grant third-party rights or resolve every
possible license issue. Do not upload the local complete archive as a public asset.

A public ready-to-use accelerator needs either permission covering the current
payload or independently distributable implementations with renewed validation.
User-local transformation tools would need a separate source and permission review;
moving compilation onto a user's machine is not automatically a legal solution.

## Publication checklist

- [x] Fresh source tree; no vendor code or private history in the allowlist.
- [x] Exact base, measured scope and source data identified.
- [x] Complete local package distinguished from public source preview.
- [ ] GPU acceleration payload distribution basis established.
- [x] Private review repository created with Issues / Discussions for invited collaborators.
- [ ] Public repository publication authorized again after private review.
- [ ] Release archive and hash published with accurate source-preview status.
- [ ] Public ready-to-use acceleration asset available.

The repository is currently a private review draft, at the owner's request. A later public source-only
release must retain the missing-payload notice until an accelerator is available.
