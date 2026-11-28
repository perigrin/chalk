my $s = "abc"; $s =~ /(a)/; (my $t = "x") =~ s/(x)/y/; print $1, "\n";
