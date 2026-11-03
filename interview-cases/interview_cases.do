* ECON 561: Empirical case interviews for economists in tech and consulting (answer key)
* Identical code blocks appear in README.md with the interview prompt and a model answer.
* All data are SIMULATED with a known true answer, so we can check which method finds it.
* Built-in Stata 16+ commands only. No internet needed.

* ----- 0. Setup -----
version 16.0
clear all
set more off
set scheme s1color
capture mkdir output
capture log close cases
log using "output/interview_cases.log", text replace name(cases)


* ----- Case 1. A/B test: did the new recommendation feature raise listening? -----
* 1a. Simulate the experiment: 20,000 users, 4 weeks after launch
clear
set seed 561
set obs 20000
gen id      = _n
gen treat   = runiform() < .5
gen premium = runiform() < .4
gen pre     = exp(rnormal(5,.8))               // minutes per week BEFORE the test
expand 4
bysort id: gen week = _n
gen eff = (.02 + .04*exp(-(week-1))) * cond(premium,.5,1.5)   // true lift, fading over time
gen y0  = pre*exp(rnormal(0,.5) - .125)        // minutes without the feature
gen y1  = y0*exp(eff)                          // minutes with the feature
gen minutes = cond(treat, y1, y0)
save "output/case1_panel.dta", replace
collapse (sum) minutes y0 y1 (first) treat premium pre, by(id)
quietly summarize y1
local m1 = r(mean)
quietly summarize y0
display "TRUE 4-week lift = " %5.2f 100*(`m1'/r(mean)-1) "%"

* 1b. Sanity checks before looking at outcomes
count if treat
bitesti 20000 `r(N)' .5                         // sample ratio mismatch (SRM) test
ttest pre, by(treat)                            // pre-period balance

* 1c. The estimate, then CUPED (use pre-period minutes to cut noise)
regress minutes treat, robust
quietly summarize minutes if treat==0
local ctrl = r(mean)
display "Lift = " %5.2f 100*_b[treat]/`ctrl' "% of control mean"
quietly correlate minutes pre, covariance
local theta = r(cov_12)/r(Var_2)
quietly summarize pre
gen cuped = minutes - `theta'*(pre - r(mean))
regress cuped treat, robust
display "CUPED lift = " %5.2f 100*_b[treat]/`ctrl' "% of control mean"

tempname h
postfile `h' str12 method b lo hi using "output/case1_ci.dta", replace
foreach v in minutes cuped {
    quietly regress `v' treat, robust
    post `h' ("`v'") (100*_b[treat]/`ctrl') (100*(_b[treat]-1.96*_se[treat])/`ctrl') ///
        (100*(_b[treat]+1.96*_se[treat])/`ctrl')
}
postclose `h'
preserve
use "output/case1_ci.dta", clear
gen x = _n
list, noobs
twoway (rcap lo hi x, lcolor(navy) lwidth(thick)) (scatter b x, mcolor(navy) msize(large)), ///
       xlabel(1 "Difference in means" 2 "CUPED", labsize(medium)) xscale(range(.5 2.5)) ///
       yline(0, lcolor(maroon) lpattern(dash)) ylabel(, angle(0)) legend(off) xtitle("") ///
       ytitle("Lift in 4-week minutes (%), 95% CI") ///
       title("Case 1a. Same experiment, narrower interval with CUPED", size(medium))
graph export "output/C1a_cuped.png", width(1600) replace
restore

* 1d. Heterogeneity: free vs premium users
regress minutes i.treat##i.premium, robust

* 1e. Novelty: is the effect fading week by week?
preserve
use "output/case1_panel.dta", clear
tempname g
postfile `g' week b lo hi using "output/case1_weeks.dta", replace
forvalues w = 1/4 {
    quietly summarize minutes if treat==0 & week==`w'
    local c = r(mean)
    quietly regress minutes treat if week==`w', robust
    post `g' (`w') (100*_b[treat]/`c') (100*(_b[treat]-1.96*_se[treat])/`c') (100*(_b[treat]+1.96*_se[treat])/`c')
}
postclose `g'
use "output/case1_weeks.dta", clear
list, noobs
twoway (rcap lo hi week, lcolor(navy)) (connected b week, mcolor(navy) lcolor(navy) msize(large)), ///
       yline(0, lcolor(maroon) lpattern(dash)) xlabel(1/4) ylabel(, angle(0)) legend(off) ///
       xtitle("Week since launch") ytitle("Lift in weekly minutes (%), 95% CI") ///
       title("Case 1b. The lift fades: a novelty effect", size(medium))
graph export "output/C1b_novelty.png", width(1600) replace
restore

* 1f. Power: how many users per arm to detect a 2% lift in 4-week minutes?
quietly summarize minutes if treat==0
local m = r(mean)
local s = r(sd)
power twomeans `m' `=1.02*`m'', sd(`s') power(.8)
quietly regress minutes pre if treat==0
power twomeans `m' `=1.02*`m'', sd(`=e(rmse)') power(.8)


