my $s = "ab"; my $n = ($s =~ tr/a/b/); my $t = $s; $s =~ tr/b/c/; print "$n $t $s\n";
