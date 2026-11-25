sub f { my @a = (1,2,3); @a } sub g { my @a = (1,2,3); @a[1,2] } sub h { my @a=(1,2,3); (@a, 9) } my ($x)=f(); my $y=f(); my $z=g(); my $w=h(); print "$x$y$z$w\n";
