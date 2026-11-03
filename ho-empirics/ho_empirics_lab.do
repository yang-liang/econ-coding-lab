* ECON 561: Does the Heckscher-Ohlin model survive the data?  (75-minute lab)
* Identical code blocks appear in README.md with the theory and the questions.
* Run one numbered block at a time.  Needs internet for section 0.

* ----- 0. Setup and data -----
version 16.0
clear all
set more off
set scheme s1color
capture mkdir output
capture log close holab
log using "output/ho_lab.log", text replace name(holab)

* Penn World Table 10.01: capital stocks, workers, wages for 183 countries (1950-2019)
capture confirm file "pwt1001.dta"
if _rc copy "https://dataverse.nl/api/access/datafile/354098" "pwt1001.dta"

* Trade by factor-intensity group (built from CEPII BACI with build_ho_trade.do)
global trade "https://raw.githubusercontent.com/yang-liang/econ-coding-lab/main/data/ho_trade_intensity.csv"
* If you downloaded the csv instead, use:  global trade "ho_trade_intensity.csv"

* NBER-CES Manufacturing Database: 473 US industries, 1958-2018
global nberces "https://data.nber.org/nberces/nberces5818v1/nberces5818v1_n1997.dta"


* ----- 1. Who is capital abundant? (Penn World Table) -----
use countrycode country year cn emp pop hc labsh cgdpo using "pwt1001.dta", clear
rename countrycode iso3
gen double kl   = cn/emp/1000                       // capital per worker, $1,000 (2017 PPP)
gen double wage = labsh*cgdpo/emp/1000              // labor income per worker, $1,000
bysort year: egen double world_k = total(cn*(emp<.)) if cn<. & emp<.
bysort year: egen double world_l = total(emp)        if cn<. & emp<.
gen double rel_kl = kl/(world_k/world_l/1000)       // 1 = world average K/L
gen ln_kl     = ln(kl)
gen ln_rel_kl = ln(rel_kl)
gen ln_wage   = ln(wage)
label var rel_kl "K/L relative to world (world = 1)"
save "output/pwt_clean.dta", replace

* Exhibit 1: relative capital abundance in 2015
graph hbar rel_kl if year==2015 & inlist(iso3,"USA","DEU","JPN","KOR","GBR","MEX","BRA") | ///
    year==2015 & inlist(iso3,"CHN","TUR","IDN","IND","VNM","BGD","NGA","ETH"), ///
    over(country, sort(1) descending label(labsize(small))) ///
    yline(1, lcolor(maroon) lpattern(dash)) blabel(bar, format(%4.1f) size(vsmall)) ///
    ytitle("Capital per worker relative to world average") ///
    title("Exhibit 1. Relative factor endowments, 2015", size(medium)) ///
    note("Source: Penn World Table 10.01 (cn/emp). Dashed line = world average.")
graph export "output/E01_endowments_2015.png", width(1800) replace

* Exhibit 2: endowments move over time
twoway (line rel_kl year if iso3=="USA", lwidth(medthick)) ///
       (line rel_kl year if iso3=="KOR", lwidth(medthick)) ///
       (line rel_kl year if iso3=="CHN", lwidth(medthick)) ///
       (line rel_kl year if iso3=="MEX", lwidth(medthick) lpattern(dash)) ///
       (line rel_kl year if iso3=="IND", lwidth(medthick) lpattern(dash)) ///
       (line rel_kl year if iso3=="VNM", lwidth(medthick) lpattern(dash)) ///
       if year>=1970, yscale(log) ylabel(.1 .25 .5 1 2 4, angle(0)) yline(1, lcolor(gs10)) ///
       legend(order(1 "USA" 2 "Korea" 3 "China" 4 "Mexico" 5 "India" 6 "Vietnam") rows(1) size(small)) ///
       ytitle("K/L relative to world (log scale)") xtitle("") ///
       title("Exhibit 2. Endowments are not fixed: capital deepening, 1970-2019", size(medium))
graph export "output/E02_endowments_over_time.png", width(1800) replace