* ----- Case 2. Selection: users who adopt a feature retain more. Did the feature cause it? -----
clear
set seed 562
set obs 20000
gen engage = rnormal()                          // engagement drives adoption AND retention
gen tenure = runiform()*36                      // months as a customer
gen adopt  = runiform() < invlogit(-1 + 1.2*engage + .02*tenure)
gen p0 = invlogit(-.3 + .9*engage + .01*tenure)
gen p1 = invlogit(-.3 + .9*engage + .01*tenure + .25)
gen u  = runiform()
gen retained = cond(adopt, u<p1, u<p0)
gen te = 100*(p1 - p0)
summarize te
local truth = r(mean)
display "TRUE average effect on retention = " %4.1f `truth' " percentage points"

tempname k
postfile `k' str28 method b se using "output/case2_est.dta", replace
quietly regress retained adopt, robust
post `k' ("Naive difference") (100*_b[adopt]) (100*_se[adopt])
quietly teffects ipw (retained) (adopt tenure, logit)
post `k' ("IPW, tenure only") (100*_b[ATE:r1vs0.adopt]) (100*_se[ATE:r1vs0.adopt])
quietly teffects ra (retained engage tenure, logit) (adopt)
post `k' ("Regression adjustment") (100*_b[ATE:r1vs0.adopt]) (100*_se[ATE:r1vs0.adopt])
quietly teffects ipw (retained) (adopt engage tenure, logit)
post `k' ("IPW") (100*_b[ATE:r1vs0.adopt]) (100*_se[ATE:r1vs0.adopt])
quietly teffects aipw (retained engage tenure, logit) (adopt engage tenure, logit)
post `k' ("Doubly robust (AIPW)") (100*_b[ATE:r1vs0.adopt]) (100*_se[ATE:r1vs0.adopt])
postclose `k'

* Overlap: do adopters and non-adopters share a common range of propensity scores?
logit adopt engage tenure
predict ps, pr
twoway (kdensity ps if adopt==1, lcolor(navy) lwidth(medthick)) ///
       (kdensity ps if adopt==0, lcolor(maroon) lwidth(medthick) lpattern(dash)), ///
       legend(order(1 "Adopters" 2 "Non-adopters") rows(1)) ylabel(, angle(0)) ///
       xtitle("Estimated probability of adopting") ytitle("Density") ///
       title("Case 2a. Overlap check for the propensity score", size(medium))
graph export "output/C2a_overlap.png", width(1600) replace

