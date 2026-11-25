sub f { return (4,5,6) } my $x=f(); my ($y)=f(); my $n=()=f(); my @a=f(); print "$x$y$n", scalar(@a), "\n";
