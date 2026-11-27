my $s = "hello"; my $n = ($s =~ tr/l//); my $d = ($s =~ tr/l//dr); my $c = ($s =~ tr/a-y/b-z/r); print "$n$d$c$s\n";
