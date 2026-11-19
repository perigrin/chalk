sub f { my $r = shift; push @$r, 1; return } my @a; f(\@a); f(\@a); print scalar(@a), "\n";
