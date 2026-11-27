sub f { my $t = shift; $_[0] = $t } my ($x,$y)=(1,2); f($x,$y); print "$x $y\n";
