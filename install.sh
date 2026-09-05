#!/bin/sh

set -eu

# Keep these sentinels split so release publishing only rewrites the configured
# values below; local or unpublished copies still need unreplaced values to compare.
acryl_unconfigured_base_url="__ACRYL_DOWNLOAD_BASE""_URL__"
acryl_unconfigured_default_release_channel="__ACRYL_DEFAULT_RELEASE_""CHANNEL__"
acryl_base_url="${ACRYL_DOWNLOAD_BASE_URL:-__ACRYL_DOWNLOAD_BASE_URL__}"
acryl_base_url="${acryl_base_url%/}"
acryl_default_release_channel="__ACRYL_DEFAULT_RELEASE_CHANNEL__"
if [ "$acryl_default_release_channel" = "$acryl_unconfigured_default_release_channel" ]; then
	acryl_default_release_channel=stable
fi
acryl_release_channel="${ACRYL_RELEASE_CHANNEL:-$acryl_default_release_channel}"
acryl_package="${ACRYL_PACKAGE:-acryl}"
acryl_cmd="${ACRYL_CMD:-acryl}"
acryl_esc=$(printf '\033')
acryl_original_path="${PATH:-}"
acryl_reset="${acryl_esc}[0m"
acryl_bold="${acryl_esc}[1m"
acryl_italic="${acryl_esc}[3m"
acryl_hide_cursor="${acryl_esc}[?25l"
acryl_show_cursor="${acryl_esc}[?25h"
acryl_home_cursor="${acryl_esc}[H"
acryl_clear_screen="${acryl_esc}[2J${acryl_esc}[H"
acryl_clear_line="${acryl_esc}[K"
acryl_sync_start="${acryl_esc}[?2026h"
acryl_sync_end="${acryl_esc}[?2026l"
acryl_color_text="${acryl_esc}[38;2;244;244;245m"
acryl_color_muted="${acryl_esc}[38;2;161;161;170m"
acryl_color_dim="${acryl_esc}[38;2;113;113;122m"
acryl_color_primary="${acryl_esc}[38;2;127;91;213m"
acryl_color_scan="${acryl_esc}[38;2;14;165;233m"
acryl_color_warning="${acryl_esc}[38;2;245;158;11m"
readonly acryl_unconfigured_base_url acryl_unconfigured_default_release_channel acryl_base_url acryl_default_release_channel acryl_release_channel acryl_package acryl_cmd acryl_esc acryl_original_path
readonly acryl_reset acryl_bold acryl_italic acryl_hide_cursor acryl_show_cursor acryl_home_cursor acryl_clear_screen acryl_clear_line
readonly acryl_sync_start acryl_sync_end
readonly acryl_color_text acryl_color_muted acryl_color_dim acryl_color_primary acryl_color_scan acryl_color_warning

acryl_screen_enabled=0
acryl_screen_frame=0
acryl_screen_cols=80
acryl_screen_rows=24
acryl_screen_drawn=0
acryl_screen_last_cols=0
acryl_screen_last_rows=0
acryl_screen_layout_ready=0
acryl_screen_layout_show_logo=0
acryl_screen_layout_lab_width=0
acryl_screen_render_lab_width=0
acryl_screen_compact=0
acryl_download_dir=
acryl_bootstrap_kernel_on_install=0
acryl_screen_title=
acryl_screen_status=
acryl_screen_detail=
acryl_screen_question=
acryl_animation_frame=0

main() {
	if [ "$acryl_base_url" = "$acryl_unconfigured_base_url" ]; then
		printf 'error: installer download URL is not configured.\n' >&2
		printf 'Set ACRYL_DOWNLOAD_BASE_URL or use the installer published by the release workflow.\n' >&2
		exit 1
	fi

	acryl_install_traps
	acryl_init_screen
	if [ "$acryl_screen_enabled" = 1 ]; then
		acryl_screen "Installing ACRYL" "" "" ""
	else
		printf '\n\033[1m  Installing ACRYL\033[0m\n\033[2m  npm global install\033[0m\n\n'
	fi

	start_preflight_checks

	if finish_preflight_checks; then
		check_status=0
	else
		check_status=$?
	fi

	if [ "$check_status" -ne 0 ]; then
		if ! install_node_npm_interactive; then
			exit "$check_status"
		fi

		start_preflight_checks
		if finish_preflight_checks; then
			check_status=0
		else
			check_status=$?
		fi

		if [ "$check_status" -ne 0 ]; then
			exit "$check_status"
		fi
	fi

	version="$(resolve_acryl_version "$@")"
	tarball_name="$acryl_package-$version.tgz"
	tarball_url="$acryl_base_url/releases/v$version/$tarball_name"

	confirm_install "$version" "$tarball_url"
	confirm_kernel_runtime_setup

	download_dir=$(create_temp_dir)
	acryl_download_dir="$download_dir"
	tarball_path="$download_dir/$tarball_name"

	download_acryl_package "$version" "$tarball_url" "$tarball_path"
	install_acryl_package "$tarball_path"
	rm -rf "$download_dir"
	acryl_download_dir=

	if [ "${ACRYL_NODE_INSTALLED_STANDALONE:-0}" = 1 ]; then
		acryl_screen "ACRYL installed" "" "Checking your shell PATH." ""
		configure_standalone_node_path
	elif command -v "$acryl_cmd" >/dev/null 2>&1; then
		if [ "$acryl_screen_enabled" = 1 ]; then
			acryl_screen "ACRYL installed" "" "Run it with: $acryl_cmd" ""
		else
			printf '\nACRYL was installed successfully.\n'
			printf '\nRun it with: %s\n' "$acryl_cmd"
		fi
	else
		if [ "$acryl_screen_enabled" = 1 ]; then
			acryl_screen "ACRYL installed" "" "PATH update needed for $acryl_cmd." ""
			acryl_restore_terminal
		else
			printf '\nACRYL was installed successfully.\n'
		fi
		cat <<EOF
The $acryl_cmd command was installed, but it is not on your PATH yet.
Check npm's global bin directory with:

  npm bin -g

Then add that directory to your shell PATH.
EOF
	fi
}

create_temp_dir() {
	if command -v mktemp >/dev/null 2>&1; then
		if tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/acryl-install.XXXXXX" 2>/dev/null); then
			printf '%s' "$tmp_dir"
			return
		fi
	fi

	printf 'error: mktemp is required to create a secure temporary directory.\n' >&2
	exit 1
}

acryl_install_traps() {
	trap 'acryl_cleanup' EXIT
	trap 'acryl_signal_cleanup 130' INT
	trap 'acryl_signal_cleanup 143' TERM
}

acryl_cleanup() {
	status=$?
	if [ -n "${acryl_download_dir:-}" ] && [ -d "$acryl_download_dir" ]; then
		rm -rf "$acryl_download_dir"
	fi
	acryl_restore_terminal
	return "$status"
}

acryl_signal_cleanup() {
	acryl_restore_terminal
	exit "$1"
}

