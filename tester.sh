#!/usr/bin/env -S --default-signal bash

# Change if you store the tester in another PATH
export MINISHELL_PATH=./
export EXECUTABLE=minishell
RUNDIR=$HOME/42_minishell_tester
TMP_OUTDIR=/tmp/minishell_tester
OUTDIR=$MINISHELL_PATH/tester_output

# Get the name of the minishell by running a command that produces an error
# The name will then be filtered out from error messages
MINISHELL_NAME=$(echo -n "|" | $MINISHELL_PATH/$EXECUTABLE 2>&1)
if [[ $(echo -n "$MINISHELL_NAME" | wc -l) -gt 1 ]] ; then
	MINISHELL_NAME=$(echo -n "$MINISHELL_NAME" | awk 'NR==2')
	READLINE="true"
fi
MINISHELL_NAME=$(echo -n "$MINISHELL_NAME" | awk -F: '{if ($0 ~ /:/) print $1; else print ""}')

# Get the minishell prompt in case it needs to be filtered out because of the use of readline
if [[ $READLINE == "true" ]] ; then
	MINISHELL_PROMPT=$(echo -n "everything_before_this_is_the_prompt" | $MINISHELL_PATH/$EXECUTABLE 2>&1 | head -n 1 | sed 's/everything_before_this_is_the_prompt.*//')
	ESCAPED_PROMPT=$(echo -n "$MINISHELL_PROMPT" | sed 's:[][\/.^$*]:\\&:g')
fi

# Get the exit message of the minishell in case it needs to be filtered out
# The exit message should always get printed to stderr, bash does it too (see `exit 2>/dev/null`)
MINISHELL_EXIT_MSG=$(echo -n "" | $MINISHELL_PATH/$EXECUTABLE 2>&1 | sed "s/^$ESCAPED_PROMPT//")

VALGRIND_FLAGS=(
	--errors-for-leak-kinds=all
	--leak-check=full
	--show-error-list=yes
	--show-leak-kinds=all
	--suppressions="$MINISHELL_PATH"/minishell.supp
	--trace-children=yes
	--trace-children-skip="$(echo /bin/* /usr/bin/* /usr/sbin/* $(which norminette) | tr ' ' ',')"
	--track-fds=all
	--track-origins=yes
	--log-file="$TMP_OUTDIR/tmp_valgrind_out"
	)
VALGRIND="valgrind ${VALGRIND_FLAGS[*]}"

NL=$'\n'
TAB=$'\t'

TEST_COUNT=0
TEST_KO_OUT=0
TEST_KO_ERR=0
TEST_KO_EXIT=0
TEST_OK=0
FAILED=0
ONE=0
TWO=0
THREE=0
GOOD_TEST=0
LEAKS=0

