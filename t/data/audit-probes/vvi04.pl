my $s = "abc"; my $t = ($s =~ s/b/z/r) =~ s/a/y/r; print "$s$t\n";
