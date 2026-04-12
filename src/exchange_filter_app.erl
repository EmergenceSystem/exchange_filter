%%%-------------------------------------------------------------------
%%% @doc Currency exchange rate agent.
%%%
%%% Returns exchange rates for a given base currency against a set of
%%% major fiat currencies and cryptocurrencies.
%%%
%%% API: https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest
%%%      /v1/currencies/{base}.json  (free, no key, jsDelivr CDN)
%%%
%%% Query: any currency code or name — "eur", "EUR", "dollar", "bitcoin".
%%% The first recognised currency code in the query is used as the base.
%%% Defaults to "usd" when nothing matches.
%%%
%%% Handler contract: handle/2 (Body, Memory) -> {RawList, Memory}.
%%% @end
%%%-------------------------------------------------------------------
-module(exchange_filter_app).
-behaviour(application).

-export([start/2, stop/1]).
-export([handle/2, base_capabilities/0]).

-define(BASE_URL,
    "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/").

%% Currencies to display in results (always shown when available).
-define(DISPLAY, [<<"usd">>, <<"eur">>, <<"gbp">>, <<"jpy">>, <<"chf">>,
                  <<"cad">>, <<"aud">>, <<"cny">>, <<"btc">>, <<"eth">>]).

%%====================================================================
%% Capability cascade
%%====================================================================

-spec base_capabilities() -> [binary()].
base_capabilities() ->
    em_filter:base_capabilities() ++ [<<"exchange">>, <<"currency">>,
                                      <<"forex">>, <<"crypto">>,
                                      <<"rates">>].

%%====================================================================
%% Application behaviour
%%====================================================================

start(_Type, _Args) ->
    em_filter:start_agent(exchange_filter, ?MODULE, #{
        capabilities => base_capabilities()
    }),
    {ok, self()}.

stop(_State) ->
    em_filter:stop_agent(exchange_filter).

%%====================================================================
%% Agent handler
%%====================================================================

handle(Body, Memory) when is_binary(Body) ->
    {generate_embryo_list(Body), Memory};
handle(_Body, Memory) ->
    {[], Memory}.

%%====================================================================
%% Query processing
%%====================================================================

generate_embryo_list(JsonBinary) ->
    {Query, Timeout} = extract_params(JsonBinary),
    Base = extract_currency(Query),
    fetch_rates(Base, Timeout).

extract_params(JsonBinary) ->
    try json:decode(JsonBinary) of
        Map when is_map(Map) ->
            Query = binary_to_list(maps:get(<<"value">>, Map,
                        maps:get(<<"query">>, Map, <<"">>))),
            Timeout = to_timeout(maps:get(<<"timeout">>, Map, undefined)),
            {Query, Timeout};
        _ ->
            {binary_to_list(JsonBinary), 10}
    catch
        _:_ -> {binary_to_list(JsonBinary), 10}
    end.

%% Extract the first currency code from the query string.
%% Accepts 2-5 letter codes (EUR, USD, BTC, ETH, ...).
%% Aliases: "dollar"→usd, "euro"→eur, "pound"→gbp, "bitcoin"→btc,
%%          "ethereum"→eth, "yen"→jpy, "franc"→chf, "yuan"→cny.
-spec extract_currency(string()) -> string().
extract_currency(Query) ->
    Q = string:lowercase(string:trim(Query)),
    case named_alias(Q) of
        {ok, Code} -> Code;
        none ->
            Words = string:tokens(Q, " \t,;:/"),
            find_code(Words)
    end.

named_alias(Q) ->
    Aliases = [{"dollar", "usd"}, {"euro", "eur"}, {"pound", "gbp"},
               {"bitcoin", "btc"}, {"ethereum", "eth"}, {"yen", "jpy"},
               {"franc", "chf"}, {"yuan", "cny"}, {"renminbi", "cny"},
               {"rupee", "inr"}, {"ruble", "rub"}, {"won", "krw"}],
    case lists:keyfind(Q, 1, Aliases) of
        {_, Code} -> {ok, Code};
        false     -> none
    end.

find_code([]) -> "usd";
find_code([W | Rest]) ->
    case length(W) >= 2 andalso length(W) =< 5
         andalso lists:all(fun(C) -> C >= $a andalso C =< $z end, W) of
        true  -> W;
        false -> find_code(Rest)
    end.

%%====================================================================
%% Fetch and parse
%%====================================================================

fetch_rates(Base, Timeout) ->
    Url = lists:flatten(io_lib:format("~s~s.json", [?BASE_URL, Base])),
    case httpc:request(get, {Url, []},
                       [{timeout, Timeout * 1000},
                        {ssl, [{verify, verify_none}]}],
                       [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} -> parse_rates(Body, Base);
        _                            -> []
    end.

parse_rates(JsonBin, Base) ->
    try json:decode(JsonBin) of
        Map when is_map(Map) ->
            BaseBin = list_to_binary(Base),
            Rates   = maps:get(BaseBin, Map, #{}),
            Date    = maps:get(<<"date">>, Map, <<"">>),
            build_embryos(BaseBin, Rates, Date);
        _ -> []
    catch
        _:_ -> []
    end.

build_embryos(Base, Rates, Date) ->
    UpperBase = string:uppercase(binary_to_list(Base)),
    %% Always show DISPLAY currencies; append any others in the query.
    Display = [C || C <- ?DISPLAY, C =/= Base],
    lists:filtermap(fun(Code) ->
        case maps:get(Code, Rates, undefined) of
            undefined -> false;
            Rate ->
                RateStr = format_rate(Rate),
                Title   = iolist_to_binary([
                    "1 ", string:uppercase(binary_to_list(Code)),
                    " = ", RateStr, " ", UpperBase
                ]),
                {true, #{<<"properties">> => #{
                    <<"url">>    => iolist_to_binary([
                        "https://cdn.jsdelivr.net/npm/@fawazahmed0/",
                        "currency-api@latest/v1/currencies/", Base, ".json"
                    ]),
                    <<"title">>  => Title,
                    <<"resume">> => iolist_to_binary(["Date: ", Date]),
                    <<"source">> => <<"fawazahmed0/currency-api">>
                }}}
        end
    end, Display).

format_rate(R) when is_float(R) ->
    %% Show up to 6 significant digits, trim trailing zeros.
    Raw = lists:flatten(io_lib:format("~.6f", [R])),
    trim_zeros(Raw);
format_rate(R) when is_integer(R) ->
    integer_to_list(R);
format_rate(_) -> "?".

trim_zeros(S) ->
    case lists:member($., S) of
        false -> S;
        true  ->
            T = lists:reverse(lists:dropwhile(fun(C) -> C =:= $0 end,
                                              lists:reverse(S))),
            case lists:last(T) of
                $. -> T ++ "0";
                _  -> T
            end
    end.

%%====================================================================
%% Helpers
%%====================================================================

to_timeout(undefined)            -> 10;
to_timeout(T) when is_integer(T) -> T;
to_timeout(T) when is_binary(T)  ->
    try binary_to_integer(T) catch _:_ -> 10 end;
to_timeout(_) -> 10.