main() {
	process_options "$@"

	if [[ ! -f $MINISHELL_PATH/$EXECUTABLE ]] ; then
		echo -e "\033[1;31m# **************************************************************************** #"
		echo "#                            MINISHELL NOT COMPILED                            #"
		echo "#                              TRY TO COMPILE ...                              #"
		echo -e "# **************************************************************************** #\033[m"
		make -C $MINISHELL_PATH
		if [[ ! -f $MINISHELL_PATH/$EXECUTABLE ]] ; then
			echo -e "\033[1;31mCOMPILING FAILED\033[m" && exit 1
		fi
	fi

	if [[ $# -eq 0 ]] ; then
		print_usage
		exit 0
	fi

	mkdir -p "$TMP_OUTDIR"
	process_tests "$@"

	if [[ $TEST_COUNT -gt 0 ]] ; then
		print_stats
	fi
	rm -rf test
	rm -rf "$TMP_OUTDIR" 2>/dev/null

	if [ "$GITHUB_ACTIONS" == "true" ] ; then
		echo "$GH_BRANCH=$FAILED" >> "$GITHUB_ENV"
	fi

	if [[ $LEAKS -ne 0 ]] ; then
		exit 1
	else
		exit 0
	fi
}

print_usage() {
	echo -e "  \033[1;33m# **************************************************************************** #"
	echo -e "  #                          USAGE: mstest [options]                             #"
	echo -e "  # Options:                                                                     #"
	echo -e "  #   m                      Run mandatory tests                                 #"
	echo -e "  #   vm                     Run mandatory tests with memory leak checks         #"
	echo -e "  #   b                      Run bonus tests                                     #"
	echo -e "  #   vb                     Run bonus tests with memory leak checks             #"
	echo -e "  #   ne                     Run tests w/o environment                           #"
	echo -e "  #   vne                    Run tests w/o environment with memory leak checks   #"
	echo -e "  #   d                      Run death tests                                     #"
	echo -e "  #   vd                     Run death tests with memory leak checks             #"
	echo -e "  #   a                      Run all tests                                       #"
	echo -e "  #   va                     Run all tests with memory leak checks               #"
	echo -e "  #   -l|--leaks             Enable memory leak checks                           #"
	echo -e "  #   -n|--no-env            Disable environment                                 #"
	echo -e "  #   -f|--file <file>       Run tests specified in a file                       #"
	echo -e "  #      --dir <directory>   Run tests specified in a directory                  #"
	echo -e "  #   -h|--help              Show this help message and exit                     #"
	echo -e "  # **************************************************************************** #\033[m"
}

process_options() {
	while [[ $# -gt 0 ]] ; do
		case $1 in
			-l|--leaks)
				TEST_LEAKS="true"
				shift
				;;
			-n|--no-env)
				NO_ENV="true"
				shift
				;;
			-f|--file)
				if [[ ! -f $2 ]] ; then
					echo "FILE NOT FOUND: \"$2\""
					exit 1
				fi
				shift 2
				;;
			-d|--dir)
				if [[ ! -d $2 ]] ; then
					echo "DIRECTORY NOT FOUND: \"$2\""
					exit 1
				fi
				shift 2
				;;
			-h|--help)
				print_usage
				exit 0
				;;
			m|vm|b|vb|ne|vne|d|vd|a|va)
				shift
				;;
			*)
				echo "INVALID OPTION: $1"
				print_usage
				exit 1
				;;
		esac
	done
}

process_tests() {
	if [[ $TEST_LEAKS == "true" ]] ; then
		print_title "MEMORY_LEAKS" "💧"
	fi
	if [[ $NO_ENV == "true" ]] ; then
		print_title "NO_ENVIRONMENT" "🌐"
	fi
	while [[ $# -gt 0 ]] ; do
		case $1 in
			m)
				dir="mand"
				print_title "MANDATORY" "🚀"
				run_tests "$dir" "$TEST_LEAKS" "$NO_ENV"
				shift
				;;
			vm)
				dir="mand"
				test_leaks="true"
				print_title "MANDATORY_LEAKS" "🚀"
				run_tests "$dir" "$test_leaks" "$NO_ENV"
				shift
				;;
			b)
				dir="bonus"
				print_title "BONUS" "🎉"
				run_tests "$dir" "$TEST_LEAKS" "$NO_ENV"
				shift
				;;
			vb)
				dir="bonus"
				test_leaks="true"
				print_title "BONUS_LEAKS" "🎉"
				run_tests "$dir" "$test_leaks" "$NO_ENV"
				shift
				;;
			ne)
				dir="no_env"
				no_env="true"
				print_title "NO_ENV" "🌐"
				run_tests "$dir" "$TEST_LEAKS" "$no_env"
				shift
				;;
			vne)
				dir="no_env"
				test_leaks="true"
				no_env="true"
				print_title "NO_ENV_LEAKS" "🌐"
				run_tests "$dir" "$test_leaks" "$no_env"
				shift
				;;
			d)
				dir="mini_death"
				print_title "MINI_DEATH" "💀"
				run_tests "$dir" "$TEST_LEAKS" "$NO_ENV"
				shift
				;;
			vd)
				dir="mini_death"
				test_leaks="true"
				print_title "MINI_DEATH_LEAKS" "💀"
				run_tests "$dir" "$test_leaks" "$NO_ENV"
				shift
				;;
			a)
				dir="all"
				print_title "ALL" "🌟"
				run_tests "$dir" "$TEST_LEAKS" "$NO_ENV"
				shift
				;;
			va)
				dir="all"
				test_leaks="true"
				print_title "ALL_LEAKS" "🌟"
				run_tests "$dir" "$test_leaks" "$NO_ENV"
				shift
				;;
			-f|--file)
				file="$2"
				print_title "FILE: $file" "📄"
				run_tests_from_file "$file" "$TEST_LEAKS" "$NO_ENV"
				shift 2
				;;
			-d|--dir)
				dir="$2"
				print_title "DIRECTORY: $dir" "📁"
				run_tests_from_dir "$dir" "$TEST_LEAKS" "$NO_ENV"
				shift 2
				;;
			*)
				shift
				;;
		esac
	done
}