acryl_restore_terminal() {
	if [ "${acryl_screen_enabled:-0}" = 1 ]; then
		if ( : <>/dev/tty ) 2>/dev/null; then
			printf '%s%s' "$acryl_reset" "$acryl_show_cursor" >/dev/tty
		else
			printf '%s%s' "$acryl_reset" "$acryl_show_cursor" >&2
		fi
	fi
}

acryl_init_screen() {
	if [ "${ACRYL_INSTALLER_PLAIN:-0}" = 1 ]; then
		return
	fi
	if [ ! -t 1 ]; then
		return
	fi
	if [ "${TERM:-}" = dumb ]; then
		return
	fi
	acryl_screen_enabled=1
}

acryl_read_terminal_size() {
	acryl_screen_cols=80
	acryl_screen_rows=24

	if size=$(stty size 2>/dev/null </dev/tty); then
		set -- $size
		if [ "${1:-}" ] && [ "${2:-}" ]; then
			case "$1" in *[!0-9]*|"") ;; *) acryl_screen_rows="$1" ;; esac
			case "$2" in *[!0-9]*|"") ;; *) acryl_screen_cols="$2" ;; esac
		fi
	fi

	if [ "$acryl_screen_cols" -lt 1 ]; then
		acryl_screen_cols=80
	fi
	if [ "$acryl_screen_rows" -lt 1 ]; then
		acryl_screen_rows=24
	fi
}

acryl_screen() {
	if [ "$acryl_screen_enabled" != 1 ]; then
		return
	fi

	acryl_screen_title="${2:-$1}"
	if [ -z "$acryl_screen_title" ]; then
		acryl_screen_title="$1"
	fi
	acryl_screen_status=
	acryl_screen_detail="${3:-}"
	acryl_screen_question="${4:-}"
	acryl_screen_frame=$((acryl_screen_frame + 1))
	acryl_read_terminal_size
	acryl_init_screen_layout
	acryl_refresh_screen_layout_mode

	if [ "$acryl_screen_drawn" = 0 ] ||
		[ "$acryl_screen_cols" -ne "$acryl_screen_last_cols" ] ||
		[ "$acryl_screen_rows" -ne "$acryl_screen_last_rows" ]; then
		acryl_screen_prefix="${acryl_reset}${acryl_clear_screen}${acryl_hide_cursor}"
		acryl_screen_drawn=1
		acryl_screen_last_cols="$acryl_screen_cols"
		acryl_screen_last_rows="$acryl_screen_rows"
	else
		acryl_screen_prefix="${acryl_reset}${acryl_home_cursor}${acryl_hide_cursor}"
	fi
	acryl_screen_frame_text=$(acryl_render_screen)

	if ( : <>/dev/tty ) 2>/dev/null; then
		printf '%s%s%s%s' "$acryl_sync_start" "$acryl_screen_prefix" "$acryl_screen_frame_text" "$acryl_sync_end" >/dev/tty
	else
		printf '%s%s%s%s' "$acryl_sync_start" "$acryl_screen_prefix" "$acryl_screen_frame_text" "$acryl_sync_end" >&2
	fi
}

acryl_init_screen_layout() {
	if [ "$acryl_screen_layout_ready" = 1 ]; then
		return
	fi

	acryl_screen_layout_ready=1
	acryl_screen_layout_show_logo=0
	acryl_screen_layout_lab_width=0
	acryl_screen_render_lab_width=0
	if acryl_terminal_size_supports_logo; then
		acryl_screen_layout_show_logo=1
		acryl_screen_layout_lab_width=$(acryl_lab_width_for_cols "$acryl_screen_cols")
	fi
}

acryl_refresh_screen_layout_mode() {
	acryl_screen_compact=0
	acryl_screen_render_lab_width=0
	if [ "$acryl_screen_layout_show_logo" != 1 ]; then
		return
	fi
	if [ "$acryl_screen_rows" -lt 17 ]; then
		acryl_screen_compact=1
		return
	fi

	max_safe_width=$((acryl_screen_cols - 1))
	if [ "$max_safe_width" -lt 32 ]; then
		acryl_screen_compact=1
		return
	fi

	acryl_screen_render_lab_width="$acryl_screen_layout_lab_width"
	if [ "$acryl_screen_render_lab_width" -gt "$max_safe_width" ]; then
		acryl_screen_render_lab_width="$max_safe_width"
	fi
}

acryl_terminal_size_supports_logo() {
	[ "$acryl_screen_rows" -ge 22 ] && [ "$acryl_screen_cols" -ge 42 ]
}

acryl_lab_width_for_cols() {
	cols="$1"
	width=$((cols - 6))
	if [ "$width" -gt 78 ]; then
		width=78
	fi
	if [ "$width" -lt 42 ]; then
		width=42
	fi
	max_safe_width=$((cols - 1))
	if [ "$max_safe_width" -lt 1 ]; then
		max_safe_width=1
	fi
	if [ "$width" -gt "$max_safe_width" ]; then
		width="$max_safe_width"
	fi
	if [ "$width" -lt 32 ]; then
		width=32
	fi
	printf '%s' "$width"
}

acryl_render_screen() {
	content_height=$(acryl_content_height)
	top=$(((acryl_screen_rows - content_height) / 2))
	if [ "$top" -lt 0 ]; then
		top=0
	fi

	y=0
	while [ "$y" -lt "$acryl_screen_rows" ]; do
		content_index=$((y - top))
		acryl_content_line "$content_index"
		if [ "${acryl_content_is_set:-0}" = 1 ]; then
			acryl_print_centered_line "$acryl_content_text" "$acryl_content_width" "$acryl_content_style"
		else
			acryl_print_centered_line "" 0 ""
		fi
		y=$((y + 1))
	done
}

acryl_content_height() {
	height=2
	if acryl_show_logo; then
		height=$((height + 15))
	fi
	printf '%s' "$height"
}

acryl_show_logo() {
	[ "$acryl_screen_layout_show_logo" = 1 ] && [ "$acryl_screen_compact" != 1 ] && [ "$acryl_screen_render_lab_width" -ge 32 ]
}

acryl_content_line() {
	index="$1"
	acryl_content_is_set=0
	acryl_content_text=
	acryl_content_width=0
	acryl_content_style=

	if acryl_show_logo; then
		case "$index" in
			0|1|2|3|4|5|6|7|8|9|10|11|12|13) acryl_set_lab_line "$index" ;;
			14) acryl_set_blank_line ;;
		esac
		if [ "$acryl_content_is_set" = 1 ]; then
			return
		fi
		index=$((index - 15))
	fi

	if [ "$index" -lt 0 ]; then
		return
	fi

	if [ "$index" -eq 0 ]; then
		if [ -n "$acryl_screen_question" ]; then
			acryl_set_text_line "$(acryl_screen_primary_text)" "$acryl_bold$acryl_color_text"
		else
			acryl_set_title_line "$acryl_screen_title"
		fi
		return
	fi

	if [ "$index" -eq 1 ]; then
		if [ -n "$acryl_screen_question" ]; then
			acryl_set_text_line "Press Enter to continue; type n to cancel." "$acryl_color_muted"
		elif [ -n "$acryl_screen_detail" ]; then
			acryl_set_text_line "$acryl_screen_detail" "$acryl_color_muted"
		else
			acryl_set_blank_line
		fi
		return
	fi
}

