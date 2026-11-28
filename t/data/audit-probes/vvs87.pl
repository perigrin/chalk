my $s = "abc"; $s =~ /(a)(b)/; my @l = ($1, $2, $s =~ /(c)/, $1); print join(",", map { $_ // "u" } @l), "\n";
