sub hanoi { my ($n, $f, $t, $v, $c) = @_; return 0 if $n == 0; hanoi($n - 1, $f, $v, $t) + 1 + hanoi($n - 1, $v, $t, $f) } print hanoi(5, "a", "b", "c"), "\n";
