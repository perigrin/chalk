sub dep { my ($n, $acc) = @_; return $acc if !$n; dep($n - 1, $acc . $n) } print dep(4, ""), "\n";
