// The open-source Fluid Framework pieces OST's Loop page host uses, as
// Teams bundles them (Fluid Framework 2.118.1, MIT; docs/spec/loop-host.md):
// the container loader, the dependency synthesizer and the ODSP share-link
// URL resolver. The ODSP driver itself is Microsoft's service-delivered one
// (res.cdn.office.net), loaded at run time as Teams loads it.
//
// Rebuild fluid-loader.js (outside the repo's build; node 20+):
//   npm ci && npm run build
// Its third-party licences are listed in desktop/THIRD-PARTY-NOTICES.md.
export { Loader } from "@fluidframework/container-loader/internal";
export { DependencyContainer } from "@fluidframework/synthesize/internal";
export { OdspDriverUrlResolverForShareLink } from "./node_modules/@fluidframework/odsp-driver/lib/odspDriverUrlResolverForShareLink.js";
export { createOdspCreateContainerRequest } from "./node_modules/@fluidframework/odsp-driver/lib/createOdspCreateContainerRequest.js";
