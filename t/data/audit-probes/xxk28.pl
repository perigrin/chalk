my $s = "abc"; my $t = $s =~ s/b/X/r =~ s/c/Y/r; print "$s$t\n";
