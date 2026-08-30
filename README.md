# exchange_filter
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE.md)

An [em_filter](https://hex.pm/packages/em_filter) agent that returns live currency exchange rates via the [fawazahmed0/currency-api](https://github.com/fawazahmed0/exchange-api) (free, no key, served via jsDelivr CDN).


<!-- emergence-context -->
Part of **[EmergenceSystem](https://github.com/EmergenceSystem)** — a distributed
discovery network of small, single-source agents. This filter joins the em_pop gossip
mesh and answers `POST /agent/query`; Emquest fans each query out to many filters in
parallel and aggregates the results.

## Query

A currency code or common name used as the **base** currency. Rates against the 10 major currencies below are always returned.

| Input form | Example |
|---|---|
| ISO code | `eur`, `EUR`, `btc` |
| Name alias | `euro`, `dollar`, `bitcoin`, `pound`, `yen`, `franc`, `yuan` |
| First token fallback | any 2-5 letter word is tried as a code |

**Display currencies:** USD, EUR, GBP, JPY, CHF, CAD, AUD, CNY, BTC, ETH

| Field | Example |
|---|---|
| title | `1 USD = 0.9287 EUR` |
| resume | `Date: 2026-04-12` |
| source | `fawazahmed0/currency-api` |

## Usage

**Via curl (direct to em_disco):**

```bash
# Euro rates
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "eur", "capabilities": ["exchange"]}'

# Bitcoin rates
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "bitcoin", "capabilities": ["exchange"]}'

# Swiss franc
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "franc", "capabilities": ["exchange"]}'
```

**Via Erlang shell:**

```erlang
emquest_cli:query(<<"dollar">>).
emquest_cli:query(<<"jpy">>).
```

## Installation

```bash
git clone https://github.com/EmergenceSystem/exchange_filter.git
cd exchange_filter
rebar3 shell --apps exchange_filter
```

Requires `em_disco` running on `localhost:8080` (configured in `emergence.conf`).

## Capabilities

`search`, `query`, `exchange`, `currency`, `forex`, `crypto`, `rates`

## License

Apache 2.0 — see [LICENSE.md](LICENSE.md).