print_title() {
	local title="$1"
	local s="$2"
	local title_length=${#title}
	local total_length=80
	local padding_length=$(( (total_length - title_length - 4) / 2 ))
	local padding_right_length=$((padding_length + (total_length - title_length - 4) % 2))
	local padding_left=$(printf '%*s' "$padding_length" "")
	local padding_right=$(printf '%*s' "$padding_right_length" "")

	echo "  $s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s"
	echo -e "  $s${padding_left}\033[1;34m$title\033[m${padding_right}$s"
	echo "  $s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s$s"
}

run_tests() {
	local dir=$1
	local test_leaks=$2
	local no_env=$3
	local files

	if [[ $dir == "all" ]] ; then
		files="${RUNDIR}/cmds/**/*.sh"
	else
		files="${RUNDIR}/cmds/${dir}/*"
	fi
	for file in $files ; do
		run_test "$file" "$test_leaks" "$no_env"
	done
}

run_tests_from_file() {
	local file=$1
	local test_leaks=$2
	local no_env=$3

	run_test "$file" "$test_leaks" "$no_env"
}

run_tests_from_dir() {
	local dir=$1
	local test_leaks=$2
	local no_env=$3
	local files="${dir}/*"

	for file in $files ; do
		run_test "$file" "$test_leaks" "$no_env"
	done
}

run_test() {
	local file=$1
	local test_leaks=$2
	local no_env=$3

	if [[ $no_env == "true" ]] ; then
		env="env -i"
	fi
	if  [[ $test_leaks == "true" ]] ; then
		valgrind="$VALGRIND"
	fi
	IFS=''
	i=1
	end_of_file=0
	line_count=0
	dir_name=$(basename "$(dirname "$file")")
	file_name=$(basename --suffix=.sh "$file")
	while [[ $end_of_file == 0 ]] ; do
		read -r line
		end_of_file=$?
		((line_count++))
		if [[ $line == \#* ]] || [[ $line == "" ]] ; then
			if [[ $line == "#"[[:blank:]]*[[:blank:]]"#" ]] ; then
				echo -e "\033[1;33m		$line\033[m" | tr '\t' '    '
			fi
			continue
		else
			printf "\033[1;35m%-4s\033[m" "  $i:	"
			tmp_line_count=$line_count
			while [[ $end_of_file == 0 ]] && [[ $line != \#* ]] && [[ $line != "" ]] ; do
				input+="$line$NL"
				read -r line
				end_of_file=$?
				((line_count++))
			done
			echo -n "$input" | eval "$env $valgrind $MINISHELL_PATH/$EXECUTABLE" 2>"$TMP_OUTDIR/tmp_err_minishell" >"$TMP_OUTDIR/tmp_out_minishell"
			exit_minishell=$?
			echo -n "enable -n .$NL$input" | eval "$env bash --posix" 2>"$TMP_OUTDIR/tmp_err_bash" >"$TMP_OUTDIR/tmp_out_bash"
			exit_bash=$?
			echo -ne "\033[1;34mSTD_OUT:\033[m "
			if [[ $READLINE == "true" ]] ; then
				# Filter out all lines with the minishell prompt from stdout
				sed -i "/^$ESCAPED_PROMPT/d" "$TMP_OUTDIR/tmp_out_minishell"
			fi
			if ! diff -q "$TMP_OUTDIR/tmp_out_minishell" "$TMP_OUTDIR/tmp_out_bash" >/dev/null ; then
				echo -ne "❌  " | tr '\n' ' '
				((TEST_KO_OUT++))
				((FAILED++))
				mkdir -p "$OUTDIR/$dir_name/$file_name" 2>/dev/null
				mv "$TMP_OUTDIR/tmp_out_minishell" "$OUTDIR/$dir_name/$file_name/stdout_minishell_$i" 2>/dev/null
				mv "$TMP_OUTDIR/tmp_out_bash" "$OUTDIR/$dir_name/$file_name/stdout_bash_$i" 2>/dev/null
			else
				echo -ne "✅  "
				((TEST_OK++))
				((ONE++))
			fi
			echo -ne "\033[1;33mSTD_ERR:\033[m "
			if [[ -n "$MINISHELL_EXIT_MSG" ]] ; then
				# Filter out the exit message from stderr
				sed -i "/^$MINISHELL_EXIT_MSG$/d" "$TMP_OUTDIR/tmp_err_minishell"
			fi
			if grep -q '^bash: line [0-9]*:' "$TMP_OUTDIR/tmp_err_bash" ; then
				# Normalize bash stderr by removing the program name and line number prefix
				sed -i 's/^bash: line [0-9]*:/:/' "$TMP_OUTDIR/tmp_err_bash"
				# Normalize minishell stderr by removing its program name prefix
				sed -i "s/^\\($MINISHELL_NAME: line [0-9]*:\\|$MINISHELL_NAME:\\)/:/" "$TMP_OUTDIR/tmp_err_minishell"
				# Remove the next line after a specific syntax error message in bash stderr
				sed -i '/^: syntax error near unexpected token/{n; d}' "$TMP_OUTDIR/tmp_err_bash"
			fi
			if ! diff -q "$TMP_OUTDIR/tmp_err_minishell" "$TMP_OUTDIR/tmp_err_bash" >/dev/null ; then
				echo -ne "❌  " | tr '\n' ' '
				((TEST_KO_ERR++))
				((FAILED++))
				mkdir -p "$OUTDIR/$dir_name/$file_name" 2>/dev/null
				mv "$TMP_OUTDIR/tmp_err_minishell" "$OUTDIR/$dir_name/$file_name/stderr_minishell_$i" 2>/dev/null
				mv "$TMP_OUTDIR/tmp_err_bash" "$OUTDIR/$dir_name/$file_name/stderr_bash_$i" 2>/dev/null
			else
				echo -ne "✅  "
				((TEST_OK++))
				((TWO++))
			fi
			echo -ne "\033[1;36mEXIT_CODE:\033[m "
			if [[ $exit_minishell != $exit_bash ]] ; then
				echo -ne "❌\033[1;31m [ minishell($exit_minishell)  bash($exit_bash) ]\033[m  " | tr '\n' ' '
				((TEST_KO_EXIT++))
				((FAILED++))
			else
				echo -ne "✅  "
				((TEST_OK++))
				((THREE++))
			fi
			if [[ $test_leaks == "true" ]] ; then
				echo -ne "\033[1;36mLEAKS:\033[m "
				# Get all error summaries
				error_summaries=$(cat "$TMP_OUTDIR/tmp_valgrind_out" | grep -a "ERROR SUMMARY:" | awk '{print $4}')
				IFS=$'\n' read -rd '' -a error_summaries_array <<<"$error_summaries"
				# Check if any error summary is not 0
				leak_found=0
				for error_summary in "${error_summaries_array[@]}" ; do
					if [ -n "$error_summary" ] && [ "$error_summary" -ne 0 ] ; then
						leak_found=1
						break
					fi
				done
				# Check if there are any open file descriptors not inherited from parent
				open_file_descriptors=$(
					awk '
						# If the line starts with a PID and "Open file descriptor"
						/^==[0-9]+== Open file descriptor/ {
							# Store the PID and the line
							pid=$1
							line=$0

							# Keep reading lines until a line that starts with the same PID gets found
							while (getline && $1 != pid);

							# Check if the line does not contain "<inherited from parent>"
							if ($0 !~ /<inherited from parent>/) {
								print line
							}
						}
					' "$TMP_OUTDIR/tmp_valgrind_out"
				)
				if [ -n "$open_file_descriptors" ] ; then
					leak_found=1
				fi
				if [ "$leak_found" -ne 0 ] ; then
					echo -ne "❌ "
					((LEAKS++))
					mkdir -p "$OUTDIR/$dir_name/$file_name" 2>/dev/null
					mv "$TMP_OUTDIR/tmp_valgrind_out" "$OUTDIR/$dir_name/$file_name/valgrind_out_$i" 2>/dev/null
				else
					echo -ne "✅ "
				fi
			fi
			input=""
			((i++))
			((TEST_COUNT++))
			echo -e "\033[0;90m$file:$tmp_line_count\033[m  "
			if [[ $ONE == 1 && $TWO == 1 && $THREE == 1 ]] ; then
				((GOOD_TEST++))
				((ONE--))
				((TWO--))
				((THREE--))
			else
				ONE=0
				TWO=0
				THREE=0
			fi
		fi
	done < "$file"
	rm -f "$TMP_OUTDIR/tmp_valgrind_out"
	find "$OUTDIR" -type d -empty -delete 2>/dev/null
}

print_stats() {
	echo "🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁"
	echo -e "🏁                                    \033[1;31mRESULT\033[m                                    🏁"
	echo "🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁"
	printf "\033[1;35m%-4s\033[m" "             TOTAL TEST COUNT: $TEST_COUNT "
	printf "\033[1;32m TESTS PASSED: $GOOD_TEST\033[m "
	if [[ $LEAKS == 0 ]] ; then
		printf "\033[1;32m LEAKING: $LEAKS\033[m "
	else
		printf "\033[1;31m LEAKING: $LEAKS\033[m "
	fi
	echo ""
	echo -ne "\033[1;34m                     STD_OUT:\033[m "
	if [[ $TEST_KO_OUT == 0 ]] ; then
		echo -ne "\033[1;32m✓ \033[m  "
	else
		echo -ne "\033[1;31m$TEST_KO_OUT\033[m  "
	fi
	echo -ne "\033[1;33mSTD_ERR:\033[m "
	if [[ $TEST_KO_ERR == 0 ]] ; then
		echo -ne "\033[1;32m✓ \033[m  "
	else
		echo -ne "\033[1;31m$TEST_KO_ERR\033[m  "
	fi
	echo -ne "\033[1;36mEXIT_CODE:\033[m "
	if [[ $TEST_KO_EXIT == 0 ]] ; then
		echo -ne "\033[1;32m✓ \033[m  "
	else
		echo -ne "\033[1;31m$TEST_KO_EXIT\033[m  "
	fi
	echo ""
	echo -e "\033[1;33m                         TOTAL FAILED AND PASSED CASES:"
	echo -e "\033[1;31m                                     ❌ $FAILED \033[m  "
	echo -ne "\033[1;32m                                     ✅ $TEST_OK \033[m  "
	echo ""
}

# Start the tester
main "$@"

# Clean all tmp files
[[ $1 != "-f" ]] && rm -f tmp_*
