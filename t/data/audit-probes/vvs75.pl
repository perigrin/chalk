my $s = "abc"; $s =~ /(a)/; my $t = join(",", $1, $s =~ /(b)/); print "$t\n";