* ----- 2. Factor price equalization: do trading countries pay the same wage? -----
* Exhibit 3: wage levels vs endowments, 2019
gen lab3 = ""
foreach c in USA DEU JPN KOR CHN MEX IND VNM BGD BRA TUR IDN {
    replace lab3 = iso3 if iso3=="`c'"
}
twoway (scatter ln_wage ln_rel_kl if year==2019 & pop>=1, msize(small) mcolor(navy%40)) ///
       (scatter ln_wage ln_rel_kl if year==2019 & pop>=1 & lab3!="", msize(small) mcolor(maroon) ///
            mlabel(lab3) mlabsize(vsmall) mlabcolor(maroon)) ///
       (lfit ln_wage ln_rel_kl if year==2019 & pop>=1, lcolor(black)), ///
       ylabel(, angle(0)) legend(off) xtitle("ln K/L relative to world") ytitle("ln labor income per worker ($1,000 PPP)") ///
       title("Exhibit 3. Factor prices are far from equal", size(medium)) ///
       note("FPE predicts a flat line: one world wage. Each dot is a country (population 1m+).")
graph export "output/E03_fpe_wages.png", width(1800) replace
regress ln_wage ln_rel_kl if year==2019 & pop>=1, robust

* Exhibit 4: has globalization compressed wage gaps?  Fixed panel of countries since 1970
preserve
keep if year>=1970 & ln_wage<. & pop>=1
bysort iso3: gen nyrs = _N
keep if nyrs==50
collapse (sd) sd_lnw=ln_wage (p90) p90=ln_wage (p10) p10=ln_wage (count) n=ln_wage, by(year)
gen gap9010 = exp(p90-p10)
list year n sd_lnw gap9010 if inlist(year,1970,1980,1990,2000,2010,2019), noobs
twoway (line gap9010 year, lwidth(medthick)), ///
       ytitle("90th / 10th percentile wage ratio") ylabel(, angle(0)) xtitle("") ///
       title("Exhibit 4. Cross-country wage gap, fixed set of countries", size(medium)) ///
       note("Ratio of labor income per worker, 90th vs 10th percentile country.")
graph export "output/E04_fpe_dispersion.png", width(1800) replace
restore


* ----- 3. The HO theorem: do capital-abundant countries export capital-intensive goods? -----
import delimited "$trade", clear
keep if inlist(group,"CAP","LAB")
reshape wide exports imports, i(iso3 year) j(group) string
merge 1:1 iso3 year using "output/pwt_clean.dta", keep(match) nogen ///
    keepusing(country pop kl rel_kl ln_kl ln_rel_kl wage ln_wage)
gen mx        = exportsCAP + exportsLAB
gen cap_share = exportsCAP/mx                                   // capital-intensive share of mfg exports
gen nx_cap    = (exportsCAP-importsCAP)/(exportsCAP+importsCAP) // net export ratio, -1 to 1
gen nx_lab    = (exportsLAB-importsLAB)/(exportsLAB+importsLAB)
keep if pop>=1 & mx>=1000                                       // 1m+ people, $1bn+ mfg exports
gen lab3 = ""
foreach c in USA DEU JPN KOR CHN MEX IND VNM BGD BRA TUR IDN PAK ITA {
    replace lab3 = iso3 if iso3=="`c'"
}
encode iso3, gen(cid)
save "output/ho_panel.dta", replace

* Exhibit 5: export composition vs endowment, 2015
twoway (scatter cap_share ln_rel_kl if year==2015, msize(small) mcolor(navy%40)) ///
       (scatter cap_share ln_rel_kl if year==2015 & lab3!="", msize(small) mcolor(maroon) ///
            mlabel(lab3) mlabsize(vsmall) mlabcolor(maroon)) ///
       (lfit cap_share ln_rel_kl if year==2015, lcolor(black)), ///
       legend(off) ylabel(0(.2)1, angle(0)) xtitle("ln K/L relative to world") ///
       ytitle("Capital-intensive share of manufactured exports") ///
       title("Exhibit 5. Capital-abundant countries export capital-intensive goods", size(medium)) ///
       note("Capital-intensive: chemicals, plastics, paper, metals, machinery, vehicles, instruments." ///
            "Labor-intensive: leather, textiles, apparel, footwear, furniture, toys. Source: BACI 2015, PWT.")
