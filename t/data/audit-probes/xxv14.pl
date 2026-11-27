my $s = "ab"; my $n = ($s =~ tr/a/x/); my $m = ($s =~ tr/x/x/); print "$n$m$s\n";