acryl_screen_primary_text() {
	if [ -z "$acryl_screen_question" ]; then
		printf '%s' "$acryl_screen_title"
		return
	fi

	case "$acryl_screen_question" in
		*'[Y/n]'*) printf '%s [Y/n] >' "$acryl_screen_title" ;;
		*) printf '%s %s' "$acryl_screen_title" "$acryl_screen_question" ;;
	esac
}

acryl_set_lab_line() {
	lab_row="$1"
	acryl_lab_width="$acryl_screen_render_lab_width"

	logo_line=$(acryl_logo_line "$lab_row")
	if [ -n "$logo_line" ]; then
		logo_start=$(((acryl_lab_width - 32) / 2))
		logo_end=$((logo_start + 32))
		left=$(acryl_lab_background_range "$lab_row" 0 "$logo_start")
		right=$(acryl_lab_background_range "$lab_row" "$logo_end" "$acryl_lab_width")
		trace="${left}${acryl_color_text}${logo_line}${acryl_reset}${right}"
	else
		trace=$(acryl_lab_background_range "$lab_row" 0 "$acryl_lab_width")
	fi

	acryl_content_is_set=1
	acryl_content_text="$trace"
	acryl_content_width="$acryl_lab_width"
	acryl_content_style=
}

acryl_logo_line() {
	case "$1" in
		2) printf '                          ▄▄███▀' ;;
		3) printf '    ▄▄▄▄▄              ▄█████▀' ;;
		4) printf '    ██████▄         ▄██████▀' ;;
		5) printf '   ▄███▀███▄     ▄███▀▄██▀' ;;
		6) printf '   ███ ▄████▄▄▄████▀▄▄██' ;;
		7) printf '  ▀██  ▀█████████▀▀▀▀▀▀' ;;
		8) printf '  ▄██   ██████▀▀ ▄███' ;;
		9) printf ' █████    ▀█▄▄▄█████▀' ;;
		10) printf '███████▄  ████████▀' ;;
		11) printf '▀███▀▀    █████▀' ;;
	esac
}

acryl_lab_background_range() {
	lab_row="$1"
	range_start="$2"
	range_end="$3"
	active_style=
	line=
	x="$range_start"
	while [ "$x" -lt "$range_end" ]; do
		acryl_lab_cell "$x" "$lab_row"
		if [ "$acryl_lab_cell_style" != "$active_style" ]; then
			if [ -n "$active_style" ]; then
				line="${line}${acryl_reset}"
			fi
			if [ -n "$acryl_lab_cell_style" ]; then
				line="${line}${acryl_lab_cell_style}"
			fi
			active_style="$acryl_lab_cell_style"
		fi
		line="${line}${acryl_lab_cell_char}"
		x=$((x + 1))
	done
	if [ -n "$active_style" ]; then
		line="${line}${acryl_reset}"
	fi
	printf '%s' "$line"
}

acryl_lab_cell() {
	x="$1"
	y="$2"
	width="$acryl_lab_width"
	height=14
	frame="$acryl_screen_frame"
	acryl_lab_cell_char=" "
	acryl_lab_cell_style=

	hash=$(((x * 37 + y * 53 + frame * 11 + x * y * 3) % 101))
	if [ "$hash" -lt 3 ]; then
		acryl_lab_cell_char="·"
		acryl_lab_cell_style="$acryl_color_dim"
	fi

	center_x=$((width * 36 / 100))
	center_y=$((height * 54 / 100))
	dx=$((x - center_x))
	dy=$((y - center_y))
	if [ "$dx" -lt 0 ]; then
		dx=$((-dx))
	fi
	if [ "$dy" -lt 0 ]; then
		dy=$((-dy))
	fi
	contour=$((dx + dy * 4 + x / 6 - frame))
	if [ "$x" -lt $((width * 82 / 100)) ] && [ $(((contour % 24 + 24) % 24)) -eq 12 ]; then
		if [ $(((x + y) % 5)) -eq 0 ]; then
			acryl_lab_cell_char="╌"
		else
			acryl_lab_cell_char="·"
		fi
		acryl_lab_cell_style="$acryl_color_dim"
	fi

	horizon_y=$((height * 58 / 100))
	if [ "$y" -eq "$horizon_y" ] && [ $((x % 2)) -eq 0 ] && [ $(((x + frame) % 13)) -lt 2 ]; then
		acryl_lab_cell_char="─"
		if [ "$x" -gt $((width * 60 / 100)) ]; then
			acryl_lab_cell_style="$acryl_color_primary"
		else
			acryl_lab_cell_style="$acryl_color_dim"
		fi
	fi

	scan_start=$((width / 2))
	if [ "$x" -ge "$scan_start" ]; then
		scan_offset=$((x - scan_start))
		if [ $((scan_offset % 5)) -eq 0 ]; then
			scan_index=$((scan_offset / 5))
			scan_top=$((1 + (scan_index + frame / 3) % 3))
			scan_bottom=$((height - 2 - (scan_index * 2 + frame / 4) % 3))
			if [ "$y" -ge "$scan_top" ] && [ "$y" -le "$scan_bottom" ] && [ $(((y + scan_index + frame) % 6)) -ne 0 ]; then
				if [ $(((scan_index + y) % 4)) -eq 0 ]; then
					acryl_lab_cell_char="┃"
				else
					acryl_lab_cell_char="╎"
				fi
				acryl_lab_cell_style="$acryl_color_scan"
			fi
		fi
	fi

	trace_index=0
	while [ "$trace_index" -lt 3 ]; do
		case "$trace_index" in
			0) base=$((height * 30 / 100)) ;;
			1) base=$((height * 49 / 100)) ;;
			*) base=$((height * 72 / 100)) ;;
		esac
		wave=$(((x * 2 + frame + trace_index * 7) % 16))
		if [ "$wave" -gt 7 ]; then
			wave=$((15 - wave))
		fi
		trace_y=$((base + (wave - 3) / 2))
		if [ "$y" -eq "$trace_y" ]; then
			if [ $(((x + frame + trace_index * 13) % 41)) -eq 0 ]; then
				acryl_lab_cell_char="◆"
				acryl_lab_cell_style="$acryl_color_warning"
			elif [ $(((x + frame) % 12)) -eq 0 ]; then
				acryl_lab_cell_char="•"
				acryl_lab_cell_style="$acryl_color_primary"
			else
				acryl_lab_cell_char="·"
				acryl_lab_cell_style="$acryl_color_primary"
			fi
		fi
		trace_index=$((trace_index + 1))
	done
}

acryl_set_blank_line() {
	acryl_content_is_set=1
	acryl_content_text=
	acryl_content_width=0
	acryl_content_style=
}

