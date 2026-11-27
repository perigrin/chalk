my (@a,@b); for my $c (0,1,1) { my $t = $c ? \@a : \@b; push @$t, $c; $t->[0] .= "x" } print "@a|@b\n";
