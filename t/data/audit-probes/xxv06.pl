my $s = "ab"; my $n = ($s =~ s/a/x/); my $m = ($s =~ s/x/z/); my $c = ($s =~ tr/z//); print "$n$m$c$s\n";