acryl_set_text_line() {
	max_width=$((acryl_screen_cols - 4))
	if [ "$max_width" -lt 1 ]; then
		max_width=1
	fi
	acryl_content_text=$(acryl_fit_ascii "$1" "$max_width")
	acryl_content_width=${#acryl_content_text}
	acryl_content_style="$2"
	acryl_content_is_set=1
}

acryl_set_title_line() {
	max_width=$((acryl_screen_cols - 4))
	if [ "$max_width" -lt 1 ]; then
		max_width=1
	fi
	acryl_content_text=$(acryl_fit_ascii "$1" "$max_width")
	acryl_content_width=${#acryl_content_text}
	case "$acryl_content_text" in
		*"ACRYL"*)
			acryl_content_text=$(acryl_style_acryl_title "$acryl_content_text")
			acryl_content_style=
			;;
		*)
			acryl_content_style="$acryl_bold$acryl_color_primary"
			;;
	esac
	acryl_content_is_set=1
}

acryl_style_acryl_title() {
	text="$1"
	styled=
	while :; do
		case "$text" in
			*"ACRYL"*)
				before=${text%%ACRYL*}
				rest=${text#*ACRYL}
				styled="${styled}${acryl_bold}${acryl_color_primary}${before}"
				styled="${styled}${acryl_bold}${acryl_color_primary}ACRYL${acryl_reset}"
				text="$rest"
				;;
			*)
				styled="${styled}${acryl_bold}${acryl_color_primary}${text}${acryl_reset}"
				printf '%s' "$styled"
				return
				;;
		esac
	done
}

acryl_fit_ascii() {
	text="$1"
	max_width="$2"
	if [ "${#text}" -le "$max_width" ]; then
		printf '%s' "$text"
		return
	fi
	if [ "$max_width" -le 3 ]; then
		printf '%s' "$text" | cut -c 1-"$max_width"
		return
	fi
	cut_width=$((max_width - 3))
	printf '%s...' "$(printf '%s' "$text" | cut -c 1-"$cut_width")"
}

acryl_print_centered_line() {
	text="$1"
	width="$2"
	style="$3"
	left=$(((acryl_screen_cols - width) / 2))
	if [ "$left" -lt 0 ]; then
		left=0
	fi
	if [ -n "$style" ]; then
		printf '%*s%s%s%s%s\n' "$left" "" "$style" "$text" "$acryl_reset" "$acryl_clear_line"
	else
		printf '%*s%s%s\n' "$left" "" "$text" "$acryl_clear_line"
	fi
}

acryl_place_prompt_cursor() {
	max_width=$((acryl_screen_cols - 4))
	if [ "$max_width" -lt 1 ]; then
		max_width=1
	fi
	prompt_text=$(acryl_fit_ascii "$(acryl_screen_primary_text)" "$max_width")
	prompt_width=${#prompt_text}
	content_height=$(acryl_content_height)
	top=$(((acryl_screen_rows - content_height) / 2))
	if [ "$top" -lt 0 ]; then
		top=0
	fi
	prompt_index=0
	if acryl_show_logo; then
		prompt_index=$((prompt_index + 15))
	fi
	row=$((top + prompt_index + 1))
	col=$(((acryl_screen_cols - prompt_width) / 2 + prompt_width + 2))
	if [ "$col" -lt 1 ]; then
		col=1
	fi
	if [ "$col" -gt "$acryl_screen_cols" ]; then
		col="$acryl_screen_cols"
	fi
	if ( : <>/dev/tty ) 2>/dev/null; then
		printf '%s%s%s[%s;%sH' "$acryl_reset" "$acryl_show_cursor" "$acryl_esc" "$row" "$col" >/dev/tty
	else
		printf '%s%s%s[%s;%sH' "$acryl_reset" "$acryl_show_cursor" "$acryl_esc" "$row" "$col" >&2
	fi
}

acryl_pulse() {
	case $((acryl_screen_frame % 4)) in
		0) printf '.' ;;
		1) printf '..' ;;
		2) printf '...' ;;
		*) printf '' ;;
	esac
}

acryl_animation_detail_count() {
	details="$1"
	case "$details" in
		*'
'*) printf '%s\n' "$details" | wc -l | tr -d ' ' ;;
		*) printf '1' ;;
	esac
}

acryl_animation_current_frame() {
	frame="${acryl_animation_frame:-1}"
	case "$frame" in
		""|*[!0-9]*) frame=1 ;;
	esac
	if [ "$frame" -lt 1 ]; then
		frame=1
	fi
	printf '%s' "$frame"
}

acryl_animation_step_index() {
	details="$1"
	detail_count=$(acryl_animation_detail_count "$details")
	frame=$(acryl_animation_current_frame)
	detail_index=$(((frame - 1) / 24 + 1))
	if [ "$detail_index" -gt "$detail_count" ]; then
		detail_index="$detail_count"
	fi
	printf '%s' "$detail_index"
}

acryl_static_progress_title() {
	case "$1" in
		*...) printf '%s' "$1" ;;
		*) printf '%s...' "$1" ;;
	esac
}

acryl_animation_status() {
	status="$1"
	details="$2"
	status_mode="$3"
	case "$status_mode" in
		static) acryl_static_progress_title "$status" ;;
		*) printf '%s%s' "$status" "$(acryl_pulse)" ;;
	esac
}

acryl_animation_detail() {
	details="$1"
	case "$details" in
		*'
'*)
			detail_index=$(acryl_animation_step_index "$details")
			printf '%s\n' "$details" | sed -n "${detail_index}p"
			;;
		*) printf '%s' "$details" ;;
	esac
}

acryl_run_quiet_with_animation() {
	title="$1"
	status="$2"
	detail="$3"
	shift 3

	acryl_run_quiet_with_animation_command "$title" "$status" "$detail" pulse "$@"
}

acryl_run_quiet_with_animation_steps() {
	title="$1"
	status="$2"
	details="$3"
	shift 3

	acryl_run_quiet_with_animation_command "$title" "$status" "$details" static "$@"
}

acryl_run_quiet_with_animation_command() {
	title="$1"
	status="$2"
	details="$3"
	status_mode="$4"
	shift 4

	if [ "$acryl_screen_enabled" != 1 ]; then
		printf '%s\n' "$status" >&2
		"$@"
		return
	fi

	output_dir=$(create_temp_dir)
	output_file="$output_dir/output"
	"$@" >"$output_file" 2>&1 &
	command_pid=$!
	acryl_animation_frame=0

	while kill -0 "$command_pid" 2>/dev/null; do
		acryl_animation_frame=$((acryl_animation_frame + 1))
		status_display=$(acryl_animation_status "$status" "$details" "$status_mode")
		acryl_screen "$title" "$status_display" "$(acryl_animation_detail "$details")" ""
		sleep 0.18
	done

	if wait "$command_pid"; then
		command_status=0
	else
		command_status=$?
	fi

	if [ "$command_status" -ne 0 ] && [ -s "$output_file" ]; then
		acryl_restore_terminal
		printf '\n' >&2
		cat "$output_file" >&2
	fi
	rm -rf "$output_dir"
	return "$command_status"
}

