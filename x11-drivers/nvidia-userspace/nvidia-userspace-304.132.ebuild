# Copyright 1999-2016 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

MULTILIB_COMPAT=( abi_x86_{32,64} )
inherit eutils flag-o-matic linux-info linux-mod multilib nvidia-driver \
	portability toolchain-funcs unpacker user versionator udev

X86_NV_PACKAGE="NVIDIA-Linux-x86-${PV}"
AMD64_NV_PACKAGE="NVIDIA-Linux-x86_64-${PV}"
X86_FBSD_NV_PACKAGE="NVIDIA-FreeBSD-x86-${PV}"
AMD64_FBSD_NV_PACKAGE="NVIDIA-FreeBSD-x86_64-${PV}"

DESCRIPTION="NVIDIA X11 userspace libraries and applications"
HOMEPAGE="http://www.nvidia.com/"
SRC_URI="x86? ( http://us.download.nvidia.com/XFree86/Linux-x86/${PV}/${X86_NV_PACKAGE}.run )
	amd64? ( http://us.download.nvidia.com/XFree86/Linux-x86_64/${PV}/${AMD64_NV_PACKAGE}.run )
	amd64-fbsd? ( http://us.download.nvidia.com/XFree86/FreeBSD-x86_64/${PV}/${AMD64_FBSD_NV_PACKAGE}.tar.gz )
	x86-fbsd? ( http://us.download.nvidia.com/XFree86/FreeBSD-x86/${PV}/${X86_FBSD_NV_PACKAGE}.tar.gz )
	tools? ( ftp://download.nvidia.com/XFree86/nvidia-settings/nvidia-settings-${PV}.tar.bz2 )"

LICENSE="GPL-2 NVIDIA-r1"
SLOT="0"
KEYWORDS="-* ~amd64 ~x86 ~amd64-fbsd ~x86-fbsd"
IUSE="acpi multilib kernel_FreeBSD kernel_linux static-libs +tools +X"
RESTRICT="strip"
EMULTILIB_PKG="true"

COMMON="app-eselect/eselect-opencl
	kernel_linux? ( >=sys-libs/glibc-2.6.1 )
	tools? (
		dev-libs/atk
		dev-libs/glib:2
		x11-libs/gdk-pixbuf
		x11-libs/gtk+:2
		x11-libs/libX11
		x11-libs/libXext
		x11-libs/pango[X]
		x11-libs/pangox-compat
	)
	X? (
		>=app-eselect/eselect-opengl-1.0.9
	)
"
DEPEND="${COMMON}"
# Note: do not add !>nvidia-userspace-ver or !<nvidia-userspace-ver
# because it would cause pkg_postrm to set the wrong opengl implementation
RDEPEND="${COMMON}
	X? ( x11-libs/libXvMC )
	acpi? ( sys-power/acpid )
	tools? ( !media-video/nvidia-settings )
	X? (
		<x11-base/xorg-server-1.18.99:=
		x11-libs/libXvMC
		multilib? (
			>=x11-libs/libX11-1.6.2[abi_x86_32]
			>=x11-libs/libXext-1.3.2[abi_x86_32]
		)
	)"
PDEPEND="X? ( >=x11-libs/libvdpau-0.3-r1 )"

REQUIRED_USE="tools? ( X )"
QA_PREBUILT="opt/* usr/lib*"
S="${WORKDIR}/"

pkg_pretend() {
	if use amd64 && has_multilib_profile && \
		[ "${DEFAULT_ABI}" != "amd64" ]; then
		eerror "This ebuild doesn't currently support changing your default ABI"
		die "Unexpected \${DEFAULT_ABI} = ${DEFAULT_ABI}"
	fi

	# Kernel features/options to check for
	CONFIG_CHECK="~ZONE_DMA ~MTRR ~SYSVIPC ~!LOCKDEP"
	use x86 && CONFIG_CHECK+=" ~HIGHMEM"

	# Now do the above checks
	use kernel_linux && check_extra_config
}

pkg_setup() {
	# try to turn off distcc and ccache for people that have a problem with it
	export DISTCC_DISABLE=1
	export CCACHE_DISABLE=1

	if use kernel_linux; then
		linux-mod_pkg_setup
		MODULE_NAMES="nvidia(video:${S}/kernel)"
		BUILD_PARAMS="IGNORE_CC_MISMATCH=yes V=1 SYSSRC=${KV_DIR} \
		SYSOUT=${KV_OUT_DIR} CC=$(tc-getBUILD_CC)"
		# linux-mod_src_compile calls set_arch_to_kernel, which
		# sets the ARCH to x86 but NVIDIA's wrapping Makefile
		# expects x86_64 or i386 and then converts it to x86
		# later on in the build process
		BUILD_FIXES="ARCH=$(uname -m | sed -e 's/i.86/i386/')"
	fi

	# Since Nvidia ships 3 different series of drivers, we need to give the user
	# some kind of guidance as to what version they should install. This tries
	# to point the user in the right direction but can't be perfect. check
	# nvidia-driver.eclass
	nvidia-driver-check-warning

	# set variables to where files are in the package structure
	if use kernel_FreeBSD; then
		use x86-fbsd   && S="${WORKDIR}/${X86_FBSD_NV_PACKAGE}"
		use amd64-fbsd && S="${WORKDIR}/${AMD64_FBSD_NV_PACKAGE}"
		NV_DOC="${S}/doc"
		NV_OBJ="${S}/obj"
		NV_SRC="${S}/src"
		NV_MAN="${S}/x11/man"
		NV_X11="${S}/obj"
		NV_SOVER=1
	elif use kernel_linux; then
		NV_DOC="${S}"
		NV_OBJ="${S}"
		NV_SRC="${S}/kernel"
		NV_MAN="${S}"
		NV_X11="${S}"
		NV_SOVER=${PV}
	else
		die "Could not determine proper NVIDIA package"
	fi
}

src_prepare() {
	# Please add a brief description for every added patch
	cat <<- EOF > "${S}"/nvidia.icd
		/usr/$(get_libdir)/libnvidia-opencl.so
	EOF

	# Allow user patches so they can support RC kernels and whatever else
	epatch_user
}

src_compile() {
	# This is already the default on Linux, as there's no toplevel Makefile, but
	# on FreeBSD there's one and triggers the kernel module build, as we install
	# it by itself, pass this.

	cd "${NV_SRC}"
	if use tools; then
		emake -C "${S}"/nvidia-settings-${PV}/src/libXNVCtrl clean
		emake -C "${S}"/nvidia-settings-${PV}/src/libXNVCtrl \
			AR="$(tc-getAR)" \
			CC="$(tc-getCC)" \
			RANLIB="$(tc-getRANLIB)" \
			libXNVCtrl.a
		emake -C "${S}"/nvidia-settings-${PV}/src \
			AR="$(tc-getAR)" \
			CC="$(tc-getCC)" \
			LD="$(tc-getCC)" \
			LIBDIR="$(get_libdir)" \
			NVML_ENABLED=0 \
			NV_USE_BUNDLED_LIBJANSSON=0 \
			NV_VERBOSE=1 \
			RANLIB="$(tc-getRANLIB)" \
			STRIP_CMD=true
	fi
}

# Install nvidia library:
# the first parameter is the library to install
# the second parameter is the provided soversion
# the third parameter is the target directory if its not /usr/lib
donvidia() {
	# Full path to library minus SOVER
	MY_LIB="$1"

	# SOVER to use
	MY_SOVER="$2"

	# Where to install
	MY_DEST="$3"

	if [[ -z "${MY_DEST}" ]]; then
		MY_DEST="/usr/$(get_libdir)"
		action="dolib.so"
	else
		exeinto ${MY_DEST}
		action="doexe"
	fi

	# Get just the library name
	libname=$(basename $1)

	# Install the library with the correct SOVER
	${action} ${MY_LIB}.${MY_SOVER} || \
		die "failed to install ${libname}"

	# If SOVER wasn't 1, then we need to create a .1 symlink
	if [[ "${MY_SOVER}" != "1" ]]; then
		dosym ${libname}.${MY_SOVER} \
			${MY_DEST}/${libname}.1 || \
			die "failed to create ${libname} symlink"
	fi

	# Always create the symlink from the raw lib to the .1
	dosym ${libname}.1 \
		${MY_DEST}/${libname} || \
		die "failed to create ${libname} symlink"
}

src_install() {
	if use kernel_linux; then
		# Add the aliases
		# This file is tweaked with the appropriate video group in
		# pkg_postinst, see bug #491414
		newins "${FILESDIR}"/nvidia-169.07 nvidia.conf

		# Ensures that our device nodes are created when not using X
		exeinto "$(get_udevdir)"
		doexe "${FILESDIR}"/nvidia-udev.sh
		udev_newrules "${FILESDIR}"/nvidia.udev-rule 99-nvidia.rules

	elif use kernel_FreeBSD; then
		if use x86-fbsd; then
			insinto /boot/modules
			doins "${S}/src/nvidia.kld" || die
		fi

		exeinto /boot/modules
		doexe "${S}/src/nvidia.ko" || die
	fi

	# NVIDIA kernel <-> userspace driver config lib
	donvidia ${NV_OBJ}/libnvidia-cfg.so ${NV_SOVER}

	if use kernel_linux; then
		# NVIDIA video decode <-> CUDA
		donvidia ${NV_OBJ}/libnvcuvid.so ${NV_SOVER}
	fi

	if use X; then
		# Xorg DDX driver
		insinto /usr/$(get_libdir)/xorg/modules/drivers
		doins ${NV_X11}/nvidia_drv.so || die "failed to install nvidia_drv.so"

		# Xorg GLX driver
		donvidia ${NV_X11}/libglx.so ${NV_SOVER} \
			/usr/$(get_libdir)/opengl/nvidia/extensions

		# XvMC driver
		dolib.a ${NV_X11}/libXvMCNVIDIA.a || \
			die "failed to install libXvMCNVIDIA.so"
		donvidia ${NV_X11}/libXvMCNVIDIA.so ${NV_SOVER}
		dosym libXvMCNVIDIA.so.${NV_SOVER} \
			/usr/$(get_libdir)/libXvMCNVIDIA_dynamic.so.1 || \
			die "failed to create libXvMCNVIDIA_dynamic.so symlink"
	fi

	# OpenCL ICD for NVIDIA
	if use kernel_linux; then
		insinto /etc/OpenCL/vendors
		doins nvidia.icd
		donvidia ${NV_OBJ}/libnvidia-opencl.so ${NV_SOVER}
	fi

	# Documentation
	dohtml ${NV_DOC}/html/*
	if use kernel_FreeBSD; then
		dodoc "${NV_DOC}/README"
		use X && doman "${NV_MAN}/nvidia-xconfig.1"
		use tools && doman "${NV_MAN}/nvidia-settings.1"
	else
		# Docs
		newdoc "${NV_DOC}/README.txt" README
		dodoc "${NV_DOC}/NVIDIA_Changelog"
		doman "${NV_MAN}/nvidia-smi.1.gz"
		use X && doman "${NV_MAN}/nvidia-xconfig.1.gz"
		use tools && doman "${NV_MAN}/nvidia-settings.1.gz"
		doman "${NV_MAN}/nvidia-cuda-proxy-control.1.gz"
	fi

	# Helper Apps
	exeinto /opt/bin/
	if use X; then
		doexe ${NV_OBJ}/nvidia-xconfig || die
	fi

	if use kernel_linux ; then
		doexe ${NV_OBJ}/nvidia-debugdump || die
		doexe ${NV_OBJ}/nvidia-cuda-proxy-control || die
		doexe ${NV_OBJ}/nvidia-cuda-proxy-server || die
		doexe ${NV_OBJ}/nvidia-smi || die
		newinitd "${FILESDIR}/nvidia-smi.init" nvidia-smi
	fi

	dobin ${NV_OBJ}/nvidia-bug-report.sh

	# Desktop entries for nvidia-settings
	if use tools ; then
		emake -C "${S}"/nvidia-settings-${PV}/src/ \
			DESTDIR="${D}" \
			LIBDIR="${D}/usr/$(get_libdir)" \
			PREFIX=/usr \
			NV_USE_BUNDLED_LIBJANSSON=0 \
			install

		if use static-libs; then
			dolib.a "${S}"/nvidia-settings-${PV}/src/libXNVCtrl/libXNVCtrl.a

			insinto /usr/include/NVCtrl
			doins "${S}"/nvidia-settings-${PV}/src/libXNVCtrl/*.h
		fi

		# There is no icon in the FreeBSD tarball.
		use kernel_FreeBSD || \
			doicon ${NV_OBJ}/nvidia-settings.png

		domenu "${FILESDIR}"/nvidia-settings.desktop

		exeinto /etc/X11/xinit/xinitrc.d
		newexe "${FILESDIR}"/95-nvidia-settings-r1 95-nvidia-settings
	fi

	if has_multilib_profile && use multilib ; then
		local OABI=${ABI}
		for ABI in $(get_install_abis) ; do
			src_install-libs
		done
		ABI=${OABI}
		unset OABI
	else
		src_install-libs
	fi

	is_final_abi || die "failed to iterate through all ABIs"

	# GNOME3 gnome-terminal redraw bug workaround,
	# see: https://bugzilla.gnome.org/show_bug.cgi?id=664858
	doenvd "${FILESDIR}/90mutter-disable-culling"
}

src_install-libs() {
	local inslibdir=$(get_libdir)
	local GL_ROOT="/usr/$(get_libdir)/opengl/nvidia/lib"
	local CL_ROOT="/usr/$(get_libdir)/OpenCL/vendors/nvidia"
	local libdir=${NV_OBJ}

	if use kernel_linux && has_multilib_profile && \
			[[ ${ABI} == "x86" ]] ; then
		libdir=${NV_OBJ}/32
	fi

	if use X; then
		# The GLX libraries
		donvidia ${libdir}/libGL.so ${NV_SOVER} ${GL_ROOT}
		donvidia ${libdir}/libnvidia-glcore.so ${NV_SOVER}
		if use kernel_FreeBSD; then
			donvidia ${libdir}/libnvidia-tls.so ${NV_SOVER} ${GL_ROOT}
		else
			donvidia ${libdir}/tls/libnvidia-tls.so ${NV_SOVER} ${GL_ROOT}
		fi

		# VDPAU
		donvidia ${libdir}/libvdpau_nvidia.so ${NV_SOVER}
	fi

	# NVIDIA monitoring library
	if use kernel_linux ; then
		donvidia ${libdir}/libnvidia-ml.so ${NV_SOVER}
	fi

	# CUDA & OpenCL
	if use kernel_linux; then
		donvidia ${libdir}/libcuda.so ${NV_SOVER}
		donvidia ${libdir}/libnvidia-compiler.so ${NV_SOVER}
		donvidia ${libdir}/libOpenCL.so 1.0.0 ${CL_ROOT}
	fi
}

pkg_preinst() {
	# Clean the dynamic libGL stuff's home to ensure
	# we dont have stale libs floating around
	if [ -d "${ROOT}"/usr/lib/opengl/nvidia ] ; then
		rm -rf "${ROOT}"/usr/lib/opengl/nvidia/*
	fi
	# Make sure we nuke the old nvidia-glx's env.d file
	if [ -e "${ROOT}"/etc/env.d/09nvidia ] ; then
		rm -f "${ROOT}"/etc/env.d/09nvidia
	fi

	local videogroup="$(getent group video | cut -d ':' -f 3)"
	if [ -n "${videogroup}" ]; then
		sed -i -e "s:PACKAGE:${PF}:g" \
			-e "s:27:${videogroup}:" "${ROOT}"/etc/modprobe.d/nvidia.conf
	else
		eerror "Failed to determine the video group gid."
		die "Failed to determine the video group gid."
	fi
}

pkg_postinst() {
	# Switch to the nvidia implementation
	use X && "${ROOT}"/usr/bin/eselect opengl set --use-old nvidia
	"${ROOT}"/usr/bin/eselect opencl set --use-old nvidia

	elog "You must be in the video group to use the NVIDIA device"
	elog "For more info, read the docs at"
	elog "http://www.gentoo.org/doc/en/nvidia-guide.xml#doc_chap3_sect6"
	elog
	elog "To use the NVIDIA GLX, run \"eselect opengl set nvidia\""
	elog
	elog "To use the NVIDIA CUDA/OpenCL, run \"eselect opencl set nvidia\""
	elog
	elog "NVIDIA has requested that any bug reports submitted have the"
	elog "output of /opt/bin/nvidia-bug-report.sh included."
	elog
	if ! use X; then
		elog "You have elected to not install the X.org driver. Along with"
		elog "this the OpenGL libraries, XvMC, and VDPAU libraries were not"
		elog "installed. Additionally, once the driver is loaded your card"
		elog "and fan will run at max speed which may not be desirable."
		elog "Use the 'nvidia-smi' init script to have your card and fan"
		elog "speed scale appropriately."
		elog
	fi
}

pkg_prerm() {
	use X && "${ROOT}"/usr/bin/eselect opengl set --use-old xorg-x11
}

pkg_postrm() {
	use X && "${ROOT}"/usr/bin/eselect opengl set --use-old xorg-x11
}