graph export "output/E05_ho_export_share.png", width(1800) replace
regress cap_share ln_rel_kl if year==2015, robust

* Exhibit 6: the cleaner test uses net exports (exports minus imports) in each group
twoway (scatter nx_cap ln_rel_kl if year==2015, msize(small) mcolor(navy%50)) ///
       (lfit nx_cap ln_rel_kl if year==2015, lcolor(navy) lwidth(medthick)) ///
       (scatter nx_lab ln_rel_kl if year==2015, msize(small) msymbol(Th) mcolor(maroon%60)) ///
       (lfit nx_lab ln_rel_kl if year==2015, lcolor(maroon) lwidth(medthick) lpattern(dash)), ///
       yline(0, lcolor(gs10)) ylabel(-1(.5)1, angle(0)) ///
       legend(order(1 "Capital-intensive goods" 3 "Labor-intensive goods") rows(1)) ///
       xtitle("ln K/L relative to world") ytitle("Net export ratio (X-M)/(X+M)") ///
       title("Exhibit 6. Net trade by factor content of goods, 2015", size(medium))
graph export "output/E06_ho_net_exports.png", width(1800) replace
regress nx_cap ln_rel_kl if year==2015, robust
regress nx_lab ln_rel_kl if year==2015, robust

* Exhibit 7: does the HO slope hold every year?
tempname h
postfile `h' year b lo hi n using "output/ho_slopes.dta", replace
foreach y in 1995 2000 2005 2010 2015 {
    quietly regress cap_share ln_rel_kl if year==`y', robust
    post `h' (`y') (_b[ln_rel_kl]) (_b[ln_rel_kl]-invttail(e(df_r),.025)*_se[ln_rel_kl]) ///
        (_b[ln_rel_kl]+invttail(e(df_r),.025)*_se[ln_rel_kl]) (e(N))
}
postclose `h'
preserve
use "output/ho_slopes.dta", clear
list, noobs
twoway (rcap lo hi year, lcolor(navy)) (scatter b year, mcolor(navy) msize(large)), ///
       yline(0, lcolor(maroon) lpattern(dash)) xlabel(1995(5)2015) ylabel(, angle(0)) legend(off) ///
       ytitle("Slope of K-intensive export share on ln K/L") xtitle("") ///
       title("Exhibit 7. The HO slope, year by year (95% CI)", size(medium))
graph export "output/E07_ho_slope_by_year.png", width(1800) replace
restore


* ----- 4. Rybczynski: when K/L grows, does the output mix shift toward K-intensive goods? -----
* Exhibit 8: trajectories of export composition
twoway (connected cap_share year if iso3=="CHN", lwidth(medthick)) ///
       (connected cap_share year if iso3=="KOR", lwidth(medthick)) ///
       (connected cap_share year if iso3=="VNM", lwidth(medthick)) ///
       (connected cap_share year if iso3=="IND", lwidth(medthick) lpattern(dash)) ///
       (connected cap_share year if iso3=="BGD", lwidth(medthick) lpattern(dash)) ///
       (connected cap_share year if iso3=="USA", lwidth(medthick) lpattern(dash)), ///
       ylabel(0(.2)1, angle(0)) xlabel(1995(5)2015) ///
       legend(order(1 "China" 2 "Korea" 3 "Vietnam" 4 "India" 5 "Bangladesh" 6 "USA") rows(1) size(small)) ///
       ytitle("Capital-intensive share of mfg exports") xtitle("") ///
       title("Exhibit 8. Export mix as countries accumulate capital", size(medium))
graph export "output/E08_rybczynski_paths.png", width(1800) replace

* Exhibit 9: long difference 1995-2015, one dot per country
preserve
keep if inlist(year,1995,2015)
bysort iso3 (year): keep if _N==2
bysort iso3 (year): gen d_share = cap_share[2]-cap_share[1]
bysort iso3 (year): gen d_lnkl  = ln_kl[2]-ln_kl[1]
keep if year==2015
twoway (scatter d_share d_lnkl, msize(small) mcolor(navy%40)) ///
       (scatter d_share d_lnkl if lab3!="", msize(small) mcolor(maroon) mlabel(lab3) mlabsize(vsmall) mlabcolor(maroon)) ///
       (lfit d_share d_lnkl, lcolor(black)), ///
       yline(0, lcolor(gs10)) ylabel(, angle(0)) legend(off) ///
       xtitle("Change in ln K/L, 1995-2015") ytitle("Change in K-intensive export share") ///
       title("Exhibit 9. Rybczynski in long differences", size(medium))
graph export "output/E09_rybczynski_longdiff.png", width(1800) replace
regress d_share d_lnkl, robust
restore

* Same idea with all five years: country and year fixed effects
xtset cid year
xtreg cap_share ln_kl i.year, fe vce(cluster cid)


* ----- 5. Factor intensity is a property of technology (US manufacturing) -----
use "$nberces", clear
gen naics3 = floor(naics/1000)
label define n3 311 "Food" 312 "Beverage & tobacco" 313 "Textile mills" 314 "Textile products" ///
    315 "Apparel" 316 "Leather" 321 "Wood" 322 "Paper" 323 "Printing" 324 "Petroleum & coal" ///
    325 "Chemicals" 326 "Plastics & rubber" 327 "Nonmetallic minerals" 331 "Primary metals" ///
    332 "Fabricated metals" 333 "Machinery" 334 "Computers & electr." 335 "Electrical equipment" ///
    336 "Transportation equip." 337 "Furniture" 339 "Miscellaneous"
label values naics3 n3
gen kl         = cap/emp                       // real capital per worker, $1,000 (1997 $)
gen skill      = (emp-prode)/emp               // nonproduction share of employment
save "output/nberces_clean.dta", replace

* Exhibit 10: capital per worker by sector, 2015
preserve
keep if year==2015
collapse (sum) cap emp, by(naics3)
gen kl = cap/emp
graph hbar kl, over(naics3, sort(1) descending label(labsize(small))) ///
    blabel(bar, format(%4.0f) size(vsmall)) ytitle("Real capital per worker ($1,000)") ///
    title("Exhibit 10. Capital per worker by US manufacturing sector, 2015", size(medium))
graph export "output/E10_kl_by_sector.png", width(1800) replace
restore

* Exhibit 11: the ranking is stable over 40 years (no factor-intensity reversals in time)
preserve
keep if inlist(year,1970,2010)
keep naics year kl emp
reshape wide kl emp, i(naics) j(year)
gen ln70 = ln(kl1970)
gen ln10 = ln(kl2010)
spearman kl1970 kl2010
local rho : display %4.2f r(rho)
twoway (scatter ln10 ln70, msize(vsmall) mcolor(navy%40)) ///
       (function y=x, range(1 7) lcolor(maroon) lpattern(dash)), ///
       ylabel(, angle(0)) legend(off) xtitle("ln capital per worker, 1970") ytitle("ln capital per worker, 2010") ///
       title("Exhibit 11. Capital-intensive industries stay capital intensive", size(medium)) ///
       note("Each dot is a 6-digit industry. Dashed = 45-degree line. Spearman rank correlation = `rho'.")