acryl_prompt_yes_no() {
	question="$1"
	detail="$2"
	input_prompt="$3"

	if ( : <>/dev/tty ) 2>/dev/null; then
		prompt_input=tty
		exec 3<>/dev/tty
	elif [ -t 0 ]; then
		prompt_input=stdin
	else
		return 2
	fi

	if [ "$acryl_screen_enabled" = 1 ]; then
		acryl_screen "$question" "" "$detail" "$input_prompt"
		acryl_place_prompt_cursor "$input_prompt"
	else
		printf '%s\n' "$detail"
		if [ "$prompt_input" = tty ]; then
			printf '%s ' "$input_prompt" >&3
		else
			printf '%s ' "$input_prompt" >&2
		fi
	fi

	if [ "$prompt_input" = tty ]; then
		if ! IFS= read -r answer <&3; then
			answer=
		fi
		exec 3>&-
	else
		if ! IFS= read -r answer; then
			answer=
		fi
	fi

	case "$answer" in
		n|N|no|NO)
			return 1
			;;
	esac
	return 0
}

start_preflight_checks() {
	preflight_dir=$(create_temp_dir)
	preflight_file="$preflight_dir/preflight"
	run_preflight_checks >"$preflight_file" &
	preflight_pid=$!
}

finish_preflight_checks() {
	if [ "$acryl_screen_enabled" = 1 ]; then
		while kill -0 "$preflight_pid" 2>/dev/null; do
			acryl_screen "Checking Node.js and npm$(acryl_pulse)" "" "" ""
			sleep 0.18
		done
	fi

	if wait "$preflight_pid"; then
		preflight_status=0
	else
		preflight_status=$?
	fi

	if [ "$acryl_screen_enabled" = 1 ]; then
		if [ "$preflight_status" -ne 0 ]; then
			preflight_summary=$(sed -n '1p' "$preflight_file")
			acryl_screen "Node.js 20.6.0 or newer is required" "" "$preflight_summary" ""
			sleep 0.4
		elif [ -s "$preflight_file" ]; then
			preflight_summary="Existing $acryl_cmd command found on PATH."
			acryl_screen "Environment ready" "" "$preflight_summary" ""
			sleep 0.4
		fi
	else
		cat "$preflight_file"
	fi
	rm -rf "$preflight_dir"
	return "$preflight_status"
}

run_preflight_checks() {
	status=0
	yellow="${acryl_esc}[33m"
	reset="${acryl_esc}[0m"

	if command -v node >/dev/null 2>&1; then
		node_version=$(node --version)
		if ! node -e 'const [major, minor, patch] = process.versions.node.split(".").map(Number); process.exit(major > 20 || (major === 20 && (minor > 6 || (minor === 6 && patch >= 0))) ? 0 : 1)' >/dev/null; then
			printf 'error: ACRYL requires Node.js 20.6.0 or newer. Found %s.\n' "$node_version"
			status=1
		fi
	else
		printf 'error: Node.js 20.6.0 or newer is required to install ACRYL.\n'
		status=1
	fi

	if ! command -v npm >/dev/null 2>&1; then
		printf 'error: npm is required to install ACRYL.\n'
		status=1
	fi

	if [ "$status" -ne 0 ]; then
		printf '\n'
	fi

	if acryl_path=$(command -v "$acryl_cmd" 2>/dev/null); then
		printf '%sExisting %s found at: %s%s\n' "$yellow" "$acryl_cmd" "$acryl_path" "$reset"
		printf '\n'
	fi

	return "$status"
}

resolve_acryl_version() {
	if [ "${1:-}" ]; then
		case "$1" in
			stable|beta) release_channel="$1" ;;
			*)
				normalize_version "$1"
				return
				;;
		esac
	else
		release_channel="$acryl_release_channel"
	fi

	if [ "${ACRYL_VERSION:-}" ]; then
		normalize_version "$ACRYL_VERSION"
		return
	fi

	if ! command -v curl >/dev/null 2>&1; then
		printf 'error: curl is required to resolve the latest ACRYL version.\n' >&2
		exit 1
	fi

	case "$release_channel" in
		stable|beta) ;;
		*)
			printf 'error: invalid ACRYL release channel: %s\n' "$release_channel" >&2
			exit 1
			;;
	esac

	channel_dir=$(create_temp_dir)
	channel_path="$channel_dir/$release_channel"
	if ! acryl_run_quiet_with_animation \
		"Resolving latest release" \
		"Resolving latest release" \
		"Checking the $release_channel release channel." \
		curl -fsSL "$acryl_base_url/$release_channel" -o "$channel_path"; then
		rm -rf "$channel_dir"
		printf 'error: could not resolve latest ACRYL version from %s/%s\n' "$acryl_base_url" "$release_channel" >&2
		exit 1
	fi
	channel_version="$(tr -d '[:space:]' <"$channel_path")"
	rm -rf "$channel_dir"
	if [ -z "$channel_version" ]; then
		printf 'error: could not resolve latest ACRYL version from %s/%s\n' "$acryl_base_url" "$release_channel" >&2
		exit 1
	fi
	normalize_version "$channel_version"
}

normalize_version() {
	version="${1#v}"
	case "$version" in
		"")
			printf 'error: empty ACRYL version.\n' >&2
			exit 1
			;;
		*[!0-9A-Za-z.-]*)
			printf 'error: invalid ACRYL version: %s\n' "$1" >&2
			exit 1
			;;
	esac
	printf '%s' "$version"
}

install_node_npm_interactive() {
	method=$(detect_node_install_method)
	case "$method" in
		homebrew) label="Homebrew" ;;
		apt) label="apt" ;;
		apk) label="apk" ;;
		standalone) label="standalone Node.js" ;;
		*)
			method=standalone
			label="standalone Node.js"
			;;
	esac

	if acryl_prompt_yes_no \
		"Install Node.js and npm with $label?" \
		"Required before ACRYL can be installed." \
		"Install? [Y/n]"; then
		install_node_npm "$method" "$label"
		return
	else
		prompt_status=$?
	fi
	if [ "$prompt_status" -eq 2 ]; then
		printf 'No terminal detected; install Node.js 20.6.0 or newer and npm, then run this installer again.\n'
	else
		printf '\nInstall Node.js 20.6.0 or newer and npm, then run this installer again.\n'
	fi
	return 1
}

detect_node_install_method() {
	case "$(uname -s)" in
		Darwin)
			if command -v brew >/dev/null 2>&1; then
				printf 'homebrew'
			else
				printf 'standalone'
			fi
			;;
		Linux)
			if command -v apt-cache >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1 && apt_node_candidate_is_new_enough; then
				printf 'apt'
			elif command -v apk >/dev/null 2>&1 && apk_node_candidate_is_new_enough; then
				printf 'apk'
			else
				printf 'standalone'
			fi
			;;
		*)
			printf 'standalone'
			;;
	esac
}

