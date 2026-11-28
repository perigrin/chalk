my $s = "abc"; $s =~ /(b)/; sub m2 { "zzz" =~ /(z)/; $1 } my $t = m2(); print $1, $t, "\n";