graph export "output/E11_kl_rank_stability.png", width(1800) replace
restore


* ----- 6. Stolper-Samuelson: skill premium and goods prices -----
* Exhibit 12: the skill premium and relative skilled employment both rose after 1980
preserve
collapse (sum) emp prode pay prodw, by(year)
gen rel_wage = ((pay-prodw)/(emp-prode)) / (prodw/prode)
gen rel_emp  = (emp-prode)/prode
list year rel_wage rel_emp if inlist(year,1960,1970,1980,1990,2000,2010,2018), noobs
twoway (line rel_wage year, lwidth(medthick)) ///
       (line rel_emp year, yaxis(2) lwidth(medthick) lpattern(dash)), ///
       xline(1980, lcolor(gs10)) ylabel(, angle(0)) xtitle("") ///
       ytitle("Nonproduction / production wage", axis(1)) ytitle("Nonproduction / production workers", axis(2)) ///
       legend(order(1 "Relative wage (left)" 2 "Relative employment (right)") rows(1)) ///
       title("Exhibit 12. US manufacturing: price and quantity of skill both rose", size(medium))
graph export "output/E12_skill_premium.png", width(1800) replace
restore

* Exhibit 13: the Lawrence-Slaughter price test, 1979-1999
* SS: if trade raised the skill premium, skill-intensive goods' prices must have risen relative
* to unskilled-intensive goods' prices. Effective price adds TFP growth (Leamer 1998).
preserve
keep if inlist(year,1979,1999)
keep naics naics3 year piship tfp5 skill emp
reshape wide piship tfp5 skill emp, i(naics) j(year)
gen dlnp   = 100*(ln(piship1999)-ln(piship1979))
gen dlneff = dlnp + 100*(ln(tfp51999)-ln(tfp51979))
drop if dlnp==. | skill1979==.
twoway (scatter dlnp skill1979 [aw=emp1979] if naics3!=334, msymbol(Oh) mcolor(navy%40)) ///
       (scatter dlnp skill1979 [aw=emp1979] if naics3==334, msymbol(Oh) mcolor(orange)) ///
       (lfit dlnp skill1979 [aw=emp1979], lcolor(gs8) lpattern(dash)) ///
       (lfit dlnp skill1979 [aw=emp1979] if naics3!=334, lcolor(navy) lwidth(medthick)), ///
       legend(order(2 "Computers & electronics" 3 "Fit, all" 4 "Fit, excl. computers") rows(1) size(vsmall)) ///
       ylabel(, angle(0)) xtitle("Nonproduction share of employment, 1979") ytitle("Price change, 1979-99 (log points)") ///
       title("Raw goods prices", size(medium)) name(ss1, replace)
