# **************************************************************************** #
#                                  SUBSHELL                                    #
# **************************************************************************** #
yes | (head -1 && (head -2 | (head -3 && head -4))) | cat | wc -l

yes | (echo 1 && (echo 2 | (echo 3 && echo 4))) | cat

yes | (echo 1 && (echo 2 | (echo 3 && echo 4))) | cat | wc -l

yes | (head -1 && (head -2 | (head -3 && head -4))) | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | wc -l

(echo 1 | cat > alt) > out
