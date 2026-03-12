#!/usr/bin/env python3
"""
Umm al-Qura calendar computation using Skyfield.

Implements the astronomical rules documented by R.H. van Gent for
determining the first day of each Hijri month, then compares the
results against the van Gent reference dataset.

Eras:
  Era 2 (1392-1419 AH): conjunction-based rule
  Era 3 (1420-1422 AH): moonset-after-sunset only
  Era 4 (1423+ AH):     conjunction before sunset AND moonset after sunset

Usage:
    python umm_al_qura.py [--era ERA] [--verbose] [--year YEAR]

    --era ERA       Which era to test: 2, 3, 4, or "all" (default: 4)
    --verbose       Print details for every month
    --year YEAR     Test only a specific Hijri year
    --failures      Print only failures

Reference:
    R.H. van Gent, "The Umm al-Qura Calendar of Saudi Arabia"
    https://webspace.science.uu.nl/~gent0113/islam/ummalqura_rules.htm
"""

import argparse
import csv
import os
import sys
from datetime import date, timedelta
from pathlib import Path

from skyfield.api import load, wgs84
from skyfield import almanac
from skyfield.almanac import find_discrete, moon_phases


# ── Constants ─────────────────────────────────────────────────────────────────

# Great Mosque of Mecca (al-Masjid al-Haram)
MECCA_LAT = 21.4225
MECCA_LON = 39.8262
MECCA_ELEV_M = 277.0

# Mean synodic month (days)
MEAN_SYNODIC = 29.530588853

# Hijri epoch seed (calibrated to reproduce the 29th-day estimation)
HIJRI_EPOCH_JDN = 1_948_410

# Era boundaries
ERA2_START = 1392
ERA3_START = 1420
ERA4_START = 1423

# Mecca is permanently UTC+3
MECCA_UTC_OFFSET_H = 3


# ── Skyfield setup ────────────────────────────────────────────────────────────

def setup_skyfield():
    """Load ephemeris and set up Mecca observer."""
    # Use the same DE440s ephemeris as our Elixir code
    ts = load.timescale()

    # Try local copy first (same dir as this script or repo root)
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    for bsp_path in [script_dir / "de440s.bsp", repo_root / "de440s.bsp"]:
        if bsp_path.exists():
            eph = load(str(bsp_path))
            break
    else:
        eph = load("de440s.bsp")

    sun = eph["sun"]
    moon = eph["moon"]
    earth = eph["earth"]
    mecca = wgs84.latlon(MECCA_LAT, MECCA_LON, elevation_m=MECCA_ELEV_M)
    observer = earth + mecca

    return ts, eph, sun, moon, earth, mecca, observer


# ── Astronomical computations ─────────────────────────────────────────────────

def find_sunset(ts, eph, sun, mecca, d):
    """
    Find sunset at Mecca on the given date (UTC day).

    Skyfield's risings_and_settings uses centre-of-disk convention:
      horizon_degrees = -34'/60 = -0.5667 deg (refraction only)
      radius_degrees  = 0 (no semi-diameter correction)
    """
    t0 = ts.utc(d.year, d.month, d.day, 0, 0, 0)
    t1 = ts.utc(d.year, d.month, d.day, 23, 59, 59)

    f = almanac.risings_and_settings(eph, sun, mecca)
    times, events = find_discrete(t0, t1, f)

    for t, event in zip(times, events):
        if not event:  # setting event
            return t

    return None


def find_moonset(ts, eph, moon, mecca, d):
    """
    Find moonset at Mecca on the given date (UTC day).

    Same centre-of-disk convention as sunset:
      horizon_degrees = -34'/60 (refraction only)
      radius_degrees  = 0
    """
    t0 = ts.utc(d.year, d.month, d.day, 0, 0, 0)
    t1 = ts.utc(d.year, d.month, d.day, 23, 59, 59)

    f = almanac.risings_and_settings(eph, moon, mecca)
    times, events = find_discrete(t0, t1, f)

    for t, event in zip(times, events):
        if not event:  # setting event
            return t

    return None


def find_conjunction_near(ts, eph, d, search_days=3):
    """
    Find the geocentric conjunction (new moon) nearest to date d.

    Searches a window of ±search_days around d.
    """
    t0 = ts.utc(d.year, d.month, d.day - search_days)
    t1 = ts.utc(d.year, d.month, d.day + search_days)

    f = moon_phases(eph)
    times, phases = find_discrete(t0, t1, f)

    for t, phase in zip(times, phases):
        if phase == 0:  # new moon
            return t

    return None


