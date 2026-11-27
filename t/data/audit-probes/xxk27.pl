my $s = "aaa"; my $c = ($s =~ s/a/b/g); my $t = $s =~ tr/b//; my $r = $s =~ tr/b/c/r; print "$c$t$r$s\n";
