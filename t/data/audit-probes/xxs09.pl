my $s = "abc"; my $u = uc($s =~ tr/a/b/r); my $l = length($s =~ tr/a//dr); print "$u$l\n";
