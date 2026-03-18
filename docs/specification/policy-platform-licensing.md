# Policy Library Platform — Software Licensing Analysis

> **Disclaimer:** This document provides a technical analysis of open source licence terms to inform engineering and product decisions. It is not legal advice. Before committing to a commercial launch, the licence positions of key components — particularly GitLab CE, Typesense, and any in-scope AI provider agreements — should be reviewed by a qualified solicitor or IP lawyer familiar with software licensing.

---

## The Central Question

**Can you monetise a platform built on GitLab CE?**

**Yes — clearly and cleanly, under two conditions:**

1. You are using GitLab CE as a *backend infrastructure component* that your application speaks to via API. Your customers never receive, install, or directly interact with GitLab.
2. You include copyright and licence attribution notices (e.g., an "Open Source Licences" page in your product), as required by MIT.

This is precisely the same model as building a SaaS product that uses PostgreSQL, Linux, or Node.js as infrastructure. MIT gives you permission to incorporate the software into a commercial product without sharing your application code. What it does not permit is removing GitLab's copyright notices, or misrepresenting your product as being GitLab itself.

The architecture as designed — where your customers interact entirely with your custom UI and API layer, and GitLab is a private backend they never see — is the cleanest possible use case for MIT-licensed infrastructure.

---

## Licence-by-Licence Breakdown

### GitLab CE
| Item | Detail |
|---|---|
| **Licence** | MIT |
| **Commercial use** | ✅ Permitted without restriction |
| **SaaS / monetisation** | ✅ Permitted |
| **Must open-source your app?** | ❌ No |
| **Obligations** | Include copyright + MIT licence notice in your product |

MIT is the most permissive commercial licence in open source. It explicitly grants the right to "use, copy, modify, merge, publish, distribute, sublicense, and/or **sell** copies of the software." There is no copyleft — your proprietary application code stays proprietary.

**Key risk to be aware of:** GitLab Inc. could change the licence for *future* versions of GitLab CE. MIT is irrevocable — they cannot take back the licence for the version you build on — but you could find yourself locked to an older version over time. In practice, GitLab has been MIT-licensed since 2011 and there is no indication of a change, but it is worth monitoring.

---

### TipTap Editor (core)
| Item | Detail |
|---|---|
| **Licence** | MIT |
| **Commercial use** | ✅ Permitted |
| **SaaS / monetisation** | ✅ Permitted |
| **Must open-source your app?** | ❌ No |
| **Obligations** | Include copyright notice |

The TipTap editor core (ProseMirror wrapper, all standard extensions) is MIT-licensed. This is what we use for the WYSIWYG editor. The paid "TipTap Platform" is only needed for their managed collaboration backend (real-time multi-user co-editing synced to Tiptap Cloud). Since our documents are saved to GitLab — not Tiptap Cloud — we do not need Tiptap Platform at all. We get a fully commercial-usable editor for free with zero platform dependency.

---

### Next.js
| Item | Detail |
|---|---|
| **Licence** | MIT |
| **Commercial use** | ✅ Permitted |
| **Must open-source your app?** | ❌ No |

No concerns. Next.js is MIT and Vercel explicitly builds their commercial hosting business on it.

---

### Auth.js (formerly NextAuth)
| Item | Detail |
|---|---|
| **Licence** | ISC (functionally equivalent to MIT) |
| **Commercial use** | ✅ Permitted |
| **Must open-source your app?** | ❌ No |

ISC is considered a simplified MIT licence. No concerns.

---

### Monaco Editor
| Item | Detail |
|---|---|
| **Licence** | MIT |
| **Commercial use** | ✅ Permitted |

Microsoft built VS Code commercially on Monaco. No concerns.

---

### PostgreSQL
| Item | Detail |
|---|---|
| **Licence** | PostgreSQL Licence (permissive, similar to MIT/BSD) |
| **Commercial use** | ✅ Permitted |

One of the most permissive licences in open source. No concerns.

---

