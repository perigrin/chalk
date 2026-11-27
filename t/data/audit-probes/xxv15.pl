our $s = "ab"; my $n = ($s =~ tr/a/x/); my $t = $s =~ tr/x/y/r; print "$n$t$s\n";