twoway (scatter dlneff skill1979 [aw=emp1979], msymbol(Oh) mcolor(maroon%40)) ///
       (lfit dlneff skill1979 [aw=emp1979], lcolor(maroon) lwidth(medthick)), ///
       ylabel(, angle(0)) legend(off) xtitle("Nonproduction share of employment, 1979") ytitle("Price + TFP change (log points)") ///
       title("Effective prices (price + TFP)", size(medium)) name(ss2, replace)
graph combine ss1 ss2, cols(2) xsize(12) ysize(5.5) iscale(.8) ///
    title("Exhibit 13. Did skill-intensive goods get relatively more expensive?", size(medium)) ///
    note("Each circle is a 6-digit industry, sized by 1979 employment.")
graph export "output/E13_ss_price_test.png", width(2200) replace
regress dlnp   skill1979 [aw=emp1979], robust
regress dlnp   skill1979 [aw=emp1979] if naics3!=334, robust      // drop computers
regress dlneff skill1979 [aw=emp1979], robust
regress dlneff skill1979 [aw=emp1979] if naics3!=334, robust
restore

* Exhibit 14: skill upgrading happened inside almost every industry
preserve
keep if inlist(year,1979,1999)
keep naics year skill emp
reshape wide skill emp, i(naics) j(year)
gen up = skill1999 > skill1979 if skill1999<. & skill1979<.
summarize up [aw=emp1979]
local pct : display %3.0f 100*r(mean)
twoway (scatter skill1999 skill1979 [aw=emp1979], msymbol(Oh) mcolor(navy%40)) ///
       (function y=x, range(0 .8) lcolor(maroon) lpattern(dash)), ///
       ylabel(, angle(0)) legend(off) xtitle("Nonproduction share, 1979") ytitle("Nonproduction share, 1999") ///
       title("Exhibit 14. Skill upgrading within industries, 1979-1999", size(medium)) ///
       note("`pct'% of employment is in industries above the 45-degree line." ///
            "SS predicts the opposite: when skilled labor gets dearer, every industry should use less of it.")
graph export "output/E14_within_upgrading.png", width(1800) replace
restore

log close holab
display "Lab complete. Figures and data are in output/."
