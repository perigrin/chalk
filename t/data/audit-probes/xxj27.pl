my $s = "x"; my $r = ($s =~ /x/) ? "y" : "n"; my ($a1) = ($s =~ /(z)/); print $r, defined $a1 ? "d" : "u", "\n";
