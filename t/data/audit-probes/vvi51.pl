my $s = "abc"; my $n = length($s) + ($s =~ s/b//) + length($s); print "$n\n";
