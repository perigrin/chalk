my $s = "ab"; my $n = ($s =~ tr/a/x/); my @p = split //, $s; print "$n@p\n";
