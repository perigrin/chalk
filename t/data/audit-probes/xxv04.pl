my $s = "bb"; my $n = ($s =~ tr/b/c/); my $l = length $s; my $u = "$s$n$l"; print "$u\n";
