sub f { my @r = (1, 2, 3); return @r } my $c = f(); my ($x) = f(); my $l = (f())[-1]; print "$c$x$l\n";
