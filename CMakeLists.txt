file(GLOB DYLIBS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.dylib")
install(FILES ${DYLIBS} DESTINATION libexec/darling/usr/lib/swift)

# Overlay payloads use the same layout as source-built frameworks. Install the
# complete bundles (including resources), with the standard current-version
# links even when the payload contains only its concrete version directory.
function(install_swift_frameworks source destination)
	set(_framework_source "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
	set(_framework_destination "${CMAKE_INSTALL_PREFIX}/libexec/darling/${destination}")
	file(GLOB _frameworks CONFIGURE_DEPENDS "${_framework_source}/*.framework")
	foreach(_framework IN LISTS _frameworks)
		get_filename_component(_framework_name "${_framework}" NAME_WE)
		install(DIRECTORY "${_framework}" DESTINATION "${_framework_destination}")
		InstallSymlink(A "${_framework_destination}/${_framework_name}.framework/Versions/Current")
		InstallSymlink("Versions/Current/${_framework_name}"
			"${_framework_destination}/${_framework_name}.framework/${_framework_name}")
		foreach(_framework_link IN ITEMS Resources Headers Modules)
			if(IS_DIRECTORY "${_framework}/Versions/A/${_framework_link}")
				InstallSymlink("Versions/Current/${_framework_link}"
					"${_framework_destination}/${_framework_name}.framework/${_framework_link}")
			endif()
		endforeach()
	endforeach()
endfunction()

install_swift_frameworks("." "System/Library/Frameworks")
install_swift_frameworks("private-frameworks" "System/Library/PrivateFrameworks")
install_swift_frameworks("substitutes/System/Library/Frameworks" "System/Library/Frameworks")
install_swift_frameworks("substitutes/System/Library/PrivateFrameworks" "System/Library/PrivateFrameworks")

# Non-framework payloads mirror their guest paths under substitutes.
install(DIRECTORY substitutes/ DESTINATION libexec/darling
	PATTERN "*.framework" EXCLUDE)

