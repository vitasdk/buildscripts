#!/usr/bin/env bash
# Groups per-host vitasdk-core/vdpm packages into Pacman repositories.
# Ported from vitasdk/autobuilds; with the RELEASE_* variables set, also
# writes release.json in the shape `verify` (next-refactor-verify) expects.

set -euo pipefail

if [[ $# -lt 2 ]]; then
	printf 'usage: %s <output-directory> <vitasdk-core-package>...\n' "$0" >&2
	exit 2
fi

output_directory=$1
shift
source_date_epoch=${SOURCE_DATE_EPOCH:-}

[[ -n $source_date_epoch && $source_date_epoch =~ ^[0-9]+$ ]] || {
	printf 'SOURCE_DATE_EPOCH must be set to a non-negative integer\n' >&2
	exit 1
}
[[ ! -e $output_directory ]] || {
	printf 'output path already exists: %s\n' "$output_directory" >&2
	exit 1
}
command -v repo-add >/dev/null
command -v bsdtar >/dev/null

output_parent=$(cd "$(dirname "$output_directory")" && pwd -P)
output_name=$(basename "$output_directory")
staging_directory=$(mktemp -d "$output_parent/.${output_name}.XXXXXXXX")
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-core-repositories.XXXXXXXX")
cleanup() {
	rm -rf -- "$staging_directory" "$temporary_directory"
}
trap cleanup EXIT

declare -A architectures=()
declare -A names=()
for package in "$@"; do
	[[ -f $package && ! -L $package ]] || {
		printf 'core package is not a regular file: %s\n' "$package" >&2
		exit 1
	}
	package_filename=${package##*/}
	pkginfo=$(bsdtar -xOf "$package" .PKGINFO)
	pkgname=$(awk -F ' = ' '$1 == "pkgname" { print $2; exit }' <<<"$pkginfo")
	pkgver=$(awk -F ' = ' '$1 == "pkgver" { print $2; exit }' <<<"$pkginfo")
	architecture=$(awk -F ' = ' '$1 == "arch" { print $2; exit }' <<<"$pkginfo")
	# A core release is the toolchain and the client that installs it, so a
	# host repository holds both and neither may appear twice.
	[[ ($pkgname == vitasdk-core || $pkgname == vdpm) && -n $pkgver && -n $architecture ]] || {
		printf 'invalid core package metadata: %s\n' "$package_filename" >&2
		exit 1
	}
	[[ $package_filename == "$pkgname-$pkgver-$architecture.pkg.tar."* ]] || {
		printf 'core package filename does not match metadata: %s\n' \
			"$package_filename" >&2
		exit 1
	}
	[[ " ${names[$architecture]:-} " != *" $pkgname "* ]] || {
		printf 'duplicate %s for %s\n' "$pkgname" "$architecture" >&2
		exit 1
	}
	names[$architecture]="${names[$architecture]:-} $pkgname"
	architectures[$architecture]="${architectures[$architecture]:-} $package_filename"
	cp -p "$package" "$staging_directory/$package_filename"
done

# The core declares a hard dependency on the client, so a repository carrying
# one without the other cannot install what it publishes.
for architecture in "${!names[@]}"; do
	for required in vitasdk-core vdpm; do
		[[ " ${names[$architecture]} " == *" $required "* ]] || {
			printf 'no %s for %s: the repository would publish a core that cannot be installed\n' \
				"$required" "$architecture" >&2
			exit 1
		}
	done
done

normalize_database() {
	local source_archive=$1 output_archive=$2 extraction_directory list_file
	extraction_directory=$(mktemp -d "$temporary_directory/database.XXXXXXXX")
	list_file=$(mktemp "$temporary_directory/list.XXXXXXXX")
	bsdtar -xf "$source_archive" -C "$extraction_directory"
	find "$extraction_directory" -exec touch -h -d "@$source_date_epoch" {} +
	(
		cd "$extraction_directory"
		find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort >"$list_file"
		bsdtar --format=gnutar --uid 0 --gid 0 --uname root --gname root \
			-cnf - -T "$list_file" | gzip -9 -n >"$output_archive"
	)
}

mapfile -t sorted_architectures < <(printf '%s\n' "${!architectures[@]}" | LC_ALL=C sort)
for architecture in ${sorted_architectures[@]+"${sorted_architectures[@]}"}; do
	read -r -a package_filenames <<<"${architectures[$architecture]}"
	packages=()
	for package_filename in ${package_filenames[@]+"${package_filenames[@]}"}; do
		packages+=("$staging_directory/$package_filename")
	done
	repo-add "$staging_directory/$architecture.db.tar.gz" ${packages[@]+"${packages[@]}"}
	normalize_database "$staging_directory/$architecture.db.tar.gz" \
		"$temporary_directory/$architecture.db"
	normalize_database "$staging_directory/$architecture.files.tar.gz" \
		"$temporary_directory/$architecture.files"
	rm -f "$staging_directory/$architecture.db" \
		"$staging_directory/$architecture.db.tar.gz" \
		"$staging_directory/$architecture.files" \
		"$staging_directory/$architecture.files.tar.gz"
	mv "$temporary_directory/$architecture.db" "$staging_directory/$architecture.db"
	mv "$temporary_directory/$architecture.files" "$staging_directory/$architecture.files"
done

if [[ -n ${SDK_ARCHIVE_DIRECTORY:-} ]]; then
	[[ -d $SDK_ARCHIVE_DIRECTORY ]] || {
		printf 'SDK archive directory not found: %s\n' "$SDK_ARCHIVE_DIRECTORY" >&2
		exit 1
	}
	while IFS= read -r -d '' sdk_archive; do
		archive_filename=${sdk_archive##*/}
		[[ ! -e $staging_directory/$archive_filename ]] || {
			printf 'duplicate SDK archive: %s\n' "$archive_filename" >&2
			exit 1
		}
		cp -p "$sdk_archive" "$staging_directory/$archive_filename"
	done < <(
		# vitasdk-sysroot-* is stage 1's internal artifact, not a host SDK.
		find "$SDK_ARCHIVE_DIRECTORY" -type f \
			\( -name 'vitasdk-*.tar.bz2' -o -name 'vitasdk-*.tar.bz2.sha256' \) \
			! -name 'vitasdk-sysroot-*' \
			-print0 |
			LC_ALL=C sort -z
	)
fi

if [[ -n ${RELEASE_SCHEMA:-}${RELEASE_BUILD_ID:-}${RELEASE_BUILDSCRIPTS_REVISION:-}${RELEASE_PROFILE:-}${RELEASE_PROVENANCE_DIRECTORY:-} ]]; then
	for var in RELEASE_SCHEMA RELEASE_BUILD_ID RELEASE_BUILDSCRIPTS_REVISION RELEASE_PROFILE RELEASE_PROVENANCE_DIRECTORY; do
		[[ -n ${!var:-} ]] || {
			printf '%s must be set alongside the other RELEASE_* variables\n' "$var" >&2
			exit 1
		}
	done
	[[ -d $RELEASE_PROVENANCE_DIRECTORY ]] || {
		printf 'release provenance directory not found: %s\n' "$RELEASE_PROVENANCE_DIRECTORY" >&2
		exit 1
	}
	# No python3 assumed: the grouping container does not carry one.
	json_escape() {
		local s=$1
		s=${s//\\/\\\\}
		s=${s//\"/\\\"}
		printf '%s' "$s"
	}
	json_string_array() {
		local first=1 item
		printf '['
		for item in "$@"; do
			[[ $first == 1 ]] && first=0 || printf ','
			printf '"%s"' "$(json_escape "$item")"
		done
		printf ']'
	}
	# Stage-1 dirs are skipped: a lock may reuse a host name at stage 1 (the
	# sysroot producer) as well as the stage where it publishes packages.
	provenance_build_id_for_host() {
		local target=$1 dir=$2 file file_host
		for file in "$dir"/*/provenance.json; do
			[[ -f $file ]] || continue
			case $file in "$dir"/stage1-*/provenance.json) continue ;; esac
			file_host=$(sed -n 's/^  "host": "\(.*\)",\{0,1\}$/\1/p' "$file")
			[[ $file_host == "$target" ]] || continue
			sed -n 's/^  "build_id": "\(.*\)",\{0,1\}$/\1/p' "$file"
			return 0
		done
		return 1
	}

	host_fragments=()
	for architecture in ${sorted_architectures[@]+"${sorted_architectures[@]}"}; do
		host_artifacts=("$architecture.db" "$architecture.files")
		read -r -a package_filenames <<<"${architectures[$architecture]}"
		host_artifacts+=(${package_filenames[@]+"${package_filenames[@]}"})
		while IFS= read -r -d '' extra; do
			host_artifacts+=("$(basename "$extra")")
		done < <(find "$staging_directory" -maxdepth 1 -type f \
			\( -name "vitasdk-bootstrap-$architecture.tar.bz2*" -o -name "vitasdk-$architecture-*.tar.bz2*" \) -print0)

		build_id=$(provenance_build_id_for_host "$architecture" "$RELEASE_PROVENANCE_DIRECTORY")
		[[ -n $build_id ]] || {
			printf 'no provenance echo found for published host: %s\n' "$architecture" >&2
			exit 1
		}
		host_fragments+=("{\"name\":\"$(json_escape "$architecture")\",\"build_id\":\"$(json_escape "$build_id")\",\"artifacts\":$(json_string_array ${host_artifacts[@]+"${host_artifacts[@]}"})}")
	done

	hosts_joined=$(
		IFS=,
		printf '%s' "${host_fragments[*]}"
	)
	cat >"$staging_directory/release.json" <<EOF
{
  "schema": $RELEASE_SCHEMA,
  "build_id": "$(json_escape "$RELEASE_BUILD_ID")",
  "buildscripts_revision": "$(json_escape "$RELEASE_BUILDSCRIPTS_REVISION")",
  "profile": "$(json_escape "$RELEASE_PROFILE")",
  "hosts": [$hosts_joined]
}
EOF
fi

(
	cd "$staging_directory"
	while IFS= read -r asset; do
		sha256sum -- "$asset"
	done < <(
		find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' |
			LC_ALL=C sort
	) >SHA256SUMS
)

mv "$staging_directory" "$output_directory"
printf 'created grouped core repositories: %s\n' "$output_directory"
