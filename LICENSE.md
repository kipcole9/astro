# License

Copyright 2018-2019 Kip Cole

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in
compliance with the License. You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License
is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied. See the License for the specific language governing permissions and limitations under the
License.

## Third-party data

### JPL planetary and lunar ephemeris DE440

`priv/de440s-astro.bsp`, which ships in the package, is a subset of the DE440s ephemeris kernel produced by the Solar System Dynamics Group of the Jet Propulsion Laboratory, California Institute of Technology, and distributed by NASA's Navigation and Ancillary Information Facility (NAIF) at [naif.jpl.nasa.gov](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/). It holds the Sun, Moon and Earth segments Astro uses for 1900 to 2100, their Chebyshev coefficients copied unchanged, and was extracted for Astro by Kip Cole with `mix astro.build_ephemeris`. The full kernel, which `mix astro.download_ephemeris` fetches from NAIF, is not redistributed.

NAIF's [rules for SPICE kernels](https://naif.jpl.nasa.gov/naif/rules.html) allow anyone to download and use them, and allow a modified kernel to be redistributed provided it attributes whoever made the last modification rather than the original producer. NAIF publishes no licence for its kernels beyond those rules, and the ephemeris is not covered by the Apache License above.

The ephemeris is described in Ryan S. Park, William M. Folkner, James G. Williams and Dale H. Boggs, "The JPL Planetary and Lunar Ephemerides DE440 and DE441", *The Astronomical Journal* 161, 105 (2021), [doi:10.3847/1538-3881/abd414](https://doi.org/10.3847/1538-3881/abd414).
