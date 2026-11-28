my $s = "abc"; my $r = [$s]; $r->[0] =~ tr/a/z/; print "$s$r->[0]\n";
