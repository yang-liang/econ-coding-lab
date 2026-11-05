* =====================================================================
* ECON 561 -- Mock data-science interviews: two business cases
*   Case A (Amazon-style):  Was Prime Day worth it?
*   Case B (Spotify-style): Should we switch to a 3-month free trial?
* Data are simulated and the firms are illustrative.
* Run top to bottom, or paste the blocks from README.md in order.
* =====================================================================

* ----- 0. Setup -----
version 16.0
clear all
set more off
set scheme s1color
capture mkdir output
capture log close mock
log using "output/mock_interviews.log", text replace name(mock)
global data "https://raw.githubusercontent.com/yang-liang/econ-coding-lab/main/data"
* If you downloaded the two csv files into this folder, use instead:  global data "."

* ----- Case A. Prime Day: load and look -----
import delimited "$data/primeday.csv", clear varnames(1)
describe
tab category deal
* One row = one product on one day. day 0 and day 1 are Prime Day.
* deal = 1 if the product got a Prime Day discount (20% off list price).

* ----- A1. The number the marketing team reports -----
summarize units if deal & day <= -8, meanonly
local normal = r(mean)
summarize units if deal & inlist(day, 0, 1), meanonly
local prime = r(mean)
display "Deal products: " %4.1f `normal' " units/day normally, " %4.1f `prime' ///
        " on Prime Day.  Naive lift = " %3.0f 100*(`prime'/`normal' - 1) "%"

* ----- A2. Look before you estimate: sales relative to normal, by day -----
* Index every product to its own normal level (days -30 to -8), so big and
* small products count equally: index = 1 means a normal day.
bysort product: egen normal_units = mean(cond(day <= -8, units, .))
gen idx_units  = units / normal_units
gen profit     = units * (price - unit_cost)
gen idx_profit = profit / (normal_units * (list_price - unit_cost))
preserve
collapse (mean) idx_units, by(category deal day)
twoway (line idx_units day if deal == 1, lcolor(maroon) lwidth(medthick)) ///
       (line idx_units day if deal == 0, lcolor(gs9) lwidth(medthick)), ///
       by(category, note("") title("A1. Sales relative to a normal day", size(medium)) rows(1)) ///
       xline(0 1, lcolor(gs13) lwidth(vthick)) yline(1, lpattern(dash) lcolor(gs10)) ///
       xtitle("Days from Prime Day") ytitle("Sales / normal daily sales") ylabel(, angle(0)) ///
       legend(order(1 "Products with a deal" 2 "Products without a deal") rows(1))
graph export "output/A1_sales_index.png", width(1600) replace
restore

* ----- A3. Event study: the deal effect day by day -----
* Products without a deal are the comparison group: they show what Prime Day
* traffic alone does. Compare each day with normal days (ev = 0).
* The coefficient on deal x day is the extra sales from the deal, measured in
* "normal days of sales".
gen ev = cond(day <= -8, 0, day + 8)           // ev 1..38 = days -7..30
capture postclose es
postfile es str20 category str7 outcome day b lo hi using "output/A_event_study.dta", replace
foreach c in "Household essentials" "Electronics" {
    foreach y in units profit {
        quietly regress idx_`y' i.deal##i.ev if category == "`c'", vce(cluster product)
        forvalues k = 1/38 {
            post es ("`c'") ("`y'") (`k' - 8) (_b[1.deal#`k'.ev]) ///
                 (_b[1.deal#`k'.ev] - 1.96*_se[1.deal#`k'.ev]) (_b[1.deal#`k'.ev] + 1.96*_se[1.deal#`k'.ev])
        }
    }
}
postclose es
preserve
use "output/A_event_study.dta", clear
keep if outcome == "units" & day <= 20
twoway (rcap lo hi day, lcolor(gs10)) (scatter b day, mcolor(maroon) msize(small)), ///
       by(category, note("") title("A2. Extra sales from the deal (vs. products without one)", size(medium)) rows(1)) ///
       yline(0, lcolor(black)) xline(-0.5 1.5, lpattern(dash) lcolor(gs12)) ///
       xtitle("Days from Prime Day") ytitle("Extra sales, in normal days") ylabel(, angle(0)) ///
       legend(order(2 "Estimate" 1 "95% CI") rows(1))
graph export "output/A2_event_study.png", width(1600) replace
restore

* ----- A4. Add it up: how much is new demand, and does it make money? -----
* Sum the daily effects over three windows:
*   spike     = days 0-1 (Prime Day itself)
*   before    = days -7 to -1 (customers wait for the deal)
*   after     = days 2 to 15 (customers stocked up)
local spike  "1.deal#8.ev + 1.deal#9.ev"
local before "1.deal#1.ev"
forvalues k = 2/7 {
    local before "`before' + 1.deal#`k'.ev"
}
local after "1.deal#10.ev"
forvalues k = 11/23 {
    local after "`after' + 1.deal#`k'.ev"
}
capture postclose sums
postfile sums str20 category str7 outcome str7 window b se using "output/A_sums.dta", replace
foreach c in "Household essentials" "Electronics" {
    foreach y in units profit {
        quietly regress idx_`y' i.deal##i.ev if category == "`c'", vce(cluster product)
        foreach w in spike before after {
            quietly lincom ``w''
            post sums ("`c'") ("`y'") ("`w'") (r(estimate)) (r(se))
        }
        quietly lincom `spike' + `before' + `after'
        post sums ("`c'") ("`y'") ("net") (r(estimate)) (r(se))
    }
}
postclose sums
preserve
use "output/A_sums.dta", clear
format b se %6.2f
list category outcome window b se, sepby(category outcome) noobs
restore

* ----- A5. The chart for your manager -----
preserve
use "output/A_sums.dta", clear
keep if outcome == "units"
gen order = 1*(window=="spike") + 2*(window=="before") + 3*(window=="after") + 4*(window=="net")
label define w 1 "Prime Day spike" 2 "Waited (days -7 to -1)" 3 "Stocked up (days 2-15)" 4 "Net new sales"
label values order w
graph bar b, over(order, label(labsize(small))) over(category) asyvars ///
       bar(1, color(navy)) bar(2, color(gs10)) bar(3, color(gs7)) bar(4, color(maroon)) ///
       blabel(bar, format(%4.1f) size(small)) yline(0) ///
       ytitle("Extra units, in normal days of sales") ylabel(, angle(0)) ///
       title("A3. Most essentials sales were borrowed; electronics sales were new", size(medium)) ///
       legend(rows(2) size(small))
graph export "output/A3_manager_chart.png", width(1600) replace
restore

* ----- Case B. Free-trial test: load and check the experiment -----
import delimited "$data/free_trial_test.csv", clear varnames(1)
describe
* One row = one visitor to the sign-up page, randomly shown a 1-month or a
* 3-month free trial. first_paid_month / last_paid_month are missing if the
* visitor never paid. Price is $6/month for students and $11 for everyone else.
gen three = arm == "3-month"
* Sample ratio check: a 50/50 split should give about 20,000 per arm
tab arm
quietly count if three
display "Sample ratio test p-value = " %5.3f 2*binomial(_N, min(r(N), _N - r(N)), .5)
* Balance: the share of students should be the same in both arms
tab student arm, col chi2

* ----- B1. The funnel: the metric that misleads -----
gen paid = first_paid_month < .
tabstat trial paid, by(arm) format(%5.3f) nototal
* Conversion among visitors who started a trial (the dashboard number):
tabstat paid if trial, by(arm) format(%5.3f) nototal
* The 3-month arm converts a smaller share of trial starters, but it brings in
* more starters. Who starts a trial is affected by the treatment, so compare
* ALL randomized visitors (intent to treat), never only the starters.

* ----- B2. Revenue per visitor, month by month -----
forvalues m = 1/24 {
    gen rev`m' = price * max(0, min(last_paid_month, `m') - first_paid_month + 1)
    replace rev`m' = 0 if missing(first_paid_month)
}
preserve
collapse (mean) rev1-rev24, by(arm student)
reshape long rev, i(arm student) j(month)
label define st 0 "Non-students" 1 "Students"
label values student st
twoway (line rev month if arm == "3-month", lcolor(maroon) lwidth(medthick)) ///
       (line rev month if arm == "1-month", lcolor(navy) lwidth(medthick) lpattern(dash)), ///
       by(student, note("") title("B1. Cumulative revenue per visitor", size(medium)) rows(1)) ///
       xtitle("Months since sign-up page") ytitle("Dollars per visitor") ylabel(, angle(0)) ///
       legend(order(1 "3-month trial" 2 "1-month trial") rows(1))
graph export "output/B1_revenue_curves.png", width(1600) replace
restore

* ----- B3. The effect with confidence intervals -----
foreach m in 6 12 24 {
    quietly regress rev`m' i.three##i.student, vce(robust)
    quietly lincom 1.three
    local ns = r(estimate)
    local ns_se = r(se)
    quietly lincom 1.three + 1.three#1.student
    display "Month " %2.0f `m' ":  effect of 3-month trial on revenue per visitor:  " ///
            "non-students " %6.2f `ns' " (se " %4.2f `ns_se' ")   students " %6.2f r(estimate) " (se " %4.2f r(se) ")"
}

* ----- B4. The decision table -----
* Revenue per visitor after 24 months under three policies
quietly summarize rev24 if !three & !student, meanonly
local a0 = r(mean)
quietly summarize rev24 if  three & !student, meanonly
local b0 = r(mean)
quietly summarize rev24 if !three &  student, meanonly
local a1 = r(mean)
quietly summarize rev24 if  three &  student, meanonly
local b1 = r(mean)
quietly summarize student, meanonly
local s = r(mean)
display "Everyone gets 1 month:               $" %5.2f (1-`s')*`a0' + `s'*`a1'
display "Everyone gets 3 months:              $" %5.2f (1-`s')*`b0' + `s'*`b1'
display "3 months for students, 1 for others: $" %5.2f (1-`s')*`a0' + `s'*`b1'

log close mock
display "Both cases done. Figures and the log are in output/."
