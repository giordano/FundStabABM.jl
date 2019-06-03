using Test, Random, LinearAlgebra

include("../src/types.jl")
include("../src/functions.jl")
include("../src/params.jl")
using .Types, .Func, .Params

# Set up types
market = Types.MarketIndex(
    zeros(Params.bigt))
stocks = Types.Equity(
    zeros(Params.bigm, Params.bigt),
    zeros(Params.bigm),
    zeros(Params.bigm),
    zeros(Params.bigm))
investors = Types.RetailInvestor(
    zeros(Params.bign, Params.bigk + 1),
    zeros(Params.bign),
    zeros(Params.bign))
funds = Func.Types.EquityFund(
    zeros(Params.bigk, Params.bigm),
    zeros(Params.bigk, Params.bign),
    zeros(Params.bigk, Params.bigt))

# TODO: Think about how I should have tested the initialisation
# Initialise market and agents
Func.marketinit!(market.value)
Func.betainit!(stocks.beta)
Func.stockvolinit!(stocks.vol)
Func.stockvalueinit!(stocks, market.value)
Func.stockimpactinit!(stocks.impact)
Func.invhorizoninit!(investors.horizon)
Func.invthreshinit!(investors.threshold)
Func.invassetinit!(investors.assets)
Func.fundcapitalinit!(funds.value, investors.assets)
Func.fundstakeinit!(funds.stakes, investors.assets)
Func.fundholdinit!(funds.holdings, funds.value[:, 1], stocks.value)
Func.fundvalinit!(funds.value, funds.holdings, stocks.value)

# TODO: Think about how I should have tested the running cycle
# TODO: Write functions that collect activity of a) selling out and b) buying in
# TODO: Tests for cases with empty reviewers, divestments
# QUESTION: Need 'if reviewers not empty'/'divestments not empty' branches?
# Looping over time after the end of the  perfwindow[end]+1 initialisation phase
for t in (Params.perfwindow[end]+2):Params.bigt

    # Market index and assets move
    Func.marketmove!(market.value, t)
    Func.stockmove!(stocks.value, t, market.value, stocks.beta, stocks.vol)
    Func.fundrevalue!(funds, stocks.value)

    # QUESTION: Consider whether I should pass t instead of stocks.value[:, t]
    # Investors (may_ sell out of underperforming funds
    # TODO: Test sellorders.investors == cashout[1,:], similar for buyorders
    # TODO: No cashout of value 0
    # QUESTION: Enforce integers for fund/investor IDs in sellorders, cashout..?

    # Investors' performance review
    reviewers = Func.drawreviewers()
    divestments = Func.perfreview(t, reviewers, investors, funds.value)

    # Run liquidation/reinvestment cycle if there are divestments
    if size(divestments,1) > 0

        sellorders, _, _ = Func.liquidate!(funds.holdings, funds.stakes,
        stocks.value[:, t], divestments)

        _, cashout = Func.executeorder!(stocks, t, sellorders)
        Func.disburse!(investors.assets, divestments, cashout)

        # TODO: Write test that check correct outocme of the whole process,
        # step by step

        # Generate a new fund for each dead one, if there are dead ones
        if any(sum(funds.stakes, dims=2) .== 0)

            buyorders, _, _ = Func.respawn!(funds, investors, t, stocks.value)

            _, sharesout = Func.executeorder!(stocks, t, buyorders)

            Func.disburse!(funds, sharesout, stocks.value)

        end # respawn loop

        # Re-value funds prior to reinvestment decisions
        Func.fundrevalue!(funds, stocks.value)

        # If there are still investors with spare cash, they reinvest it
        if any(investors.assets[:, end] .> 0)

            _, _, buyorders = Func.reinvest!(investors, funds, stocks.value, t)
            _, sharesout = Func.executeorder!(stocks, t, buyorders)

            Func.disburse!(funds, sharesout, stocks.value)
        end # reinvestment loop

    end # Divestment loop
end # Model run