apt_node_candidate_is_new_enough() {
	version=$(apt-cache policy nodejs 2>/dev/null | awk '/Candidate:/ { print $2; exit }')
	[ -n "$version" ] && [ "$version" != "(none)" ] && node_version_string_is_new_enough "$version"
}

apk_node_candidate_is_new_enough() {
	version=$(apk search -x nodejs 2>/dev/null | awk -F- '/^nodejs-/ { print $2; exit }')
	[ -n "$version" ] && node_version_string_is_new_enough "$version"
}

node_version_string_is_new_enough() {
	version="${1#v}"
	case "$version" in
		[0-9]*) ;;
		*) return 1 ;;
	esac
	version="${version%%[!0-9.]*}"
	version_ifs=${IFS- }
	IFS=.
	set -- $version
	IFS=$version_ifs
	major="${1:-}"
	minor="${2:-0}"
	patch="${3:-0}"
	case "$major" in ''|*[!0-9]*) return 1 ;; esac
	case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
	case "$patch" in ''|*[!0-9]*) patch=0 ;; esac

	[ "$major" -gt 20 ] && return 0
	[ "$major" -eq 20 ] && [ "$minor" -gt 6 ] && return 0
	[ "$major" -eq 20 ] && [ "$minor" -eq 6 ] && [ "$patch" -ge 0 ] && return 0
	return 1
}

install_node_npm() {
	method="$1"
	label="$2"

	if [ "$acryl_screen_enabled" != 1 ]; then
		printf '\nInstalling Node.js and npm with %s...\n\n' "$label"
		run_node_install_method "$method"
	else
		prepare_sudo_for_node_install "$method"
		node_install_details="Using $label.
Resolving Node.js packages.
Downloading Node.js runtime.
Installing npm.
Preparing ACRYL setup."
		acryl_run_quiet_with_animation_steps \
			"Installing Node.js and npm" \
			"Installing Node.js and npm" \
			"$node_install_details" \
			run_node_install_method "$method"
	fi

	if [ "$method" = standalone ]; then
		load_standalone_node
		ACRYL_NODE_INSTALLED_STANDALONE=1
	fi
	hash -r
	if [ "$acryl_screen_enabled" = 1 ]; then
		acryl_screen "Node.js and npm installed" "" "Continuing ACRYL setup." ""
	else
		printf '\nNode.js and npm are installed.\n\n'
	fi
}

node_install_needs_sudo() {
	if [ "${EUID:-$(id -u)}" -eq 0 ]; then
		return 1
	fi

	case "$1" in
		apt|apk)
			return 0
			;;
		standalone)
			[ "$(uname -s)" = Linux ] || return 1
			command -v xz >/dev/null 2>&1 && return 1
			command -v apt-get >/dev/null 2>&1 || command -v apk >/dev/null 2>&1
			;;
		*)
			return 1
			;;
	esac
}

prepare_sudo_for_node_install() {
	method="$1"
	if ! node_install_needs_sudo "$method"; then
		return 0
	fi

	acryl_screen "Preparing Node.js install" "" "This may ask for your sudo password." ""
	acryl_restore_terminal
	printf '\n'
	sudo -v
}

run_node_install_method() {
	case "$1" in
		homebrew) install_node_with_homebrew ;;
		apt) install_node_with_apt ;;
		apk) install_node_with_apk ;;
		standalone) install_node_standalone ;;
	esac
}

install_node_with_homebrew() {
	if brew list node >/dev/null 2>&1; then
		brew upgrade node
	else
		brew install node
	fi
}

install_node_with_apt() {
	print_sudo_note
	if [ "${EUID:-$(id -u)}" -eq 0 ]; then
		apt-get update
		apt-get install -y nodejs npm
	else
		sudo sh -c 'apt-get update && apt-get install -y nodejs npm'
	fi
}

install_node_with_apk() {
	print_sudo_note
	run_with_sudo apk add --update-cache nodejs npm
}