# ── Hijri calendar logic ─────────────────────────────────────────────────────

def approximate_29th(hijri_year, hijri_month):
    """
    Estimate the Gregorian date of the 29th day of the Hijri month
    preceding the target month.

    Uses the same epoch/synodic seed as the Elixir implementation.
    """
    months_since_epoch = (hijri_year - 1) * 12 + (hijri_month - 1)
    rough_jdn = HIJRI_EPOCH_JDN + round(months_since_epoch * MEAN_SYNODIC) + 28
    return jdn_to_date(rough_jdn)


def jdn_to_date(jdn):
    """Convert a Julian Day Number to a Gregorian date."""
    # Richards algorithm (2013)
    f = jdn + 1401 + ((4 * jdn + 274277) // 146097 * 3) // 4 - 38
    e = 4 * f + 3
    g = (e % 1461) // 4
    h = 5 * g + 2

    day = (h % 153) // 5 + 1
    month = (h // 153 + 2) % 12 + 1
    year = e // 1461 - 4716 + (14 - month) // 12

    return date(year, month, day)


def era4_first_day(hijri_year, hijri_month, ts, eph, sun, moon, mecca, verbose=False):
    """
    Era 4 rule (1423+ AH): conjunction before sunset AND moonset after sunset.

    Returns (gregorian_date, details_dict).
    """
    candidate_29 = approximate_29th(hijri_year, hijri_month)

    # Find conjunction near candidate date
    conjunction = find_conjunction_near(ts, eph, candidate_29)
    if conjunction is None:
        return None, {"error": "no conjunction found"}

    # Convert conjunction to Mecca local date to anchor the 29th
    conj_utc_h = conjunction.utc[3] + conjunction.utc[4] / 60 + conjunction.utc[5] / 3600
    conj_mecca_h = conj_utc_h + MECCA_UTC_OFFSET_H
    conj_date_utc = date(int(conjunction.utc[0]), int(conjunction.utc[1]), int(conjunction.utc[2]))
    if conj_mecca_h >= 24:
        candidate_29 = conj_date_utc + timedelta(days=1)
    else:
        candidate_29 = conj_date_utc

    # Find sunset and moonset on candidate 29th
    sunset = find_sunset(ts, eph, sun, mecca, candidate_29)
    moonset = find_moonset(ts, eph, moon, mecca, candidate_29)

    if sunset is None:
        return None, {"error": "no sunset found"}

    # Check conditions
    conj_before_sunset = conjunction.tt < sunset.tt
    moonset_after_sunset = (moonset is not None) and (moonset.tt > sunset.tt)

    # Compute gaps for diagnostics
    conj_gap_s = (conjunction.tt - sunset.tt) * 86400
    moon_gap_s = (moonset.tt - sunset.tt) * 86400 if moonset is not None else None

    details = {
        "candidate_29": candidate_29,
        "conjunction": conjunction.utc_iso(),
        "sunset": sunset.utc_iso(),
        "moonset": moonset.utc_iso() if moonset is not None else "none",
        "conj_before_sunset": conj_before_sunset,
        "moonset_after_sunset": moonset_after_sunset,
        "conj_gap_s": round(conj_gap_s, 1),
        "moon_gap_s": round(moon_gap_s, 1) if moon_gap_s is not None else None,
        "new_month": conj_before_sunset and moonset_after_sunset,
    }

    if conj_before_sunset and moonset_after_sunset:
        first_day = candidate_29 + timedelta(days=1)
    else:
        first_day = candidate_29 + timedelta(days=2)

    return first_day, details


def era3_first_day(hijri_year, hijri_month, ts, eph, sun, moon, mecca, verbose=False):
    """
    Era 3 rule (1420-1422 AH): moonset after sunset only (no conjunction check).
    """
    candidate_29 = approximate_29th(hijri_year, hijri_month)

    # Still need conjunction to anchor the candidate 29th date
    conjunction = find_conjunction_near(ts, eph, candidate_29)
    if conjunction is not None:
        conj_utc_h = conjunction.utc[3] + conjunction.utc[4] / 60 + conjunction.utc[5] / 3600
        conj_mecca_h = conj_utc_h + MECCA_UTC_OFFSET_H
        conj_date_utc = date(int(conjunction.utc[0]), int(conjunction.utc[1]), int(conjunction.utc[2]))
        if conj_mecca_h >= 24:
            candidate_29 = conj_date_utc + timedelta(days=1)
        else:
            candidate_29 = conj_date_utc

    sunset = find_sunset(ts, eph, sun, mecca, candidate_29)
    moonset = find_moonset(ts, eph, moon, mecca, candidate_29)

    if sunset is None:
        return None, {"error": "no sunset found"}

    moonset_after_sunset = (moonset is not None) and (moonset.tt > sunset.tt)

    details = {
        "candidate_29": candidate_29,
        "sunset": sunset.utc_iso(),
        "moonset": moonset.utc_iso() if moonset is not None else "none",
        "moonset_after_sunset": moonset_after_sunset,
    }

    if moonset_after_sunset:
        first_day = candidate_29 + timedelta(days=1)
    else:
        first_day = candidate_29 + timedelta(days=2)

    return first_day, details


def era2_first_day(hijri_year, hijri_month, ts, eph, verbose=False):
    """
    Era 2 rule (1392-1419 AH): Gregorian date of conjunction + 1 day.
    """
    candidate_29 = approximate_29th(hijri_year, hijri_month)
    conjunction = find_conjunction_near(ts, eph, candidate_29)

    if conjunction is None:
        return None, {"error": "no conjunction found"}

    conj_date_utc = date(int(conjunction.utc[0]), int(conjunction.utc[1]), int(conjunction.utc[2]))
    first_day = conj_date_utc + timedelta(days=1)

    details = {
        "conjunction": conjunction.utc_iso(),
        "conj_date": conj_date_utc,
    }

    return first_day, details


# ── Reference data loading ────────────────────────────────────────────────────

def load_van_gent_csv(csv_path):
    """
    Load the van Gent reference data from a CSV file.

    Expected columns: hijri_year, hijri_month, gregorian_date
    Returns a dict: (hijri_year, hijri_month) -> date
    """
    ref = {}
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            hy = int(row["hijri_year"])
            hm = int(row["hijri_month"])
            gd = date.fromisoformat(row["gregorian_date"])
            ref[(hy, hm)] = gd
    return ref


def load_van_gent_from_elixir_data():
    """
    Reconstruct van Gent dates from the days-since-epoch data
    embedded directly in this file (copied from the Elixir module).

    This avoids a runtime dependency on the Elixir project.
    """
    # Van Gent days-since-epoch data (identical to van_gent_data/0 in
    # Astro.UmmAlQura.ReferenceData)
    days = [
        28607,28636,28665,28695,28724,28754,28783,28813,28843,28872,28901,28931,28960,28990,29019,29049,29078,29108,29137,29167,
        29196,29226,29255,29285,29315,29345,29375,29404,29434,29463,29492,29522,29551,29580,29610,29640,29669,29699,29729,29759,
        29788,29818,29847,29876,29906,29935,29964,29994,30023,30053,30082,30112,30141,30171,30200,30230,30259,30289,30318,30348,
        30378,30408,30437,30467,30496,30526,30555,30585,30614,30644,30673,30703,30732,30762,30791,30821,30850,30880,30909,30939,
        30968,30998,31027,31057,31086,31116,31145,31175,31204,31234,31263,31293,31322,31352,31381,31411,31441,31471,31500,31530,
        31559,31589,31618,31648,31676,31706,31736,31766,31795,31825,31854,31884,31913,31943,31972,32002,32031,32061,32090,32120,
        32150,32180,32209,32239,32268,32298,32327,32357,32386,32416,32445,32475,32504,32534,32563,32593,32622,32652,32681,32711,
        32740,32770,32799,32829,32858,32888,32917,32947,32976,33006,33035,33065,33094,33124,33153,33183,33213,33243,33272,33302,
        33331,33361,33390,33420,33450,33479,33509,33539,33568,33598,33627,33657,33686,33716,33745,33775,33804,33834,33863,33893,
        33922,33952,33981,34011,34040,34069,34099,34128,34158,34187,34217,34247,34277,34306,34336,34365,34395,34424,34454,34483,
        34512,34542,34571,34601,34631,34660,34690,34719,34749,34778,34808,34837,34867,34896,34926,34955,34985,35015,35044,35074,
        35103,35133,35162,35192,35222,35251,35280,35310,35340,35370,35399,35429,35458,35488,35517,35547,35576,35605,35635,35665,
        35694,35723,35753,35782,35811,35841,35871,35901,35930,35960,35989,36019,36048,36078,36107,36136,36166,36195,36225,36254,
        36284,36314,36343,36373,36403,36433,36462,36492,36521,36551,36580,36610,36639,36669,36698,36728,36757,36786,36816,36845,
        36875,36904,36934,36963,36993,37022,37052,37081,37111,37141,37170,37200,37229,37259,37288,37318,37347,37377,37406,37436,
        37465,37495,37524,37554,37584,37613,37643,37672,37701,37731,37760,37790,37819,37849,37878,37908,37938,37967,37997,38027,
        38056,38085,38115,38144,38174,38203,38233,38262,38292,38322,38351,38381,38410,38440,38469,38499,38528,38558,38587,38617,
        38646,38676,38705,38735,38764,38794,38823,38853,38882,38912,38941,38971,39001,39030,39059,39089,39118,39148,39178,39208,
        39237,39267,39297,39326,39355,39385,39414,39444,39473,39503,39532,39562,39592,39621,39650,39680,39709,39739,39768,39798,
        39827,39857,39886,39916,39946,39975,40005,40035,40064,40094,40123,40153,40182,40212,40241,40271,40300,40330,40359,40389,
        40418,40448,40477,40507,40536,40566,40595,40625,40655,40685,40714,40744,40773,40803,40832,40862,40892,40921,40951,40980,
        41009,41039,41068,41098,41127,41157,41186,41216,41245,41275,41304,41334,41364,41393,41422,41452,41481,41511,41540,41570,
        41599,41629,41658,41688,41718,41748,41777,41807,41836,41865,41894,41924,41953,41983,42012,42042,42072,42102,42131,42161,
        42190,42220,42249,42279,42308,42337,42367,42397,42426,42456,42485,42515,42545,42574,42604,42633,42662,42692,42721,42751,
        42780,42810,42839,42869,42899,42929,42958,42988,43017,43046,43076,43105,43135,43164,43194,43223,43253,43283,43312,43342,
        43371,43401,43430,43460,43489,43519,43548,43578,43607,43637,43666,43696,43726,43755,43785,43814,43844,43873,43903,43932,
        43962,43991,44021,44050,44080,44109,44139,44169,44198,44228,44258,44287,44317,44346,44375,44405,44434,44464,44493,44523,
        44553,44582,44612,44641,44671,44700,44730,44759,44788,44818,44847,44877,44906,44936,44966,44996,45025,45055,45084,45114,
        45143,45172,45202,45231,45261,45290,45320,45350,45380,45409,45439,45468,45498,45527,45556,45586,45615,45644,45674,45704,
        45733,45763,45793,45823,45852,45882,45911,45940,45970,45999,46028,46058,46088,46117,46147,46177,46206,46236,46265,46295,
        46324,46354,46383,46413,46442,46472,46501,46531,46560,46590,46620,46649,46679,46708,46738,46767,46797,46826,46856,46885,
        46915,46944,46974,47003,47033,47063,47092,47122,47151,47181,47210,47240,47269,47298,47328,47357,47387,47417,47446,47476,
        47506,47535,47565,47594,47624,47653,47682,47712,47741,47771,47800,47830,47860,47890,47919,47949,47978,48008,48037,48066,
        48096,48125,48155,48184,48214,48244,48273,48303,48333,48362,48392,48421,48450,48480,48509,48538,48568,48598,48627,48657,
        48687,48717,48746,48776,48805,48834,48864,48893,48922,48952,48982,49011,49041,49071,49100,49130,49160,49189,49218,49248,
        49277,49306,49336,49365,49395,49425,49455,49484,49514,49543,49573,49602,49632,49661,49690,49720,49749,49779,49809,49838,
        49868,49898,49927,49957,49986,50016,50045,50075,50104,50133,50163,50192,50222,50252,50281,50311,50340,50370,50400,50429,
        50459,50488,50518,50547,50576,50606,50635,50665,50694,50724,50754,50784,50813,50843,50872,50902,50931,50960,50990,51019,
        51049,51078,51108,51138,51167,51197,51227,51256,51286,51315,51345,51374,51403,51433,51462,51492,51522,51552,51582,51611,
        51641,51670,51699,51729,51758,51787,51816,51846,51876,51906,51936,51965,51995,52025,52054,52083,52113,52142,52171,52200,
        52230,52260,52290,52319,52349,52379,52408,52438,52467,52497,52526,52555,52585,52614,52644,52673,52703,52733,52762,52792,
        52822,52851,52881,52910,52939,52969,52998,53028,53057,53087,53116,53146,53176,53205,53235,53264,53294,53324,53353,53383,
        53412,53441,53471,53500,53530,53559,53589,53619,53648,53678,53708,53737,53767,53796,53825,53855,53884,53914,53943,53973,
        54003,54032,54062,54092,54121,54151,54180,54209,54239,54268,54297,54327,54357,54387,54416,54446,54476,54505,54535,54564,
        54593,54623,54652,54681,54711,54741,54770,54800,54830,54859,54889,54919,54948,54977,55007,55036,55066,55095,55125,55154,
        55184,55213,55243,55273,55302,55332,55361,55391,55420,55450,55479,55508,55538,55567,55597,55627,55657,55686,55716,55745,
        55775,55804,55834,55863,55892,55922,55951,55981,56011,56040,56070,56100,56129,56159,56188,56218,56247,56276,56306,56335,
        56365,56394,56424,56454,56483,56513,56543,56572,56601,56631,56660,56690,56719,56749,56778,56808,56837,56867,56897,56926,
        56956,56985,57015,57044,57074,57103,57133,57162,57192,57221,57251,57280,57310,57340,57369,57399,57429,57458,57487,57517,
        57546,57576,57605,57634,57664,57694,57723,57753,57783,57813,57842,57871,57901,57930,57959,57989,58018,58048,58077,58107,
        58137,58167,58196,58226,58255,58285,58314,58343,58373,58402,58432,58461,58491,58521,58551,58580,58610,58639,58669,58698,
        58727,58757,58786,58816,58845,58875,58905,58934,58964,58994,59023,59053,59082,59111,59141,59170,59200,59229,59259,59288,
        59318,59348,59377,59407,59436,59466,59495,59525,59554,59584,59613,59643,59672,59702,59731,59761,59791,59820,59850,59879,
        59909,59939,59968,59997,60027,60056,60086,60115,60145,60174,60204,60234,60264,60293,60323,60352,60381,60411,60440,60469,
        60499,60528,60558,60588,60618,60647,60677,60707,60736,60765,60795,60824,60853,60883,60912,60942,60972,61002,61031,61061,
        61090,61120,61149,61179,61208,61237,61267,61296,61326,61356,61385,61415,61445,61474,61504,61533,61563,61592,61621,61651,
        61680,61710,61739,61769,61799,61828,61858,61888,61917,61947,61976,62006,62035,62064,62094,62123,62153,62182,62212,62242,
        62271,62301,62331,62360,62390,62419,62448,62478,62507,62537,62566,62596,62625,62655,62685,62715,62744,62774,62803,62832,
        62862,62891,62921,62950,62980,63009,63039,63069,63099,63128,63157,63187,63216,63246,63275,63305,63334,63363,63393,63423,
        63453,63482,63512,63541,63571,63600,63630,63659,63689,63718,63747,63777,63807,63836,63866,63895,63925,63955,63984,64014,
        64043,64073,64102,64131,64161,64190,64220,64249,64279,64309,64339,64368,64398,64427,64457,64486,64515,64545,64574,64603,
        64633,64663,64692,64722,64752,64782,64811,64841,64870,64899,64929,64958,64987,65017,65047,65076,65106,65136,65166,65195,
        65225,65254,65283,65313,65342,65371,65401,65431,65460,65490,65520,65549,65579,65608,65638,65667,65697,65726,65755,65785,
        65815,65844,65874,65903,65933,65963,65992,66022,66051,66081,66110,66140,66169,66199,66228,66258,66287,66317,66346,66376,
        66405,66435,66465,66494,66524,66553,66583,66612,66641,66671,66700,66730,66760,66789,66819,66849,66878,66908,66937,66967,
        66996,67025,67055,67084,67114,67143,67173,67203,67233,67262,67292,67321,67351,67380,67409,67439,67468,67497,67527,67557,
        67587,67617,67646,67676,67705,67735,67764,67793,67823,67852,67882,67911,67941,67971,68000,68030,68060,68089,68119,68148,
        68177,68207,68236,68266,68295,68325,68354,68384,68414,68443,68473,68502,68532,68561,68591,68620,68650,68679,68708,68738,
        68768,68797,68827,68857,68886,68916,68946,68975,69004,69034,69063,69092,69122,69152,69181,69211,69240,69270,69300,69330,
        69359,69388,69418,69447,69476,69506,69535,69565,69595,69624,69654,69684,69713,69743,69772,69802,69831,69861,69890,69919,
        69949,69978,70008,70038,70067,70097,70126,70156,70186,70215,70245,70274,70303,70333,70362,70392,70421,70451,70481,70510,
        70540,70570,70599,70629,70658,70687,70717,70746,70776,70805,70835,70864,70894,70924,70954,70983,71013,71042,71071,71101,
        71130,71159,71189,71218,71248,71278,71308,71337,71367,71397,71426,71455,71485,71514,71543,71573,71602,71632,71662,71691,
        71721,71751,71781,71810,71839,71869,71898,71927,71957,71986,72016,72046,72075,72105,72135,72164,72194,72223,72253,72282,
        72311,72341,72370,72400,72429,72459,72489,72518,72548,72577,72607,72637,72666,72695,72725,72754,72784,72813,72843,72872,
        72902,72931,72961,72991,73020,73050,73080,73109,73139,73168,73197,73227,73256,73286,73315,73345,73375,73404,73434,73464,
        73493,73523,73552,73581,73611,73640,73669,73699,73729,73758,73788,73818,73848,73877,73907,73936,73965,73995,74024,74053,
        74083,74113,74142,74172,74202,74231,74261,74291,74320,74349,74379,74408,74437,74467,74497,74526,74556,74585,74615,74645,
        74675,74704,74733,74763,74792,74822,74851,74881,74910,74940,74969,74999,75029,75058,75088,75117,75147,75176,75206,75235,
        75264,75294,75323,75353,75383,75412,75442,75472,75501,75531,75560,75590,75619,75648,75678,75707,75737,75766,75796,75826,
        75856,75885,75915,75944,75974,76003,76032,76062,76091,76121,76150,76180,76210,76239,76269,76299,76328,76358,76387,76416,
        76446,76475,76505,76534,76564,76593,76623,76653,76682,76712,76741,76771,76801,76830,76859,76889,76918,76948,76977,77007,
        77036,77066,77096,77125,77155,77185,77214,77243,77273,77302,77332,77361,77390,77420,77450,77479,77509,77539,77569,77598,
        77627,77657,77686,77715,77745,77774,77804,77833,77863,77893,77923,77952,77982,78011,78041,78070,78099,78129,78158,78188,
        78217,78247,78277,78307,78336,78366,78395,78425,78454,78483,78513,78542,78572,78601,78631,78661,78690,78720,78750,78779,
        78808,78838,78867,78897,78926,78956,78985,79015,79044,79074,79104,79133,79163,79192,79222,79251,79281,79310,79340,79369,
        79399,79428,79458,79487,79517,79546,79576,79606,79635,79665,79695,79724,79753,79783,79812,79841,79871,79900,79930,79960,
        79990,
    ]

    # Hijri calendar starts at 1356/1 = 1937-03-14
    start_date = date(1937, 3, 14)
    start_year = 1356
    start_month = 1

    ref = {}
    current = start_date
    for i in range(len(days) - 1):
        hy = start_year + i // 12
        hm = start_month + i % 12
        ref[(hy, hm)] = current
        month_len = days[i + 1] - days[i]
        current = current + timedelta(days=month_len)

    # Last entry
    i = len(days) - 1
    hy = start_year + i // 12
    hm = start_month + i % 12
    ref[(hy, hm)] = current

    return ref


# ── Main sweep ────────────────────────────────────────────────────────────────

def run_sweep(args):
    print("Loading Skyfield ephemeris...")
    ts, eph, sun, moon, earth, mecca, observer = setup_skyfield()
    print("Ephemeris loaded.\n")

    # Load reference data
    ref = load_van_gent_from_elixir_data()
    print(f"Loaded {len(ref)} van Gent reference months.\n")

    # Determine era range
    if args.era == "all":
        eras = [2, 3, 4]
    else:
        eras = [int(args.era)]

    total = 0
    correct = 0
    failures = []

    for era in eras:
        if era == 2:
            year_range = range(ERA2_START, ERA3_START)
            era_label = "Era 2"
        elif era == 3:
            year_range = range(ERA3_START, ERA4_START)
            era_label = "Era 3"
        elif era == 4:
            year_range = range(ERA4_START, 1501)
            era_label = "Era 4"
        else:
            print(f"Unknown era {era}")
            continue

        if args.year:
            year_range = range(args.year, args.year + 1)

        era_total = 0
        era_correct = 0
        era_failures = []

        print(f"{'='*60}")
        print(f"  {era_label}: {year_range.start}-{year_range.stop - 1} AH")
        print(f"{'='*60}")

        for hy in year_range:
            for hm in range(1, 13):
                if (hy, hm) not in ref:
                    continue

                expected = ref[(hy, hm)]

                try:
                    if era == 4:
                        result, details = era4_first_day(
                            hy, hm, ts, eph, sun, moon, mecca, verbose=args.verbose
                        )
                    elif era == 3:
                        result, details = era3_first_day(
                            hy, hm, ts, eph, sun, moon, mecca, verbose=args.verbose
                        )
                    else:  # era 2
                        result, details = era2_first_day(
                            hy, hm, ts, eph, verbose=args.verbose
                        )
                except Exception as e:
                    result = None
                    details = {"error": str(e)}

                era_total += 1

                if result == expected:
                    era_correct += 1
                    if args.verbose:
                        print(f"  {hy}/{hm:2d}: {result}  OK")
                        if era == 4:
                            print(f"           conj_gap={details.get('conj_gap_s')}s  "
                                  f"moon_gap={details.get('moon_gap_s')}s")
                else:
                    diff = (result - expected).days if result else "N/A"
                    entry = {
                        "hijri": f"{hy}/{hm}",
                        "expected": expected,
                        "got": result,
                        "diff": diff,
                        "details": details,
                    }
                    era_failures.append(entry)

                    if args.verbose or args.failures:
                        print(f"  {hy}/{hm:2d}: MISMATCH  expected={expected}  "
                              f"got={result}  diff={diff}d")
                        if era == 4 and "conj_gap_s" in details:
                            print(f"           conj_gap={details['conj_gap_s']}s  "
                                  f"moon_gap={details.get('moon_gap_s')}s  "
                                  f"conj_before={details['conj_before_sunset']}  "
                                  f"moon_after={details['moonset_after_sunset']}")

        pct = era_correct / era_total * 100 if era_total > 0 else 0
        print(f"\n  {era_label} result: {era_correct}/{era_total} ({pct:.1f}%)")
        if era_failures:
            print(f"  {len(era_failures)} failures")
        print()

        total += era_total
        correct += era_correct
        failures.extend(era_failures)

    # Summary
    pct = correct / total * 100 if total > 0 else 0
    print(f"{'='*60}")
    print(f"  OVERALL: {correct}/{total} ({pct:.1f}%)")
    print(f"{'='*60}")

    if failures:
        print(f"\n  {len(failures)} total failures:")
        for f in failures:
            print(f"    {f['hijri']}: expected {f['expected']}, got {f['got']} (diff {f['diff']}d)")
            d = f["details"]
            if "conj_gap_s" in d:
                print(f"      conjunction gap: {d['conj_gap_s']}s, "
                      f"moonset gap: {d.get('moon_gap_s')}s")

    return len(failures) == 0


def main():
    parser = argparse.ArgumentParser(
        description="Umm al-Qura calendar computation using Skyfield"
    )
    parser.add_argument(
        "--era", default="4",
        help="Era to test: 2, 3, 4, or 'all' (default: 4)"
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Print details for every month"
    )
    parser.add_argument(
        "--failures", action="store_true",
        help="Print only failures (not every month)"
    )
    parser.add_argument(
        "--year", type=int, default=None,
        help="Test only a specific Hijri year"
    )

    args = parser.parse_args()
    success = run_sweep(args)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
