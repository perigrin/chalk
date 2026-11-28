my $s = "abc"; $s =~ /(a)/; sub m2 { "zz" =~ /(z)/; 0 } my @l = ($1, m2(), $1); print "@l\n";
