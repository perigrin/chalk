sub f { return } my %h = (a => scalar(f()), b => 1); print join(",", map { $_ // "u" } map { $_, $h{$_} } sort keys %h), "\n";