use "output/case2_est.dta", clear
gen lo = b - 1.96*se
gen hi = b + 1.96*se
gen y  = _N - _n + 1
list method b se, noobs
forvalues i = 1/`=_N' {
    local lbl `lbl' `=y[`i']' "`=method[`i']'"
}
twoway (rcap lo hi y, horizontal lcolor(navy)) (scatter y b, mcolor(navy) msize(large)), ///
       xline(`truth', lcolor(maroon) lwidth(medthick) lpattern(dash)) ///
       ylabel(`lbl', angle(0) labsize(small)) yscale(range(.5 5.5)) legend(off) ytitle("") ///
       xtitle("Estimated effect on retention (percentage points)") ///
       title("Case 2b. Controlling for engagement recovers the truth", size(medium)) ///
       note("Dashed line = true effect, known because we simulated the data.")
graph export "output/C2b_estimates.png", width(1800) replace


* ----- Case 3. Difference-in-differences: a price increase in 15 of 40 markets -----
clear
set seed 563
set obs 40
gen market = _n
gen treat  = market <= 15                       // markets that raised the price
gen a      = rnormal(13,1)                      // market size (ln subscribers)
gen g      = rnormal(.004,.001)                 // market-specific growth rate
expand 24
bysort market: gen month = _n
gen post = month >= 13
gen e    = month - 13                           // event time; price rises at e = 0
gen true_eff = 0
replace true_eff = -.010 if treat & e==0
replace true_eff = -.020 if treat & e==1
replace true_eff = -.030 if treat & e>=2
gen price  = 10.99 + treat*post*1.00
gen lnsubs = a + g*month + .01*sin(month/2) + true_eff + rnormal(0,.004)
gen lnrev  = ln(price) + lnsubs
xtset market month

* 3a. Raw trends, normalized to the month before the change
bysort market (month): gen base = lnsubs[12]
gen idx = 100*(lnsubs - base)
preserve
collapse (mean) idx, by(treat month)
twoway (connected idx month if treat==1, lcolor(maroon) mcolor(maroon)) ///
       (connected idx month if treat==0, lcolor(navy) mcolor(navy) lpattern(dash)), ///
       xline(12.5, lcolor(gs10)) ylabel(, angle(0)) xlabel(1(2)24) ///
       legend(order(1 "Raised price (15 markets)" 2 "Did not (25 markets)") rows(1)) ///
       xtitle("Month") ytitle("Subscribers, % vs month 12") ///
       title("Case 3a. Subscribers in treated and control markets", size(medium))
graph export "output/C3a_trends.png", width(1600) replace
restore

* 3b. DiD regression with market and month fixed effects
gen D = treat*post
xtreg lnsubs D i.month, fe vce(cluster market)
local dsubs = _b[D]
xtreg lnrev  D i.month, fe vce(cluster market)
display "Implied elasticity of subscribers to price = " %5.2f `dsubs'/ln(11.99/10.99)

* 3c. Event study: one coefficient per month relative to month 12 (e = -1)
gen ev = cond(treat, e + 12, 11)                // 0..23; base 11 = month before
xtreg lnsubs ib11.ev i.month, fe vce(cluster market)
tempname q
postfile `q' e b lo hi using "output/case3_es.dta", replace
forvalues k = 0/23 {
    if `k'==11 post `q' (-1) (0) (0) (0)
    else post `q' (`k'-12) (100*_b[`k'.ev]) (100*(_b[`k'.ev]-1.96*_se[`k'.ev])) (100*(_b[`k'.ev]+1.96*_se[`k'.ev]))
}
postclose `q'
preserve
use "output/case3_es.dta", clear
twoway (rarea lo hi e, color(navy%20)) (connected b e, lcolor(navy) mcolor(navy)), ///
       yline(0, lcolor(gs10)) xline(-.5, lcolor(maroon) lpattern(dash)) ylabel(, angle(0)) ///
       legend(off) xtitle("Months since price increase") ytitle("Effect on subscribers (%), 95% CI") ///
       title("Case 3b. Event study: flat before, about -3% after", size(medium))
graph export "output/C3b_event_study.png", width(1600) replace
restore


* ----- Case 4. Tariff pass-through: who paid the 25% tariff? -----
clear
set seed 564
set obs 1000
gen product = _n
gen tariffed = product <= 400                   // 400 products hit by a 25% tariff in month 13
gen a = rnormal(3,1)
expand 36
bysort product: gen month = _n
gen e = month - 13
gen ramp = 0
replace ramp = .3  if tariffed & e==0
replace ramp = .6  if tariffed & e==1
replace ramp = .85 if tariffed & e==2
replace ramp = 1   if tariffed & e>=3
gen lnp_border = a + .001*month + rnormal(0,.02)            // price before duty: unchanged
gen lnp_duty   = lnp_border + ln(1.25)*(tariffed & e>=0)    // importer's cost incl. duty
gen lnp_retail = a + .3 + .002*month + .45*ln(1.25)*ramp + rnormal(0,.02)  // shelf price
xtset product month
gen ev = cond(tariffed, e + 12, 11)

tempname r
postfile `r' str12 outcome e b lo hi using "output/case4_es.dta", replace
foreach y in lnp_border lnp_duty lnp_retail {
    quietly xtreg `y' ib11.ev i.month, fe vce(cluster product)
    forvalues k = 0/35 {
        if `k'==11 post `r' ("`y'") (-1) (0) (0) (0)
        else post `r' ("`y'") (`k'-12) (100*_b[`k'.ev]) (100*(_b[`k'.ev]-1.96*_se[`k'.ev])) (100*(_b[`k'.ev]+1.96*_se[`k'.ev]))
    }
}
postclose `r'

* Pass-through = price change / tariff change, using months 3+ after the tariff
gen D = tariffed & e>=3
gen ramp_up = tariffed & inrange(e,0,2)
foreach y in lnp_border lnp_duty lnp_retail {
    quietly xtreg `y' D ramp_up i.month, fe vce(cluster product)
    display "`y': pass-through = " %4.2f _b[D]/ln(1.25) "  (SE " %4.2f _se[D]/ln(1.25) ")"
}

preserve
use "output/case4_es.dta", clear
twoway (connected b e if outcome=="lnp_duty",   lcolor(maroon) mcolor(maroon) msize(small)) ///
       (connected b e if outcome=="lnp_retail", lcolor(navy) mcolor(navy) msize(small)) ///
       (connected b e if outcome=="lnp_border", lcolor(gs8) mcolor(gs8) msize(small) lpattern(dash)), ///
       yline(0, lcolor(gs12)) yline(`=100*ln(1.25)', lcolor(maroon%40) lpattern(dot)) ///
       xline(-.5, lcolor(gs10)) ylabel(, angle(0)) ///
       legend(order(1 "Importer cost incl. duty" 2 "Retail price" 3 "Foreign price before duty") rows(1) size(small)) ///
       xtitle("Months since tariff") ytitle("Change vs untariffed products (log points)") ///
       title("Case 4. Event study of a 25% tariff", size(medium))
graph export "output/C4_passthrough.png", width(1800) replace
restore


* ----- Case 5. Price elasticity: OLS vs instrumental variables -----
clear
set seed 565
set obs 200
gen product = _n
gen a = rnormal(8,1)
gen c = rnormal(2,.5)
expand 52
bysort product: gen week = _n
gen xi  = rnormal(0,.3)                          // demand shock the retailer sees, we don't
gen z   = rnormal(0,.15)                         // cost shock: freight and exchange rate
gen lnmc = c + z
gen lnp  = lnmc + ln(2) + .6*xi + rnormal(0,.05) // price rises when demand is high
gen lnq  = a - 2*lnp + xi + rnormal(0,.1)        // TRUE elasticity = -2
xtset product week

xtreg lnq lnp, fe vce(cluster product)
local b_ols = _b[lnp]
xtreg lnp z, fe vce(cluster product)                 // first stage
test z
xtivreg lnq (lnp = z), fe vce(cluster product)
local b_iv = _b[lnp]
display "OLS elasticity = " %5.2f `b_ols' "   IV elasticity = " %5.2f `b_iv'
display "Optimal markup p/mc = e/(e+1):  IV -> " %4.2f `b_iv'/(`b_iv'+1) ///
        "   OLS -> " cond(`b_ols' > -1, "none (demand looks inelastic: raise price forever)", string(`b_ols'/(`b_ols'+1),"%4.2f"))

* Picture: within-product variation, 20 bins
bysort product: egen mp = mean(lnp)
bysort product: egen mq = mean(lnq)
gen dp = lnp - mp
gen dq = lnq - mq
xtile bin = dp, nq(20)
preserve
collapse (mean) dp dq, by(bin)
twoway (scatter dq dp, mcolor(navy) msize(large)) ///
       (function y = `b_ols'*x, range(-.4 .4) lcolor(navy) lwidth(medthick)) ///
       (function y = `b_iv'*x,  range(-.4 .4) lcolor(maroon) lwidth(medthick) lpattern(dash)), ///
       ylabel(, angle(0)) legend(order(2 "OLS slope" 3 "IV slope (cost shifter)") rows(1)) ///
       xtitle("ln price, deviation from product mean") ytitle("ln quantity, deviation from product mean") ///
       title("Case 5. Raw data say demand is inelastic; IV says elastic", size(medium)) ///
       note("Dots: 20 bins of 10,400 product-weeks. True elasticity = -2.")
graph export "output/C5_elasticity.png", width(1600) replace
restore

log close cases
display "All five cases done. Figures and logs are in output/."
