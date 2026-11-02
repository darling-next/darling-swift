/*
 This file is part of Darling.

 Copyright (C) 2026 Darling contributors

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

/* The two Security protocol-object types the Network overlay's declarations name.
 *
 * Darling's MacOSX.sdk has no Modules/module.modulemap for Security.framework (it is generated from
 * src/external/security with the headers symlinked in), so `import Security` does not resolve when
 * the overlays are built. The overlay builds already carry shim module maps for exactly this case
 * (see overlays/UniformTypeIdentifiers/shims, overlays/CoreGraphics/shims); this one re-exports only
 * what the overlay needs, so the Swift type it names is the same C type Apple's own interface names
 * (`Security.sec_protocol_options_t`, i.e. `__C.OS_sec_protocol_options`).
 */

#ifndef DARLING_NETWORK_SECURITY_SHIMS_H
#define DARLING_NETWORK_SECURITY_SHIMS_H

#include <Security/SecProtocolOptions.h>
#include <Security/SecProtocolMetadata.h>

#endif /* DARLING_NETWORK_SECURITY_SHIMS_H */