### BullMQ (job queue)
| Item | Detail |
|---|---|
| **Licence** | MIT |
| **Commercial use** | ✅ Permitted |

No concerns.

---

### LlamaIndex (TypeScript)
| Item | Detail |
|---|---|
| **Licence** | MIT |
| **Commercial use** | ✅ Permitted |

No concerns.

---

### Typesense Server ⚠️
| Item | Detail |
|---|---|
| **Licence** | GPL-3.0 (server); Apache 2.0 (client libraries) |
| **Commercial use** | ✅ Permitted with important nuance |
| **Must open-source your app?** | ❌ No — see explanation below |

**This needs careful explanation.** GPL-3.0 is a copyleft licence — but copyleft only triggers when you *distribute* a modified version of the software. Running Typesense as a server that your application connects to over a network does **not** make your application a derivative work, and does **not** require you to open-source your application. This is the same reason you can build a commercial product on top of a Linux server without open-sourcing your application.

The licence that *would* be a problem is **AGPL** (Affero GPL), which adds a "network clause" — if users interact with your software over a network, you must release your source code. Typesense explicitly chose GPL *instead of* AGPL for exactly this reason: to allow commercial products to use it as a service without triggering source disclosure.

Typesense's own documentation confirms: *"GPL covers and allows for this use case generously... AGPL is what makes server software accessed over a network result in derivative work and not GPL."*

**Your obligations with Typesense:**
- If you run it unmodified (which you will), no obligations beyond attribution
- If you modify the Typesense source code and distribute it, you must release those modifications under GPL
- The Apache-licensed client library (which you include in your Node.js code) has no copyleft at all

**Verdict:** Typesense is safe to use commercially as a server. The client library is Apache-licensed and has no copyleft. No source disclosure required.

---

### Redis / Valkey 🔴 → ✅ (with the right choice)

This is the most complex licensing situation in the stack and requires an explicit decision.

**The situation:**
- Redis 7.4 and later: dual-licensed RSALv2 + SSPLv1 (neither is OSI-approved open source)
- Redis 8.0 and later: tri-licensed RSALv2 + SSPLv1 + **AGPLv3**
- AGPLv3's network clause means: if users access your application over a network and your application uses AGPL-licensed code, you must release your *entire application's* source code

**This is a serious problem for a commercial SaaS product.** AGPL is specifically designed to prevent the "build a closed SaaS on open source" model. Using Redis 8+ in a commercial SaaS without open-sourcing your platform would breach the AGPLv3 licence.

**The clean solution: Valkey**

| Item | Detail |
|---|---|
| **Licence** | BSD-3-Clause |
| **Commercial use** | ✅ Fully permitted |
| **Must open-source your app?** | ❌ No |
| **Governance** | Linux Foundation (neutral, multi-vendor) |
| **Compatibility** | Drop-in replacement for Redis 7.2 — no code changes |
| **Backed by** | AWS, Google Cloud, Oracle, Ericsson, Huawei, Tencent |

Valkey is a fork of the last BSD-licensed Redis (7.2.4), maintained by the Linux Foundation with backing from every major cloud provider except Microsoft (who did a commercial deal with Redis instead). It is a complete, drop-in, wire-compatible replacement. AWS has already moved all new ElastiCache clusters to Valkey by default.

**Decision: Use Valkey instead of Redis. Zero code changes required. Eliminates all licensing risk.**

---

### Anthropic Claude API
| Item | Detail |
|---|---|
| **Licence type** | Commercial API — usage terms |
| **SaaS use** | ✅ Permitted under standard API terms |
| **Data processing** | Covered by Anthropic's standard DPA |
| **Key consideration** | Prompt content (policy text) is sent to Anthropic's servers for AI processing. Verify DPA meets your data sovereignty requirements. |

If data sovereignty is a hard requirement, the AI service can be pointed at **Azure OpenAI** (same models, hosted in your Azure tenant, covered by your Microsoft agreement) rather than Anthropic's direct API. No other architecture changes are needed — this is a configuration-level swap.