install_node_standalone() {
	node_platform=$(detect_node_binary_platform) || {
		printf 'Unsupported operating system for automatic Node.js install: %s\n' "$(uname -s)"
		return 1
	}
	node_arch=$(detect_node_binary_arch) || {
		printf 'Unsupported CPU architecture for automatic Node.js install: %s\n' "$(uname -m)"
		return 1
	}
	node_dist_base="https://nodejs.org/dist/latest-v22.x"
	node_base_dir=$(node_standalone_base_dir)
	node_tmp_dir=$(create_temp_dir)

	mkdir -p "$node_tmp_dir" "$node_base_dir"

	printf 'Resolving Node.js binary for %s-%s\n' "$node_platform" "$node_arch"
	curl -fsSL "$node_dist_base/SHASUMS256.txt" -o "$node_tmp_dir/SHASUMS256.txt"
	node_file=$(awk -v suffix="-$node_platform-$node_arch.tar.xz" '
		index($2, "node-v") == 1 && length($2) >= length(suffix) && substr($2, length($2) - length(suffix) + 1) == suffix { print $2; exit }
	' "$node_tmp_dir/SHASUMS256.txt")
	if [ -z "$node_file" ]; then
		printf 'No Node.js binary is available for %s-%s.\n' "$node_platform" "$node_arch"
		rm -rf "$node_tmp_dir"
		return 1
	fi
	case "$node_file" in
		*/*|*\\*|*..*)
			printf 'Unsafe Node.js archive name in checksum manifest: %s\n' "$node_file"
			rm -rf "$node_tmp_dir"
			return 1
			;;
		node-v*-"$node_platform"-"$node_arch".tar.xz) ;;
		*)
			printf 'Unexpected Node.js archive name in checksum manifest: %s\n' "$node_file"
			rm -rf "$node_tmp_dir"
			return 1
			;;
	esac

	printf 'Downloading Node.js %s\n' "${node_file%.tar.xz}"
	curl -fsSL "$node_dist_base/$node_file" -o "$node_tmp_dir/$node_file"
	verify_node_standalone_download "$node_tmp_dir" "$node_file"
	ensure_node_standalone_extract_tools "$node_platform"

	node_dir="$node_base_dir/${node_file%.tar.xz}"
	rm -rf "$node_dir"
	printf 'Extracting Node.js to %s\n' "$node_dir"
	tar -xf "$node_tmp_dir/$node_file" -C "$node_base_dir"
	rm -f "$node_base_dir/current"
	ln -s "$node_dir" "$node_base_dir/current"
	rm -rf "$node_tmp_dir"
	printf 'Node.js installed at %s\n' "$node_dir"
}

verify_node_standalone_download() {
	checksum_dir="$1"
	checksum_file_name="$2"
	awk -v file="$checksum_file_name" '$2 == file { print }' "$checksum_dir/SHASUMS256.txt" >"$checksum_dir/SHASUMS256.selected"

	if command -v sha256sum >/dev/null 2>&1; then
		printf 'Verifying Node.js download\n'
		(cd "$checksum_dir" && sha256sum -c SHASUMS256.selected)
	elif command -v shasum >/dev/null 2>&1; then
		printf 'Verifying Node.js download\n'
		(cd "$checksum_dir" && shasum -a 256 -c SHASUMS256.selected)
	else
		printf 'error: sha256sum or shasum is required to verify the Node.js download.\n'
		return 1
	fi
}

ensure_node_standalone_extract_tools() {
	extract_platform="$1"

	if [ "$extract_platform" = linux ] && ! command -v xz >/dev/null 2>&1; then
		printf 'Installing xz-utils for Node.js archive extraction\n'
		print_sudo_note
		if command -v apt-get >/dev/null 2>&1; then
			run_with_sudo apt-get update
			run_with_sudo apt-get install -y xz-utils
		elif command -v apk >/dev/null 2>&1; then
			run_with_sudo apk add --update-cache xz
		else
			printf 'xz is required to extract Node.js. Install xz and run this installer again.\n'
			return 1
		fi
	fi
}

load_standalone_node() {
	ACRYL_STANDALONE_NODE_BIN="$(node_standalone_base_dir)/current/bin"
	PATH="$ACRYL_STANDALONE_NODE_BIN:$PATH"
	export ACRYL_STANDALONE_NODE_BIN PATH
}

node_standalone_base_dir() {
	if [ -n "${XDG_DATA_HOME:-}" ]; then
		printf '%s/acryl-node' "$XDG_DATA_HOME"
	else
		printf '%s/.local/share/acryl-node' "$HOME"
	fi
}

detect_node_binary_platform() {
	case "$(uname -s)" in
		Darwin) printf 'darwin' ;;
		Linux) printf 'linux' ;;
		*) return 1 ;;
	esac
}

detect_node_binary_arch() {
	case "$(uname -m)" in
		x86_64|amd64) printf 'x64' ;;
		arm64|aarch64) printf 'arm64' ;;
		armv7l) printf 'armv7l' ;;
		ppc64le) printf 'ppc64le' ;;
		s390x) printf 's390x' ;;
		*) return 1 ;;
	esac
}

print_sudo_note() {
	if [ "${EUID:-$(id -u)}" -ne 0 ]; then
		printf 'This may ask for your sudo password.\n\n'
	fi
}

run_with_sudo() {
	if [ "${EUID:-$(id -u)}" -eq 0 ]; then
		"$@"
	else
		sudo "$@"
	fi
}

configure_standalone_node_path() {
	if original_acryl_path=$(resolve_acryl_with_original_path); then
		case "$original_acryl_path" in
			"$ACRYL_STANDALONE_NODE_BIN/"*)
				if [ "$acryl_screen_enabled" = 1 ]; then
					acryl_screen "ACRYL installed" "" "Run it with: $acryl_cmd" ""
				else
					printf '\nRun it with: %s\n' "$acryl_cmd"
				fi
				return 0
				;;
		esac
		if [ "$acryl_screen_enabled" = 1 ]; then
			acryl_screen "ACRYL installed" "" "PATH update needed for $acryl_cmd." ""
		else
			printf '%s was installed, but your shell is not using that install yet.\n' "$acryl_cmd"
			printf 'Your shell currently resolves %s to: %s\n' "$acryl_cmd" "$original_acryl_path"
		fi
	else
		if [ "$acryl_screen_enabled" = 1 ]; then
			acryl_screen "ACRYL installed" "" "PATH update needed for $acryl_cmd." ""
		else
			printf '%s was installed, but your shell is not using that install yet.\n' "$acryl_cmd"
		fi
	fi

	profile=$(detect_shell_profile) || {
		if [ "$acryl_screen_enabled" = 1 ]; then
			acryl_restore_terminal
			printf '\n'
		fi
		print_standalone_path_manual_instructions
		return 0
	}

	if shell_profile_has_standalone_node_path "$profile"; then
		if [ "$acryl_screen_enabled" = 1 ]; then
			acryl_screen "ACRYL installed" "" "Run: $(acryl_source_profile_command "$profile")" ""
		else
			printf '%s already contains %s.\n' "$profile" "$ACRYL_STANDALONE_NODE_BIN"
			printf 'Restart your shell or run: %s\n' "$(acryl_source_profile_command "$profile")"
		fi
		return 0
	fi

	prompt_add_standalone_node_path "$profile"
}

resolve_acryl_with_original_path() {
	saved_path=$PATH
	PATH=$acryl_original_path
	if command -v "$acryl_cmd" 2>/dev/null; then
		status=0
	else
		status=$?
	fi
	PATH=$saved_path
	return "$status"
}

detect_shell_profile() {
	if [ -n "${ACRYL_SHELL_PROFILE:-}" ]; then
		printf '%s' "$ACRYL_SHELL_PROFILE"
		return 0
	fi
	if [ -z "${HOME:-}" ]; then
		return 1
	fi

	shell_name="${SHELL:-}"
	shell_name="${shell_name##*/}"
	case "$shell_name" in
		zsh)
			printf '%s/.zshrc' "${ZDOTDIR:-$HOME}"
			;;
		bash)
			printf '%s/.bashrc' "$HOME"
			;;
		*)
			if [ -f "$HOME/.zshrc" ]; then
				printf '%s/.zshrc' "$HOME"
			elif [ -f "$HOME/.bashrc" ]; then
				printf '%s/.bashrc' "$HOME"
			else
				printf '%s/.profile' "$HOME"
			fi
			;;
	esac
}

shell_profile_has_standalone_node_path() {
	profile="$1"
	[ -f "$profile" ] && grep -F "$ACRYL_STANDALONE_NODE_BIN" "$profile" >/dev/null 2>&1
}

prompt_add_standalone_node_path() {
	profile="$1"
	path_line=$(standalone_node_path_line)

	if ! acryl_prompt_yes_no \
		"Add standalone Node.js to your PATH?" \
		"Updates $profile so future shells can run $acryl_cmd." \
		"Update PATH? [Y/n]"; then
		if [ "$acryl_screen_enabled" = 1 ]; then
			acryl_restore_terminal
			printf '\n'
		fi
		print_standalone_path_manual_instructions
		return 0
	fi

	mkdir -p "$(dirname "$profile")"
	{
		printf '\n# ACRYL standalone Node.js\n'
		printf '%s\n' "$path_line"
	} >>"$profile"
	if [ "$acryl_screen_enabled" = 1 ]; then
		acryl_screen "ACRYL installed" "" "Run: $(acryl_source_profile_command "$profile")" ""
	else
		printf 'Added %s to %s.\n' "$ACRYL_STANDALONE_NODE_BIN" "$profile"
		printf 'Restart your shell or run: %s\n' "$(acryl_source_profile_command "$profile")"
	fi
}

print_standalone_path_manual_instructions() {
	printf 'Add this to your shell profile to use %s from new shells:\n\n' "$acryl_cmd"
	printf '  %s\n' "$(standalone_node_path_line)"
	printf '\nThen restart your shell and run: %s\n' "$acryl_cmd"
}

