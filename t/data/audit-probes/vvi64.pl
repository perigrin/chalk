my $s = "abc"; my $t = $s . ($s =~ s/b//) . $s; print "$t\n";
