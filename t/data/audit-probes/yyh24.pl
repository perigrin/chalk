sub f { my @a=(4,5,6); return @a } sub g { my @a=(4,5,6); return @a[0,1] } sub h { return (4,5,6)[0,1] } my $a1=f(); my $b1=g(); my $c1=h(); print "$a1$b1$c1\n";
