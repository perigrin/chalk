sub f { return { a => 1 } } my $n = f()->{a}; my $h = f(); $h->{a} = 5; print "$n $h->{a} ", f()->{a}, "\n";
