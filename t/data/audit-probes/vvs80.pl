my $s = "abc"; $s =~ /(a)/; sub m2 { $s =~ /(c)/; 0 } my @l = ($1, m2()); print "@l\n";