standalone_node_path_line() {
	printf 'export PATH="%s:$PATH"' "$ACRYL_STANDALONE_NODE_BIN"
}

acryl_shell_quote() {
	quoted=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
	printf "'%s'" "$quoted"
}

acryl_source_profile_command() {
	printf '. %s && %s' "$(acryl_shell_quote "$1")" "$acryl_cmd"
}

download_acryl_package() {
	version="$1"
	tarball_url="$2"
	tarball_path="$3"
	download_dir=$(dirname "$tarball_path")
	tarball_name=$(basename "$tarball_path")
	checksums_url="$acryl_base_url/releases/v$version/SHA256SUMS"
	checksums_path="$download_dir/SHA256SUMS"

	if ! command -v curl >/dev/null 2>&1; then
		printf 'error: curl is required to download ACRYL.\n' >&2
		exit 1
	fi

	acryl_run_quiet_with_animation \
		"Downloading checksums" \
		"Downloading release checksums" \
		"ACRYL v$version" \
		curl -fsSL "$checksums_url" -o "$checksums_path"

	acryl_run_quiet_with_animation \
		"Downloading ACRYL" \
		"Downloading ACRYL v$version" \
		"Fetching the verified package." \
		curl -fsSL "$tarball_url" -o "$tarball_path"

	verify_acryl_package_checksum "$checksums_path" "$tarball_path"
}

verify_acryl_package_checksum() {
	checksums_path="$1"
	tarball_path="$2"
	checksum_dir=$(dirname "$tarball_path")
	tarball_name=$(basename "$tarball_path")
	selected_checksums_path="$checksum_dir/SHA256SUMS.selected"

	if ! awk -v file="$tarball_name" '$2 == file { print; found = 1; exit } END { if (!found) exit 1 }' \
		"$checksums_path" >"$selected_checksums_path"; then
		printf 'error: checksum for %s was not found in %s\n' "$tarball_name" "$checksums_path" >&2
		exit 1
	fi

	if command -v sha256sum >/dev/null 2>&1; then
		acryl_run_quiet_with_animation \
			"Verifying download" \
			"Verifying ACRYL download" \
			"Checking SHA-256." \
			acryl_run_checksum_check "$checksum_dir" "$(basename "$selected_checksums_path")" sha256sum
	elif command -v shasum >/dev/null 2>&1; then
		acryl_run_quiet_with_animation \
			"Verifying download" \
			"Verifying ACRYL download" \
			"Checking SHA-256." \
			acryl_run_checksum_check "$checksum_dir" "$(basename "$selected_checksums_path")" shasum
	else
		printf 'error: sha256sum or shasum is required to verify the ACRYL download.\n' >&2
		exit 1
	fi
}

acryl_run_checksum_check() {
	checksum_dir="$1"
	selected_checksums_name="$2"
	checker="$3"
	case "$checker" in
		sha256sum)
			(cd "$checksum_dir" && sha256sum -c "$selected_checksums_name")
			;;
		shasum)
			(cd "$checksum_dir" && shasum -a 256 -c "$selected_checksums_name")
			;;
	esac
}

confirm_install() {
	version="$1"
	tarball_url="$2"

	if acryl_prompt_yes_no \
		"Install ACRYL v$version globally with npm?" \
		"Downloads the verified release and runs npm install -g." \
		"Install? [Y/n]"; then
		return 0
	else
		prompt_status=$?
	fi

	if [ "$prompt_status" -eq 2 ]; then
		printf 'This will download, verify, and install:\n\n  %s\n\n' "$tarball_url"
		printf 'No terminal detected; continuing without confirmation.\n'
		return 0
	fi

	if [ "$acryl_screen_enabled" = 1 ]; then
		acryl_screen "Installation cancelled" "" "No changes were made." ""
		exit 0
	fi
	printf '\nInstallation cancelled.\n'
	exit 0
}

confirm_kernel_runtime_setup() {
	case "${ACRYL_BOOTSTRAP_KERNEL_ON_INSTALL:-}" in
		1)
			acryl_bootstrap_kernel_on_install=1
			return
			;;
		0)
			acryl_bootstrap_kernel_on_install=0
			return
			;;
	esac

	if acryl_prompt_yes_no \
		"Prepare Python runtime now?" \
		"Installs uv, Python 3.11, and the ACRYL runtime." \
		"Prepare? [Y/n]"; then
		acryl_bootstrap_kernel_on_install=1
		return
	else
		prompt_status=$?
	fi

	if [ "$prompt_status" -eq 2 ]; then
		printf 'No terminal detected; preparing the Python runtime during install.\n'
		acryl_bootstrap_kernel_on_install=1
		return
	fi

	acryl_bootstrap_kernel_on_install=0
	if [ "$acryl_screen_enabled" = 1 ]; then
		acryl_screen "Python setup skipped" "" "The runtime can be prepared on first ipython use." ""
		sleep 0.4
	else
		printf '\nSkipping Python runtime setup.\n'
	fi
}

acryl_npm_requires_remote_policy() {
	npm_version=$(npm --version 2>/dev/null) || return 1
	npm_major=${npm_version%%.*}
	case "$npm_major" in
		""|*[!0-9]*) return 1 ;;
	esac
	[ "$npm_major" -ge 12 ]
}

acryl_npm_install() {
	tarball_path="$1"
	shift
	if acryl_npm_requires_remote_policy; then
		# Limit npm 12's required policy overrides to the verified root package.
		env "$@" npm install -g --no-fund --no-audit --loglevel=error --progress=false \
			--allow-remote=all --allow-scripts="$tarball_path" "$tarball_path"
	else
		env "$@" npm install -g --no-fund --no-audit --loglevel=error --progress=false "$tarball_path"
	fi
}

install_acryl_package() {
	tarball_path="$1"
	if [ "$acryl_bootstrap_kernel_on_install" = 1 ]; then
		npm_install_details="Preparing global install.
Linking command binaries.
Installing runtime packages.
Preloading search tools.
Preparing Python kernel.
Finalizing npm install."
		acryl_run_quiet_with_animation_steps \
			"Installing ACRYL" \
			"Installing ACRYL" \
			"$npm_install_details" \
			acryl_npm_install "$tarball_path" ACRYL_BOOTSTRAP_TOOLS_ON_INSTALL=1 ACRYL_BOOTSTRAP_KERNEL_ON_INSTALL=1 ACRYL_INSTALL_UV=1
	else
		npm_install_details="Preparing global install.
Linking command binaries.
Installing runtime packages.
Preloading search tools.
Finalizing npm install."
		acryl_run_quiet_with_animation_steps \
			"Installing ACRYL" \
			"Installing ACRYL" \
			"$npm_install_details" \
			acryl_npm_install "$tarball_path" ACRYL_BOOTSTRAP_TOOLS_ON_INSTALL=1
	fi
}

main "$@"
