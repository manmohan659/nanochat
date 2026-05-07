## [1.1.6](https://github.com/manmohan659/nanochat/compare/v1.1.5...v1.1.6) (2026-05-07)


### Bug Fixes

* **inference:** proxy generation when local model is unavailable ([981ba3b](https://github.com/manmohan659/nanochat/commit/981ba3b671b8dd3234bfe43d6c2222a42d02e44a))

## [1.1.4](https://github.com/manmohan659/nanochat/compare/v1.1.3...v1.1.4) (2026-05-07)


### Bug Fixes

* **auth:** link OAuth users by verified email ([857a140](https://github.com/manmohan659/nanochat/commit/857a14099b753c9ff70df41923c9bab3147432db))
* **auth:** link OAuth users by verified email ([b438a55](https://github.com/manmohan659/nanochat/commit/b438a55a455f8e031a2788dacd9ac5122a071c3d))

## [1.1.2](https://github.com/manmohan659/nanochat/compare/v1.1.1...v1.1.2) (2026-05-07)


### Bug Fixes

* **devops:** route slotted services and bind user logs ([023997f](https://github.com/manmohan659/nanochat/commit/023997f48684d96d0c60666b20a7ca8e10b94c5a))

# [1.1.0](https://github.com/manmohan659/nanochat/compare/v1.0.5...v1.1.0) (2026-05-07)


### Features

* **observability:** propagate session trace context ([7dac66d](https://github.com/manmohan659/nanochat/commit/7dac66d2e8919f14584980decae6eae7d07c90d3))

## [1.0.5](https://github.com/manmohan659/nanochat/compare/v1.0.4...v1.0.5) (2026-05-06)


### Bug Fixes

* **devops:** unblock ALB and prod release flow ([e4eeb7e](https://github.com/manmohan659/nanochat/commit/e4eeb7e72e0225d85186b7e37d48510a2970caf0))

## [1.0.4](https://github.com/manmohan659/nanochat/compare/v1.0.3...v1.0.4) (2026-05-06)


### Bug Fixes

* **ci:** use batch get for image promotion ([#76](https://github.com/manmohan659/nanochat/issues/76)) ([b7e0b99](https://github.com/manmohan659/nanochat/commit/b7e0b99ddf73a975c34e2f61f4e5c02dfa1d4874))

## [1.0.3](https://github.com/manmohan659/nanochat/compare/v1.0.2...v1.0.3) (2026-05-06)


### Bug Fixes

* **ci:** wait for promoted source images ([#75](https://github.com/manmohan659/nanochat/issues/75)) ([e4136b9](https://github.com/manmohan659/nanochat/commit/e4136b9e55c0d7d8106d1fd34f67c4de1459c76f))

## [1.0.2](https://github.com/manmohan659/nanochat/compare/v1.0.1...v1.0.2) (2026-05-06)


### Bug Fixes

* **ci:** make promotions rerunnable ([#74](https://github.com/manmohan659/nanochat/issues/74)) ([38032fe](https://github.com/manmohan659/nanochat/commit/38032fee37e01a658f632875a7cd13012d92058d))

## [1.0.1](https://github.com/manmohan659/nanochat/compare/v1.0.0...v1.0.1) (2026-05-06)


### Bug Fixes

* **eks:** stabilize live helm ingress rollout ([43a366c](https://github.com/manmohan659/nanochat/commit/43a366ce4f1bec2c3f06fa05d4840b7814083371))

# 1.0.0 (2026-05-06)


### Bug Fixes

* add missing models/ dirs to auth and chat-api services ([8a95a76](https://github.com/manmohan659/nanochat/commit/8a95a765228c1042fbe773e42006e585d7832c02))
* align conversation list response shape with chat-api ([4369826](https://github.com/manmohan659/nanochat/commit/4369826043909fa228ee3c2f33e54b9851f92544))
* auto-inject calculator tool call on arithmetic in user message ([bd37163](https://github.com/manmohan659/nanochat/commit/bd37163138ea328b27d4340777bc9853160a16c3))
* cast bf16 to fp32 on MPS (like CPU) to avoid dtype issues ([7a40ee7](https://github.com/manmohan659/nanochat/commit/7a40ee77b4695ccb7350a679230eb6a7f8a6ae29))
* **chat-api:** detect Modal URL by domain not path suffix ([df0584b](https://github.com/manmohan659/nanochat/commit/df0584b86147b09b5114e4259c8e74890cb9f65e))
* **chat-api:** support Modal inference URL in inference client ([6d3e1f0](https://github.com/manmohan659/nanochat/commit/6d3e1f0afdd7dfcbf736b22e4099a1596c22d603))
* **chat-api:** use_alter on users FK to avoid metadata resolution error ([e822201](https://github.com/manmohan659/nanochat/commit/e8222011d9918c71d4dc7abfa65d234490db1baa))
* **ci:** grant id-token write so EC2 deploy can assume the OIDC role ([#40](https://github.com/manmohan659/nanochat/issues/40)) ([9a45f09](https://github.com/manmohan659/nanochat/commit/9a45f0924dc074b0d3d59aa0540fead20e165cf5))
* **ci:** use astral-sh/setup-uv and --no-workspace for service tests ([66bac1a](https://github.com/manmohan659/nanochat/commit/66bac1aa5f068f946008ebf148e3e7d245fba379))
* **classifier:** expand identity veto to cover all self-introspection queries ([fd8e10a](https://github.com/manmohan659/nanochat/commit/fd8e10a820e8e7e49b53809014f9ffe389a0eb96))
* **classifier:** resolve pronouns from conversation history + roadmap ([2e5cf45](https://github.com/manmohan659/nanochat/commit/2e5cf45f8685e2c34b0c721b111c231cd9f6a1ce))
* **classifier:** veto identity/meta/greeting/writing queries from web_search ([5e3b17e](https://github.com/manmohan659/nanochat/commit/5e3b17e9908c454642e5805258b537d7be999665))
* **docker:** add structlog + prometheus deps to auth and chat-api Dockerfiles ([2061f88](https://github.com/manmohan659/nanochat/commit/2061f8848bd2b02948b2b750f63b7f643fcd8772))
* **docker:** pass missing env vars to auth service ([b797131](https://github.com/manmohan659/nanochat/commit/b7971313ba1a5c3724ebd2f90ac8d052627df368))
* **eval:** use UTF-8 when reading CORE JSONL and writing CSV ([a83646e](https://github.com/manmohan659/nanochat/commit/a83646e098374de4d4f2c2da1175d2f5fdd18ed3))
* **frontend:** add maxTokens to StreamBody interface ([fe34250](https://github.com/manmohan659/nanochat/commit/fe3425090044fc1345c9387ceeae3bc8b396a7b0))
* **frontend:** assistant messages fill the chat column ([#42](https://github.com/manmohan659/nanochat/issues/42)) ([94bec5f](https://github.com/manmohan659/nanochat/commit/94bec5f2a096f032493eecd67e1361d9e5390efa))
* **frontend:** pass assistantMsgId directly to fix stale closure bug ([16f40ce](https://github.com/manmohan659/nanochat/commit/16f40ceb54595c4e74bd5678cc40f58b2f014739))
* **frontend:** redesign landing and chat pages for warm, premium look ([36debd8](https://github.com/manmohan659/nanochat/commit/36debd85027e85b3daf8d47d896539948244fcc9))
* **frontend:** send correct body format to chat-api messages endpoint ([faf4810](https://github.com/manmohan659/nanochat/commit/faf481069669b0fe5e5eda1e4c7b70d52397c2bf))
* **frontend:** use any type for proxyUpstream body param ([7ecd8a9](https://github.com/manmohan659/nanochat/commit/7ecd8a928c9fdc3aae89bad0a999cdd71977739a))
* **frontend:** widen nav pill, default to dark theme ([#41](https://github.com/manmohan659/nanochat/issues/41)) ([748d2e5](https://github.com/manmohan659/nanochat/commit/748d2e561c8e1cfcecf5addee34b9dc96c724272))
* **inference:** regenerate uv.lock after structlog/prometheus deps added ([07892c0](https://github.com/manmohan659/nanochat/commit/07892c0f003c4453ccc4471af7113044b3d7f757))
* inject Tavily snippet text into grounding suffix ([3c5a815](https://github.com/manmohan659/nanochat/commit/3c5a815f92b9535843b92c78a3f66266168ecdf2))
* missing val_bpb on resume ([2fd0440](https://github.com/manmohan659/nanochat/commit/2fd0440355a34d592db285eaf5bc93858b57e80d))
* missing val_bpb on resume ([53b3a4f](https://github.com/manmohan659/nanochat/commit/53b3a4fb814d845107ed2a43db97cd2232433c68))
* **model:** apply float32 cast before logits softcapping ([16788ee](https://github.com/manmohan659/nanochat/commit/16788eed3cc3a79a94fa5bb852db722f79852cb7))
* **nginx:** re-resolve upstream IPs so deploys don't break auth ([#43](https://github.com/manmohan659/nanochat/issues/43)) ([67f568a](https://github.com/manmohan659/nanochat/commit/67f568a4f2a5130a937088bcddb47371a31ac3ca))
* **nginx:** route all /api/* through frontend, not directly to chat-api ([3f7a7da](https://github.com/manmohan659/nanochat/commit/3f7a7da30bee6603a22c0d2b88fbdc719d37c4f7))
* open JSONL and results CSV with UTF-8 encoding for portability ([226953b](https://github.com/manmohan659/nanochat/commit/226953b841f322bf88cb0f2af460a897f00393a2))
* pass device_type to compute_init in engine.__main__ ([#451](https://github.com/manmohan659/nanochat/issues/451)) ([6a477ee](https://github.com/manmohan659/nanochat/commit/6a477eedbdc8d2c66da84c2fbfcf907ee7e1ba60))
* remove unnecessary tensor allocation in DistAdamW optimizer ([49cd02f](https://github.com/manmohan659/nanochat/commit/49cd02f283b3688ff058ac854faae3c84560761e))
* return inf instead of crashing when evaluate_bpb has zero total_bytes ([02440f6](https://github.com/manmohan659/nanochat/commit/02440f670df71d26b39e924ade41e85e860deb38))
* safe DDP cleanup (check initialized PG, not just env) ([#256](https://github.com/manmohan659/nanochat/issues/256)) ([2f2d7ab](https://github.com/manmohan659/nanochat/commit/2f2d7ab80cd07a8b5fab9feebcb185fd3ca37339))
* sample first token independently for each row in multi-sample generation ([8f979a8](https://github.com/manmohan659/nanochat/commit/8f979a8bdab491c4c152ce5c87f90c2ec31d0845))
* search veto for identity+greetings, grounding suffix for tool results ([6069a73](https://github.com/manmohan659/nanochat/commit/6069a7329b46b200a84dea92cbad66ebde844fec))
* **serve:** decode-tail text match for tool markers ([d49de15](https://github.com/manmohan659/nanochat/commit/d49de1575bc942863989a3b5903967d860b92fa8))
* **serve:** detect tool markers in text stream not token ids ([7a92f5b](https://github.com/manmohan659/nanochat/commit/7a92f5b016c494117fe600083dacfc2927567e43))
* **serve:** don't scan our own injected tokens for the loop-break check ([57be688](https://github.com/manmohan659/nanochat/commit/57be688fdccbd32ef59d3da2752d48ad145c942c))
* **serve:** match tool markers on token-id sequences not decoded text ([ba727cb](https://github.com/manmohan659/nanochat/commit/ba727cb4d59b21e7770f91d98cf0bf07618577a2))
* **serve:** stop turn when model emits second output block after injection ([544ab89](https://github.com/manmohan659/nanochat/commit/544ab89c047689bf5cbb6b4d418412be4253acad))
* **serve:** strip system-prompt prefix before classifying user query ([297bc4b](https://github.com/manmohan659/nanochat/commit/297bc4bfb90bda3a11f35403b7c9b000537696c3))
* stream directly from chat-api, bypass Next.js proxy ([a873b6a](https://github.com/manmohan659/nanochat/commit/a873b6ad46396d85fada1917fd942bfa73749940))
* **terraform:** support day one environment apply ([374d026](https://github.com/manmohan659/nanochat/commit/374d0267c5788f5639b48f5cf830be33b7714ae2))
* **tools:** enable Tavily include_answer and fix UI overflow ([f70be25](https://github.com/manmohan659/nanochat/commit/f70be2521252a27ac8b78ebc3c4fda9dafa54e7e))
* **tools:** force web_search on tool-worthy queries + strip orphan markers in UI ([4628d53](https://github.com/manmohan659/nanochat/commit/4628d53d67455edbfd5ff62d748f5e71b4aa99e0))
* **ui:** prevent iOS Safari toolbar from covering input on initial load ([796f845](https://github.com/manmohan659/nanochat/commit/796f84527f3c62f7466eeb59f362d0827d619e6d))
* veto matches shorthand 'u' and 'r' for you/are ([8b360f5](https://github.com/manmohan659/nanochat/commit/8b360f5bc87f0ae58630aad6e9f542eafb7e0d7d))


### Features

* **admin:** add /dashboard with user analytics, gated on ADMIN_EMAIL ([0108ac1](https://github.com/manmohan659/nanochat/commit/0108ac103cf1c58831bd90107151dd3202488bb2))
* allow top_k=0 in web api to disable filtering ([#458](https://github.com/manmohan659/nanochat/issues/458)) ([ace6740](https://github.com/manmohan659/nanochat/commit/ace6740bdd392de4710f054afa7dc9368a076606))
* **auth:** OAuth2 + JWT auth service with Alembic migrations ([#5](https://github.com/manmohan659/nanochat/issues/5) [#7](https://github.com/manmohan659/nanochat/issues/7)) ([4b4aca6](https://github.com/manmohan659/nanochat/commit/4b4aca642a320b2ba1b167c7c24226b44401fdf3))
* **chat-api:** conversation orchestration + SSE streaming proxy ([#6](https://github.com/manmohan659/nanochat/issues/6)) ([8153a4f](https://github.com/manmohan659/nanochat/commit/8153a4fadfb786226bf4ef8341042ada936942f2))
* **ci:** CI/CD pipeline and Helm umbrella chart for samosaChaat ([#8](https://github.com/manmohan659/nanochat/issues/8)) ([53f547f](https://github.com/manmohan659/nanochat/commit/53f547fdefb8e9bf5b2eeb4dc86e780758692b58))
* deploy d24 SFT + polished UI redesign with dark mode ([#39](https://github.com/manmohan659/nanochat/issues/39)) ([1d2a76e](https://github.com/manmohan659/nanochat/commit/1d2a76eec49cb952422c01e1bbfe08a3181e42ec))
* deploy d24-sft-r6 with full reasoning mode + live tool use (Tavily) ([3ab89e7](https://github.com/manmohan659/nanochat/commit/3ab89e78909d25542fe7696f99ad76bfdcb8e8a9))
* **deploy:** add dual-mode deploy switch (EC2 monolith + EKS) ([b766dcf](https://github.com/manmohan659/nanochat/commit/b766dcf7036c63c2000d76caa163aaedd09c4d4e))
* double default and max generation budget ([5bd773e](https://github.com/manmohan659/nanochat/commit/5bd773ef13062c3b29ec14c5bb6edb9eb788e04e))
* **frontend:** mobile sidebar overlay + user menu for logout ([a12a991](https://github.com/manmohan659/nanochat/commit/a12a991f31018d5cbab1ef2e3ac402c90675f7ac))
* **frontend:** Next.js 14 frontend service for samosaChaat ([#2](https://github.com/manmohan659/nanochat/issues/2)) ([634be40](https://github.com/manmohan659/nanochat/commit/634be4080bf47324c9a2da9f19f80052c2faf5b6))
* **frontend:** wire frontend to real backend auth + chat-api services ([aa7a907](https://github.com/manmohan659/nanochat/commit/aa7a907063c9ad4c34b9dd0e6bbf2d32953c9227))
* **infra:** complete EKS assignment platform ([7a369b9](https://github.com/manmohan659/nanochat/commit/7a369b91c1e2309c0570b93498aafcefc576e97c))
* **modal:** add Modal GPU inference endpoint for samosaChaat ([e5b4db1](https://github.com/manmohan659/nanochat/commit/e5b4db1eee54b6020cb108a89e8f525a27401008))
* **observability:** Prometheus + Grafana + Loki stack for samosaChaat ([#9](https://github.com/manmohan659/nanochat/issues/9)) ([aa0818a](https://github.com/manmohan659/nanochat/commit/aa0818aae2b95257d3f63cc3b22f4f610613692c))
* **ops:** Day 2 operations automation and chaos runbook ([#10](https://github.com/manmohan659/nanochat/issues/10)) ([0b8f9f0](https://github.com/manmohan659/nanochat/commit/0b8f9f0a5f510f5ac63cde38cd382ee2324a5809))
* pad vocab size to 64 for DDP optimizers and efficiency ([f1bf69d](https://github.com/manmohan659/nanochat/commit/f1bf69d56290fb82788f0f7f7b70a7eaa484d1ec))
* **sft:** add r7 think+tool prep scripts and compose cleanup ([f642cb2](https://github.com/manmohan659/nanochat/commit/f642cb2eb6ea306d4d084ffaa50e24ef40bfc510))
* **terraform:** provision full AWS stack for samosaChaat (issue [#4](https://github.com/manmohan659/nanochat/issues/4)) ([b381933](https://github.com/manmohan659/nanochat/commit/b381933c3b47c9d0ddf6995cedd66190ada09f97))
* **ui:** add Search toggle that forces web_search every message ([215e8bd](https://github.com/manmohan659/nanochat/commit/215e8bd8c325c067aa2b2d596293d7c8f7add222))
* **ui:** cleaner input layout + sanitize model-output artifacts ([2b6b718](https://github.com/manmohan659/nanochat/commit/2b6b7186d3748de5c2a971dc222ad9279a60416f))
* **ui:** remove model selector dropdown - single model only ([43ad35f](https://github.com/manmohan659/nanochat/commit/43ad35f73b8c1db258be1ff7c8e9d60992bbf9e0))
