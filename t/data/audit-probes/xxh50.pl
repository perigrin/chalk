our @st; sub f { my ($n) = @_; push @st, $n; f($n - 1) if $n; pop @st } print f(3), scalar(@st), "\n";
