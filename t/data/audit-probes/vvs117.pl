my $s = "abc"; $s =~ /(a)/; (my $t = "xy") =~ s/(x)/$1$1/; print "$t$1\n";
