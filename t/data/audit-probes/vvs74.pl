my $s = "abc"; $s =~ /(a)/; my $t = $1 . ($s =~ /(b)/) . $1; print "$t\n";
