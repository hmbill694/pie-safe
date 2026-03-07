# Progress: auth_flow_170307_implementation

- [x] Phase 1: env vars (.envrc, .envrc.sample)
- [x] Phase 2: config.gleam - added jwt_secret field
- [x] Phase 3: token.gleam - new file with generate() and hash()
- [x] Phase 4: jwt.gleam - new file with Claims, sign(), verify()
- [x] Phase 5: registry_actor.gleam - added 5 new Message variants and handlers
- [x] Phase 6: auth.gleam - new file with all 4 handler functions
- [x] Phase 7: backend.gleam - added auth import, ctx, and 4 route branches
- [x] Phase 8: home.gleam - rewrote with Loading state, HTTP session check
- [x] gleam.toml - added gleam_json and youid dependencies
- [x] manifest.toml - added gleam_json and youid to requirements
