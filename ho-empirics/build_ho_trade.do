* ECON 561: build the HO lab trade file (instructor only; students never run this)
* Input : CEPII BACI HS92 bilateral flows (1995, 2000, 2005, 2010, 2015), values in $1,000
* Output: data/ho_trade_intensity.csv, one row per country x year x factor-intensity group
* Run from the folder that holds this do-file.

version 16.0
clear all
set more off

global baci "G:\My Drive\Class\International Economics\archive\ECON360\legacy_sorted\in_person_or_historical_mixed"

* ----- 1. Country codes (BACI numeric code -> ISO3) -----
import delimited "$baci\2021_undated\data_code\primary\archive_360\country_codes_V202102.csv", clear
keep country_code iso_3digit_alpha country_name_abbreviation
rename (country_code iso_3digit_alpha country_name_abbreviation) (code iso3 name)
tempfile codes
save `codes'

* ----- 2. HS chapter -> factor-intensity group -----
* LAB = labor-intensive manufactures, CAP = capital-intensive manufactures,
* NAT = natural-resource goods (food, fuels, minerals, wood), OTH = everything else.
capture program drop classify
program define classify
    gen int ch = floor(k/10000)
    gen str3 group = "OTH"
    replace group = "LAB" if inrange(ch,41,43) | ch==46 | inrange(ch,50,67) | inrange(ch,94,96)
    replace group = "CAP" if inrange(ch,28,40) | inrange(ch,47,49) | inrange(ch,72,92)
    replace group = "NAT" if inrange(ch,1,27) | inrange(ch,44,45)
end

* ----- 3. Exports and imports by country, year, group -----
tempfile all
local first 1
foreach y in 1995 2000 2005 2010 2015 {
    local folder "`y'_undated"
    if `y' == 1995 local folder "undated"
    use "$baci\\`folder'\data_code\primary\archive_360\HS92_`y'.dta", clear
    classify
    preserve
        collapse (sum) exports=v, by(t i group)
        rename i code
        tempfile ex
        save `ex'
    restore
    collapse (sum) imports=v, by(t j group)
    rename j code
    merge 1:1 t code group using `ex', nogen
    if `first' == 0 append using `all'
    save `all', replace
    local first 0
}

* ----- 4. Attach ISO3 codes; BACI uses 251 France, 699 India, 842 USA, etc. -----
merge m:1 code using `codes', keep(match) nogen
rename t year
foreach v in exports imports {
    replace `v' = 0 if missing(`v')
    replace `v' = `v'/1000      // $ millions
}
* A few ISO3 codes have two BACI codes (e.g., a territory reported before and after a code change)
duplicates tag iso3 year group, gen(dup)
tab iso3 if dup>0
collapse (sum) exports imports (first) name, by(iso3 year group)
order iso3 name year group exports imports
sort iso3 year group
label var exports "Exports, $ millions (BACI HS92)"
label var imports "Imports, $ millions (BACI HS92)"
export delimited iso3 name year group exports imports using "data/ho_trade_intensity.csv", replace
display "Rows written: " _N