---

## Revised Stack with Licensing Verdicts

| Component | Licence | Commercial OK? | Change needed? |
|---|---|---|---|
| GitLab CE | MIT | ✅ | None |
| TipTap Editor (core) | MIT | ✅ | None |
| Next.js | MIT | ✅ | None |
| Auth.js | ISC | ✅ | None |
| Monaco Editor | MIT | ✅ | None |
| PostgreSQL | PostgreSQL | ✅ | None |
| BullMQ | MIT | ✅ | None |
| LlamaIndex TS | MIT | ✅ | None |
| Typesense Server | GPL-3.0 | ✅ (as server) | None |
| Typesense client | Apache 2.0 | ✅ | None |
| **Redis** | RSALv2/SSPL/AGPL | ⚠️ Risky | **Replace with Valkey** |
| **Valkey** | BSD-3-Clause | ✅ | Use this instead |
| Claude API | Commercial terms | ✅ | Verify DPA |

**One change required: Replace Redis with Valkey.** Everything else in the stack is clean for commercial use.

---

## Your Own Code: How to Protect It

When you commercialise this platform, your own application code is your primary intellectual property. Here is how to structure it:

### If building for internal use only (no external sale)
- Licence is irrelevant — use whatever open source components you want
- Your own code has no licence obligations beyond your employment/contracting arrangements

### If selling to external customers (SaaS or licensed software)

**Option A: Fully proprietary (recommended for v1)**
- Your application code: All Rights Reserved / proprietary
- Open source dependencies: included with attribution (licence notices page)
- Customers: no access to your source code
- Pro: maximum IP protection, no obligation to share innovations
- Con: if a customer wants to self-host, you must provide support; no community contributions

**Option B: Open Core**
- Core platform: permissive open source (MIT or Apache 2.0)
- Premium features (advanced AI, enterprise SSO, analytics, SLA support): proprietary / paid tier
- Pro: community adoption, trust from enterprise buyers, marketing value
- Con: competitors can use your open source core; requires careful boundary design

**Option C: Source Available**
- Source code visible but commercial use restricted (e.g., Business Source Licence)
- Becoming more common for developer tools (HashiCorp Terraform used this model)
- Pro: transparency without giving away commercial use rights
- Con: not "open source" in the OSI sense, some community resistance

**Recommendation:** Start with fully proprietary (Option A). If you gain traction and want to build community, transition core components to open source under the Open Core model at a defined point. Do not try to do both at once — it complicates go-to-market significantly.

---

## Monetisation Models

All of the following are permitted by the licence stack:

| Model | Description | Licence risk |
|---|---|---|
| SaaS (hosted, per-seat) | Charge per user/month for hosted access | ✅ None |
| On-premises licence | Customer self-hosts, pays annual licence | ✅ None |
| Managed deployment | You host a dedicated instance per customer | ✅ None |
| OEM / white-label | Sell to other vendors to rebrand | ✅ None (with attribution) |
| Consultancy + customisation | Implementation and configuration fees | ✅ None |

The only things you **cannot** do under the current stack:
- Call your product "GitLab" or imply it is GitLab (trademark, not licence)
- Remove copyright and attribution notices for MIT/Apache-licensed components
- Modify the Typesense server binary and distribute it without releasing those modifications

---

## Practical Obligations Summary

When you launch commercially, you will need to:

1. **Add an open source attributions page** to the product (or include in documentation). This lists all MIT/Apache/BSD licensed components with their copyright notices. This is the primary obligation of using permissive licences.

2. **Replace Redis with Valkey** in the infrastructure stack (zero code changes, drop-in replacement).

3. **Get a DPA signed with Anthropic** (or switch to Azure OpenAI) before processing real customer policy data through the AI service.

4. **Register your own trademarks** for your product name/brand before launch.

5. **Have a solicitor review your customer licence agreement** to ensure the open source attribution obligations are correctly passed through, and that your proprietary code rights are properly protected.
