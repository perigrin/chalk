my $s = "abc"; $s =~ s/(b)/$1$1/; my $k = $1; print "$s$k\n";
