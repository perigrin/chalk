my $s = "abc"; my $t = ($s =~ tr/a/x/r) . $s; print "$t\n";
