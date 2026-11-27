my $s = "ab"; my $n = ($s =~ tr/a/x/); my $t = $s; $s =~ tr/x/y/; print "$n$t$s\n";
