my $s = "abc"; $s =~ /(a)/; my $t = $1 . ($s =~ /(b)/); print "$t\n";
