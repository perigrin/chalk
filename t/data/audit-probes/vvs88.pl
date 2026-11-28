my $s = "abc"; $s =~ /(a)(b)/; my @l = ($2, $s =~ /(c)/); print join(",", map { $_ // "u" } @l), "\n";
