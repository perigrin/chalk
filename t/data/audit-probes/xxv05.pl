my $s = "ab"; my $n = ($s =~ s/a/x/); my $t = $s =~ s/b/y/r; print "$n$t$s\n";
