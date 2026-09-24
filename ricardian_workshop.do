* ECON 561: Ricardian simulation workshop
* Identical code blocks appear in README.md with equations and discussion.
* Select a writable working directory before running.

* ----- 1. Setup (0-5 minutes) -----
version 16.0
clear all
set more off
set scheme s2color
pwd
capture mkdir output
capture log close riclab
log using "output/ricardian_class.log", text replace name(riclab)

input double(aCN aTN aCS aTS LN LS beta)
2 1 10 2 100 100 .5
end
list, noobs

* ----- 2. Autarky equations (5-15 minutes) -----
capture program drop autarky
program define autarky
    foreach c in N S {
        assert aC`c' > 0 & aC`c' < .
        assert aT`c' > 0 & aT`c' < .
        assert L`c' > 0 & L`c' < .
    }
    assert beta > 0 & beta < 1
    gen double rN = aCN/aTN
    gen double rS = aCS/aTS
    foreach c in N S {
        gen double cA_`c' = beta/aC`c'
        gen double tA_`c' = (1-beta)/aT`c'
        gen double DCA_`c' = L`c'*cA_`c'
        gen double DTA_`c' = L`c'*tA_`c'
        gen double uA_`c' = cA_`c'^beta*tA_`c'^(1-beta)
        assert abs(aC`c'*DCA_`c'+aT`c'*DTA_`c'-L`c') < 1e-8
    }
end

autarky
list rN rS cA_N tA_N cA_S tA_S, noobs
list DCA_N DTA_N DCA_S DTA_S, noobs

* ----- 2. Autarky graphs -----
preserve
expand 201
gen double z = (_n-1)/200
foreach c in N S {
    gen double x_`c' = z*L`c'/aC`c'
    gen double ppf_`c' = (L`c'-aC`c'*x_`c')/aT`c'
    gen double icA_`c' = L`c'*(uA_`c'/(x_`c'/L`c')^beta)^(1/(1-beta)) if x_`c'>0
    replace icA_`c' = . if icA_`c'>1.1*L`c'/aT`c'
    twoway (line ppf_`c' x_`c', lcolor(navy)) ///
        (line icA_`c' x_`c', lcolor(gs8) lpattern(dash)) ///
        (scatter DTA_`c' DCA_`c' if _n==1, mcolor(black) msymbol(O)), ///
        title("`c': autarky") xtitle("Computers: national quantity") ///
        ytitle("Textiles: national quantity", margin(medium)) ylabel(, angle(horizontal)) ///
        legend(order(1 "PPF = budget" 2 "Indifference curve" 3 "Autarky") cols(1) size(small)) ///
        name(aut_`c', replace)
}
graph combine aut_N aut_S, cols(2) iscale(.65) xsize(12) ysize(6) title("Autarky: consumption equals production")
graph export "output/01_autarky.png", width(2000) replace
restore

* ----- 3. Free-trade solver and checks (15-30 minutes) -----
capture program drop trade
program define trade
    assert rN < rS
    gen double rho_hat = beta/(1-beta)*(LS/LN)*(aCN/aTS)
    gen double rho = max(rN,min(rho_hat,rS))
    gen byte regime = 2
    replace regime = 1 if rho_hat < rN
    replace regime = 3 if rho_hat > rS
    label define regime_lab 1 "North diversified" 2 "Both specialized" 3 "South diversified", replace
    label values regime regime_lab

    gen double wN = rho/aCN
    gen double wS = 1/aTS
    foreach c in N S {
        gen double cF_`c' = beta*w`c'/rho
        gen double tF_`c' = (1-beta)*w`c'
        gen double DCF_`c' = L`c'*cF_`c'
        gen double DTF_`c' = L`c'*tF_`c'
    }

    * Start at both specialization corners; revise the diversified case.
    gen double QC_N = LN/aCN
    gen double QT_N = 0
    gen double QC_S = 0
    gen double QT_S = LS/aTS
    replace QC_N = DCF_N+DCF_S if regime==1
    replace QT_N = (LN-aCN*QC_N)/aTN if regime==1
    replace QT_S = DTF_N+DTF_S if regime==3
    replace QC_S = (LS-aTS*QT_S)/aCS if regime==3

    foreach c in N S {
        gen double NX_C_`c' = QC_`c'-DCF_`c'
        gen double NX_T_`c' = QT_`c'-DTF_`c'
        gen double uF_`c' = cF_`c'^beta*tF_`c'^(1-beta)
        gen double gain_`c' = 100*(uF_`c'/uA_`c'-1)
        gen double shareC_`c' = aC`c'*QC_`c'/L`c'

        * Full employment, budgets, balanced trade, and feasible outputs.
        assert abs(aC`c'*QC_`c'+aT`c'*QT_`c'-L`c') < 1e-8
        assert abs(rho*DCF_`c'+DTF_`c'-w`c'*L`c') < 1e-8
        assert abs(rho*NX_C_`c'+NX_T_`c') < 1e-8
        assert QC_`c'>=-1e-8 & QT_`c'>=-1e-8
        * No positive profits; zero profits in each active sector.
        assert rho <= w`c'*aC`c'+1e-8
        assert 1 <= w`c'*aT`c'+1e-8
        assert abs(rho-w`c'*aC`c') < 1e-8 if QC_`c'>1e-8
        assert abs(1-w`c'*aT`c') < 1e-8 if QT_`c'>1e-8
        assert gain_`c'>=-1e-8 & gain_`c'<.
    }
    assert abs(QC_N+QC_S-DCF_N-DCF_S) < 1e-8
    assert abs(QT_N+QT_S-DTF_N-DTF_S) < 1e-8
end

trade
list rho_hat rho regime wN wS, noobs
list QC_N QT_N DCF_N DTF_N QC_S QT_S DCF_S DTF_S, noobs
list NX_C_N NX_T_N NX_C_S NX_T_S gain_N gain_S, noobs
save "output/baseline.dta", replace

* ----- 4. Visualize gains (30-40 minutes) -----
preserve
expand 301
gen double z = (_n-1)/300
foreach c in N S {
    gen double xmax_`c' = max(L`c'/aC`c',w`c'*L`c'/rho)
    gen double ymax_`c' = max(L`c'/aT`c',w`c'*L`c')
    gen double x_`c' = z*xmax_`c'
    gen double ppf_`c' = (L`c'-aC`c'*x_`c')/aT`c'
    replace ppf_`c' = . if ppf_`c'<0
    gen double bc_`c' = w`c'*L`c'-rho*x_`c'
    replace bc_`c' = . if bc_`c'<0
    foreach s in A F {
        gen double ic`s'_`c' = L`c'*(u`s'_`c'/(x_`c'/L`c')^beta)^(1/(1-beta)) if x_`c'>0
        replace ic`s'_`c' = . if ic`s'_`c'>1.1*ymax_`c'
    }
    twoway (line ppf_`c' x_`c', lcolor(navy) lwidth(medthick)) ///
        (line bc_`c' x_`c', lcolor(maroon) lpattern(dash)) ///
        (line icA_`c' x_`c', lcolor(gs10)) ///
        (line icF_`c' x_`c', lcolor(teal) lpattern(shortdash)) ///
        (scatter DTA_`c' DCA_`c' if _n==1, msymbol(Oh) msize(large) mcolor(black)) ///
        (scatter QT_`c' QC_`c' if _n==1, msymbol(T) mcolor(navy)) ///
        (scatter DTF_`c' DCF_`c' if _n==1, msymbol(D) mcolor(maroon)), ///
        title("`c': production and consumption") ///
        xtitle("Computers: national quantity") ytitle("Textiles: national quantity", margin(medium)) ylabel(, angle(horizontal)) ///
        legend(order(1 "PPF" 2 "Trade budget" 3 "Autarky IC" 4 "Trade IC" ///
            5 "Autarky bundle" 6 "Production" 7 "Consumption") cols(2) size(vsmall) symxsize(5)) ///
        name(ft_`c', replace)
}
graph combine ft_N ft_S, cols(2) iscale(.65) xsize(12) ysize(6) title("Trade separates consumption from production")
graph export "output/02_trade_budgets.png", width(2400) replace
restore

graph bar gain_N gain_S, ///
    legend(order(1 "North" 2 "South")) blabel(bar, format(%5.2f)) ///
    ytitle("Real consumption-income gain (%)") ///
    title("Free trade relative to each country's autarky") name(gains, replace)
graph export "output/03_baseline_gains.png", width(1600) replace

* ----- 5. Population counterfactual (40-55 minutes) -----
clear
set obs 601
gen double LS = 49+_n
gen double LN = 100
gen double aCN = 2
gen double aTN = 1
gen double aCS = 10
gen double aTS = 2
gen double beta = .5
autarky
trade

list LS rho regime shareC_N shareC_S gain_N gain_S ///
    if inlist(LS,100,200,300,500,600), noobs

twoway (line rho LS, lcolor(navy) lwidth(medthick)) ///
    (line rho_hat LS, lcolor(gs8) lpattern(dash)), ///
    xline(200 500, lpattern(shortdash)) yline(2 5, lcolor(gs12)) ///
    xtitle("South workers; North fixed at 100") ytitle("Computer price / textile price") ///
    legend(order(1 "Equilibrium price" 2 "Both-specialized candidate")) ///
    title("Market size changes the equilibrium regime") name(pop_price, replace)
graph export "output/04_population_price.png", width(1800) replace

twoway (line shareC_N LS, lcolor(navy)) ///
    (line shareC_S LS, lcolor(maroon)), xline(200 500, lpattern(shortdash)) ///
    ylabel(0(.25)1) xtitle("South workers") ytitle("Share of own labor in computers") ///
    legend(order(1 "North" 2 "South")) title("Specialization is an outcome") ///
    name(pop_jobs, replace)
graph export "output/05_population_employment.png", width(1800) replace

twoway (line gain_N LS, lcolor(navy)) (line gain_S LS, lcolor(maroon)), ///
    xline(200 500, lpattern(shortdash)) yline(0, lcolor(gs12)) ///
    xtitle("South workers") ytitle("Gain versus own autarky (%)") ///
    legend(order(1 "North" 2 "South")) title("Who captures gains as South grows?") ///
    name(pop_gains, replace)
graph export "output/06_population_gains.png", width(1800) replace
save "output/population_sweep.dta", replace
export delimited using "output/population_sweep.csv", replace

* ----- 6. Textile productivity (55-70 minutes) -----
clear
set obs 101
gen double k = 1+(_n-1)/100
gen double aCN = 2
gen double aTN = 1
gen double aCS = 10
gen double aTS = 2/k
gen double LN = 100
gen double LS = 300
gen double beta = .5
autarky
trade
assert regime==2
sort k
foreach c in N S {
    gen double change_`c' = 100*(uF_`c'/uF_`c'[1]-1)
}
assert abs(change_N-change_S)<1e-8
list k aTS rho wN wS change_N change_S gain_N gain_S if inlist(k,1,2), noobs

twoway (line rho k, lcolor(navy)) (line rS k, lcolor(maroon) lpattern(dash)) ///
    (line rN k, lcolor(gs8) lpattern(shortdash)), ///
    xtitle("South textile productivity multiplier k") ytitle("Relative price") ///
    legend(order(1 "World price" 2 "South opportunity cost" 3 "North opportunity cost")) ///
    title("Technology changes relative prices") name(tech_price, replace)
graph export "output/07_productivity_price.png", width(1800) replace

twoway (line change_N k, lcolor(navy) lwidth(thick)) ///
    (line change_S k, lcolor(maroon) lpattern(dash)), ///
    xtitle("South textile productivity multiplier k") ytitle("Change from initial free trade (%)") ///
    legend(order(1 "North" 2 "South (same values)")) ///
    title("Both benefit from South's textile innovation") name(tech_change, replace)
graph export "output/08_productivity_welfare.png", width(1800) replace

twoway (line gain_N k, lcolor(navy)) (line gain_S k, lcolor(maroon)), ///
    xtitle("South textile productivity multiplier k") ytitle("Gain versus current autarky (%)") ///
    legend(order(1 "North" 2 "South")) title("A different benchmark: gains from trade") ///
    name(tech_gains, replace)
graph export "output/09_productivity_trade_gains.png", width(1800) replace
save "output/productivity_sweep.dta", replace
export delimited using "output/productivity_sweep.csv", replace

* ----- 6. Student variation: computer productivity -----
clear
input double(aCN aTN aCS aTS LN LS beta)
2 1 10 2 100 300 .5
2 1  5 2 100 300 .5
end
gen byte scenario = _n
label define scenario_lab 1 "Before" 2 "South computer innovation", replace
label values scenario scenario_lab
autarky
trade
sort scenario
foreach c in N S {
    gen double change_`c' = 100*(uF_`c'/uF_`c'[1]-1)
}
list scenario rho regime uF_N uF_S change_N change_S gain_N gain_S, noobs

graph bar change_N change_S, over(scenario) ///
    legend(order(1 "North" 2 "South")) blabel(bar, format(%5.2f)) ///
    yline(0, lcolor(gs8)) ytitle("Change from initial free trade (%)") ///
    title("South computer innovation changes the terms of trade", size(medium)) name(import_tech, replace)
graph export "output/10_computer_innovation.png", width(1800) replace
save "output/computer_innovation.dta", replace

* ----- 7. Exit exercise and close log (70-75 minutes) -----
log close riclab
display "Lab complete. Graphs, datasets, CSV sweeps, and the class log are in output/."
