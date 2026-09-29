import http from 'k6/http';
import { arrivalScenario, baseThresholds, ok, randomInt, wcmHeaders } from './lib/common.js';

const BASE = (__ENV.WCM_BASE_URL || 'http://127.0.0.1:8087').replace(/\/$/, '');
const API = `${BASE}/api/wcm/v0`;
const PEAK = Number(__ENV.LOAD_PEAK_RPS || 50);

// Все запросы к /api/wcm/* обязаны нести X-WCM-Client, иначе FrontendAccessFilter
// отвечает 403 и сценарий ничего не нагружает.
function get(url) {
  return http.get(url, { headers: wcmHeaders() });
}

const COUNTRIES = ['RUS', 'USA', 'CHN', 'DEU', 'AUS', 'GBR', 'IND', 'FRA'];
const YEARS = ['2022', '2023', '2024'];

export const options = {
  scenarios: {
    country_all: arrivalScenario('countryAll', PEAK * 0.1, { endpoint: 'country_all' }),
    reserves_country: arrivalScenario('reservesCountry', PEAK * 0.1, { endpoint: 'reserves_country' }),
    reserves_year: arrivalScenario('reservesYear', PEAK * 0.1, { endpoint: 'reserves_year' }),
    gdp_country: arrivalScenario('gdpCountry', PEAK * 0.1, { endpoint: 'gdp_country' }),
    gdp_year: arrivalScenario('gdpYear', PEAK * 0.1, { endpoint: 'gdp_year' }),
    debt_country: arrivalScenario('debtCountry', PEAK * 0.1, { endpoint: 'debt_country' }),
    debt_gross_country: arrivalScenario('debtGrossCountry', PEAK * 0.1, { endpoint: 'debt_gross_country' }),
    debt_year: arrivalScenario('debtYear', PEAK * 0.1, { endpoint: 'debt_year' }),
    money_supply_country: arrivalScenario('moneySupplyCountry', PEAK * 0.1, { endpoint: 'money_supply_country' }),
    money_supply_year: arrivalScenario('moneySupplyYear', PEAK * 0.1, { endpoint: 'money_supply_year' }),
  },
  thresholds: baseThresholds(),
};

function country() {
  return COUNTRIES[randomInt(0, COUNTRIES.length - 1)];
}

function year() {
  return YEARS[randomInt(0, YEARS.length - 1)];
}

export function countryAll() {
  ok(get(`${API}/country/all`), 'country/all');
}

export function reservesCountry() {
  ok(get(`${API}/international-reserve/country/${country()}`), 'international-reserve/country');
}

export function reservesYear() {
  ok(get(`${API}/international-reserve/year/${year()}`), 'international-reserve/year');
}

export function gdpCountry() {
  ok(get(`${API}/gross-domestic-product/country/${country()}`), 'gdp/country');
}

export function gdpYear() {
  ok(get(`${API}/gross-domestic-product/year/${year()}`), 'gdp/year');
}

export function debtCountry() {
  ok(get(`${API}/debt/country/${country()}`), 'debt/country');
}

export function debtGrossCountry() {
  ok(get(`${API}/debt/debt-gross/country/${country()}`), 'debt/debt-gross/country');
}

export function debtYear() {
  ok(get(`${API}/debt/year/${year()}`), 'debt/year');
}

export function moneySupplyCountry() {
  ok(get(`${API}/money-supply/country/${country()}`), 'money-supply/country');
}

export function moneySupplyYear() {
  ok(get(`${API}/money-supply/year/${year()}`), 'money-supply/year');
}
